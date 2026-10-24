import CoreLocation
import Foundation
import GRDB

// Duo v2 hole editing (PR 2): the writes `HoleSession` routes to for holes that
// aren't the live one, and that `RoundController` reuses for the live hole.

extension RoundRepository {
    static func round(id: UUID) throws -> Round? {
        try Database.shared.read { db in try Round.fetchOne(db, key: id) }
    }
}

extension HoleRepository {
    /// Records a hand-entered score for (round, holeNumber) — a hole played
    /// before a late start, or a casual Finish. Creates the hole row ONLY here,
    /// when a score is entered, so a late start leaves no empty rows behind.
    /// Marks the hole `.hand`, and confirms it if it wasn't (a hand score is
    /// the final answer for that hole). Logged shots/penalties are kept but no
    /// longer count toward the score (see `HoleScoring`). Returns the row.
    @discardableResult
    static func setHandScore(roundID: UUID, holeNumber: Int, strokes: Int, putts: Int?,
                             at date: Date = Date()) throws -> Hole {
        guard HoleScoring.holeRange.contains(holeNumber) else {
            throw HoleEditError.invalidHoleNumber(holeNumber)
        }
        try HoleScoring.validateHandScore(strokes: strokes, putts: putts)
        return try Database.shared.write { db in
            let existing = try Hole
                .filter(Column("roundID") == roundID && Column("holeNumber") == holeNumber)
                .fetchOne(db)
            var hole = existing ?? Hole(id: UUID(), roundID: roundID, holeNumber: holeNumber,
                                        par: nil, confirmedAt: nil)
            hole.scoreSource = .hand
            hole.handStrokes = strokes
            hole.handPutts = putts
            hole.confirmedAt = hole.confirmedAt ?? date
            if existing == nil { try hole.insert(db) } else { try hole.update(db) }
            return hole
        }
    }
}

extension ShotRepository {
    /// Inserts a hand-placed shot at `coordinate` on a hole, numbered by its
    /// position along the hole (`ShotInsertOrdering`). The pin snaps to the
    /// walking path within 8 m first (`ShotPlacement.pinned`) and is saved as
    /// `.manual`, so trail re-placement never moves it. `now` is the live-hole
    /// clock (nil for a past hole, whose new shot is timed between neighbours).
    @discardableResult
    static func insertShot(at coordinate: CLLocationCoordinate2D, holeID: UUID, club: Club?,
                           anchors: HolePathAnchors = .none, now: Date? = nil) throws -> Shot {
        let existing = try shotsForHole(holeID)
        let drafted = Shot(
            id: UUID(), holeID: holeID, sequenceNumber: 0, timestamp: now ?? Date(),
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            gpsAccuracy: nil, hadGPS: true, club: club?.id, source: .manual, notes: nil,
            isPutt: Shot.derivedIsPutt(club: club), locationSource: .manual)
        var shot = ShotPlacement.pinned(drafted, at: coordinate)
        let placed = CLLocationCoordinate2D(latitude: shot.latitude ?? coordinate.latitude,
                                            longitude: shot.longitude ?? coordinate.longitude)
        let position = ShotInsertOrdering.position(for: placed, among: existing, anchors: anchors)
        shot.sequenceNumber = position
        shot.timestamp = ShotInsertOrdering.timestamp(forPosition: position, among: existing, now: now)
        try insertShot(shot, at: position)
        return shot
    }

    /// Makes the hole's putt count `count`: removes the last putts (closing the
    /// gaps) or appends unlocated putter strokes at the end, in one write.
    /// Full shots are untouched. For tracked holes; hand-scored holes keep
    /// their putts in `Hole.handPutts`.
    static func setPuttCount(_ count: Int, holeID: UUID, putterID: String?, now: Date = Date()) throws {
        guard HoleScoring.puttRange.contains(count) else { throw HoleEditError.invalidPutts(count) }
        try Database.shared.write { db in
            let active = try Shot.filter(Column("holeID") == holeID && Column("excludedAt") == nil)
                .order(Column("sequenceNumber"))
                .fetchAll(db)
            let putts = active.filter(\.isPutt)
            if count < putts.count {
                // Highest sequence first, so each renumber leaves the rest valid.
                for shot in putts.suffix(putts.count - count).reversed() {
                    _ = try shot.delete(db)
                    try db.execute(
                        sql: "UPDATE shot SET sequenceNumber = sequenceNumber - 1 WHERE holeID = ? AND sequenceNumber > ?",
                        arguments: [holeID, shot.sequenceNumber])
                }
            } else if count > putts.count {
                let maxSeq = try Int.fetchOne(
                    db, sql: "SELECT MAX(sequenceNumber) FROM shot WHERE holeID = ?", arguments: [holeID]) ?? 0
                let base = active.last?.timestamp ?? now
                for i in 1...(count - putts.count) {
                    let putt = Shot(
                        id: UUID(), holeID: holeID, sequenceNumber: maxSeq + i,
                        timestamp: base.addingTimeInterval(Double(i)),
                        latitude: nil, longitude: nil, gpsAccuracy: nil, hadGPS: false,
                        club: putterID, source: .manual, notes: nil, isPutt: true)
                    try putt.insert(db)
                }
            }
        }
    }
}

extension ClubRepository {
    /// First putter-kind club in `preferred` (the clubs in play), else the
    /// first active putter. nil only if the catalog has none.
    static func putter(preferring preferred: [Club] = []) -> Club? {
        if let inPlay = preferred.first(where: { $0.kind == .putter }) { return inPlay }
        return ((try? all()) ?? []).first { $0.kind == .putter }
    }
}

extension ShotPlacement {
    /// A pin the golfer dragged: snapped + `.manual` (`pinned`), and full
    /// confidence — a hand placement is ground truth and clears the amber cue.
    static func dragged(_ shot: Shot, to coordinate: CLLocationCoordinate2D) -> Shot {
        var moved = pinned(shot, at: coordinate)
        moved.confidence = 1.0
        return moved
    }
}
