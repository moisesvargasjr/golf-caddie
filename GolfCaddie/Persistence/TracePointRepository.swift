import Foundation
import GRDB

/// Breadcrumb trail persistence. The `tracePoint` table has existed since the
/// v1 schema but was unused until live shot logging — these are the continuous
/// GPS fixes the fusion engine matches a watch SwingEvent's timestamp against
/// to assign the shot a coordinate. Rows cascade-delete with their round
/// (FK ON DELETE CASCADE, see RoundRepository.delete).
enum TracePointRepository {
    static func insert(_ point: TracePoint) throws {
        try Database.shared.write { db in try point.insert(db) }
    }

    static func pointsForRound(_ roundID: UUID) throws -> [TracePoint] {
        try Database.shared.read { db in
            try TracePoint.filter(Column("roundID") == roundID)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    /// The round's single trail for every consumer (B38): watch points wherever the
    /// watch covered, phone points elsewhere, time-sorted. Prefer this over
    /// `pointsForRound` unless you specifically need the raw phone breadcrumbs.
    static func preferredTrail(roundID: UUID) throws -> [TracePoint] {
        TrailMerge.preferred(try pointsForRound(roundID))
    }

    /// Insert watch trail points, skipping any whose (round, timestamp, source)
    /// already exists. The point id is derived from the batch, so redelivering a
    /// batch hits the primary key and is ignored too. Returns rows inserted.
    static func insertWatchPoints(_ points: [TracePoint]) throws -> Int {
        guard let first = points.first else { return 0 }
        return try Database.shared.write { db in
            let times = points.map(\.timestamp)
            let existing = try TracePoint
                .filter(Column("roundID") == first.roundID && Column("source") == TracePointSource.watch.rawValue)
                .filter(Column("timestamp") >= times.min()! && Column("timestamp") <= times.max()!)
                .fetchAll(db)
            var seen = Set(existing.map { millis($0.timestamp) })
            var inserted = 0
            for point in points where seen.insert(millis(point.timestamp)).inserted {
                try point.insert(db, onConflict: .ignore)
                inserted += db.changesCount
            }
            return inserted
        }
    }

    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    /// Half-width of the time window `nearest` reads. Far wider than the 10 s the
    /// caller accepts, so span coverage near the target is computed correctly.
    private static let nearestWindowSeconds: TimeInterval = 40

    static func count(forRound roundID: UUID) throws -> Int {
        try Database.shared.read { db in
            try TracePoint.filter(Column("roundID") == roundID).fetchCount(db)
        }
    }

    /// The fusion primitive: the breadcrumb closest in time to a swing event.
    /// A round is bounded (hours), and the golfer is stationary at address, so
    /// the nearest fix is a faithful stand-in for "where the shot was struck"
    /// even with seconds of watch↔phone clock drift. Returns nil if the round
    /// has no breadcrumbs yet (caller falls back to latestLocation).
    static func nearest(toTimestamp target: Date, inRound roundID: UUID) throws -> TracePoint? {
        // Reads a bounded window around the target and takes the nearest point of
        // the PREFERRED trail there (B38: a watch point beats the phone's where the
        // watch covered). A window with nothing in it falls back to the unbounded
        // phone-style bracket, so a sparse round still answers like before.
        let window = target.addingTimeInterval(-nearestWindowSeconds)...target.addingTimeInterval(nearestWindowSeconds)
        let nearby = try Database.shared.read { db in
            try TracePoint.filter(Column("roundID") == roundID)
                .filter(Column("timestamp") >= window.lowerBound && Column("timestamp") <= window.upperBound)
                .fetchAll(db)
        }
        let pool = nearby.isEmpty ? try bracket(target, inRound: roundID) : TrailMerge.preferred(nearby)
        return pool.min {
            abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target))
        }
    }

    /// The point just before and just after `target`, whatever the distance.
    /// GRDB encodes a Date argument to the same lexicographically-ordered string
    /// it stores, so the comparison doesn't depend on SQLite date parsing.
    private static func bracket(_ target: Date, inRound roundID: UUID) throws -> [TracePoint] {
        try Database.shared.read { db in
            let base = TracePoint.filter(Column("roundID") == roundID)
            let before = try base.filter(Column("timestamp") <= target)
                .order(Column("timestamp").desc).fetchOne(db)
            let after = try base.filter(Column("timestamp") >= target)
                .order(Column("timestamp").asc).fetchOne(db)
            return [before, after].compactMap { $0 }
        }
    }

    static func deleteForRound(_ roundID: UUID) throws {
        try Database.shared.write { db in
            _ = try TracePoint.filter(Column("roundID") == roundID).deleteAll(db)
        }
    }
}
