import CoreLocation
import Foundation
import GRDB

enum ClubConfigurationRepository {
    private static let singletonID: Int64 = 1

    static func load() throws -> ClubConfiguration {
        try Database.shared.read { db in
            let json = try String.fetchOne(
                db,
                sql: "SELECT bagJSON FROM clubConfiguration WHERE id = ?",
                arguments: [singletonID]
            )
            guard let json else { return .empty }
            let bag = try JSONDecoder().decode([ClubID].self, from: Data(json.utf8))
            return ClubConfiguration(bag: bag)
        }
    }

    static func save(_ config: ClubConfiguration) throws {
        try Database.shared.write { db in
            let data = try JSONEncoder().encode(config.bag)
            let json = String(decoding: data, as: UTF8.self)
            try db.execute(
                sql: """
                INSERT INTO clubConfiguration (id, bagJSON) VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET bagJSON = excluded.bagJSON
                """,
                arguments: [singletonID, json]
            )
        }
    }
}

enum RoundRepository {
    static func insert(_ round: Round) throws {
        try Database.shared.write { db in try round.insert(db) }
    }

    static func update(_ round: Round) throws {
        try Database.shared.write { db in try round.update(db) }
    }

    static func activeRound() throws -> Round? {
        try Database.shared.read { db in
            try Round.filter(Column("endedAt") == nil)
                .order(Column("startedAt").desc)
                .fetchOne(db)
        }
    }

    static func allRounds() throws -> [Round] {
        try Database.shared.read { db in
            try Round.order(Column("startedAt").desc).fetchAll(db)
        }
    }

    /// Manually attach a curated course to a round whose `curatedCourseId`
    /// was never resolved (auto-match missed at round start, or the round
    /// predates curated sync). Distinct from the auto path in
    /// `RoundController.resolveCuratedCourse` — that runs once at startRound
    /// and is then frozen on the round; this lets the user retro-link from
    /// the review screen so green-anchor capture can attach. No-op if the
    /// round is gone.
    static func setCuratedCourseId(roundID: UUID, id: String?) throws {
        try Database.shared.write { db in
            guard var r = try Round.filter(Column("id") == roundID).fetchOne(db)
            else { return }
            r.curatedCourseId = id
            try r.update(db)
        }
    }

    /// Delete a round and its dependent rows (holes → shots/penalties,
    /// tracePoint). FK constraints in the schema cascade automatically; this
    /// just removes the round row. Used from the Logbook to discard old or
    /// junk rounds. No-op if the round is already gone.
    static func delete(_ round: Round) throws {
        try Database.shared.write { db in
            _ = try Round.filter(Column("id") == round.id).deleteAll(db)
        }
    }
}

enum HoleRepository {
    static func insert(_ hole: Hole) throws {
        try Database.shared.write { db in try hole.insert(db) }
    }

    static func update(_ hole: Hole) throws {
        try Database.shared.write { db in try hole.update(db) }
    }

    static func holesForRound(_ roundID: UUID) throws -> [Hole] {
        try Database.shared.read { db in
            try Hole.filter(Column("roundID") == roundID)
                .order(Column("holeNumber"))
                .fetchAll(db)
        }
    }

    /// The existing hole row for a (round, holeNumber), or nil if that hole
    /// hasn't been visited yet. Used by flexible hole navigation to return to a
    /// skipped hole without creating a duplicate row.
    static func hole(forRound roundID: UUID, number: Int) throws -> Hole? {
        try Database.shared.read { db in
            try Hole.filter(Column("roundID") == roundID && Column("holeNumber") == number)
                .fetchOne(db)
        }
    }

    static func hole(byID id: UUID) throws -> Hole? {
        try Database.shared.read { db in
            try Hole.filter(Column("id") == id).fetchOne(db)
        }
    }

    /// Sets par on a hole — including an already-confirmed one — WITHOUT
    /// touching `confirmedAt` or creating a next hole. This is the
    /// previous-hole-editor path, deliberately distinct from
    /// `RoundController.confirmHoleAndAdvance` (which is the only place that
    /// also closes the hole + spawns the next one). Score is derived
    /// everywhere (RoundReviewView, GlassesStateMapper), so changing par alone
    /// is sufficient — no recompute. No-op if the hole no longer exists.
    static func setPar(holeID: UUID, par: Int?) throws {
        try Database.shared.write { db in
            guard var hole = try Hole.filter(Column("id") == holeID).fetchOne(db)
            else { return }
            hole.par = par
            try hole.update(db)
        }
    }
}

enum PenaltyRepository {
    static func insert(_ penalty: Penalty) throws {
        try Database.shared.write { db in try penalty.insert(db) }
    }

    static func delete(_ penalty: Penalty) throws {
        try Database.shared.write { db in
            _ = try penalty.delete(db)
        }
    }

    static func penaltiesForHole(_ holeID: UUID) throws -> [Penalty] {
        try Database.shared.read { db in
            try Penalty.filter(Column("holeID") == holeID)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }
}

enum ShotRepository {
    static func insert(_ shot: Shot) throws {
        try Database.shared.write { db in try shot.insert(db) }
    }

    static func shotsForHole(_ holeID: UUID) throws -> [Shot] {
        try Database.shared.read { db in
            try Shot.filter(Column("holeID") == holeID)
                .order(Column("sequenceNumber"))
                .fetchAll(db)
        }
    }

    static func count(forHole holeID: UUID) throws -> Int {
        try Database.shared.read { db in
            try Shot.filter(Column("holeID") == holeID).fetchCount(db)
        }
    }

    static func nextSequenceNumber(forHole holeID: UUID) throws -> Int {
        try Database.shared.read { db in
            let maxSeq = try Int.fetchOne(
                db,
                sql: "SELECT MAX(sequenceNumber) FROM shot WHERE holeID = ?",
                arguments: [holeID]
            )
            return (maxSeq ?? 0) + 1
        }
    }

    static func update(_ shot: Shot) throws {
        try Database.shared.write { db in try shot.update(db) }
    }

    static func delete(_ shot: Shot) throws {
        try Database.shared.write { db in
            _ = try shot.delete(db)
        }
    }

    /// Deletes the shot and decrements sequenceNumber on every later shot in
    /// the same hole, atomically.
    static func deleteAndRenumber(_ shot: Shot) throws {
        try Database.shared.write { db in
            _ = try shot.delete(db)
            try db.execute(
                sql: """
                UPDATE shot
                SET sequenceNumber = sequenceNumber - 1
                WHERE holeID = ? AND sequenceNumber > ?
                """,
                arguments: [shot.holeID, shot.sequenceNumber]
            )
        }
    }

    static func shotsForRound(_ roundID: UUID) throws -> [Shot] {
        try Database.shared.read { db in
            try Shot.fetchAll(
                db,
                sql: """
                SELECT s.* FROM shot s
                JOIN hole h ON s.holeID = h.id
                WHERE h.roundID = ?
                ORDER BY h.holeNumber, s.sequenceNumber
                """,
                arguments: [roundID]
            )
        }
    }

    /// Inserts a shot at a specific sequence position, shifting any existing
    /// shots at or after that position up by one.
    static func insertShot(_ shot: Shot, at position: Int) throws {
        try Database.shared.write { db in
            try db.execute(
                sql: """
                UPDATE shot
                SET sequenceNumber = sequenceNumber + 1
                WHERE holeID = ? AND sequenceNumber >= ?
                """,
                arguments: [shot.holeID, position]
            )
            var newShot = shot
            newShot.sequenceNumber = position
            try newShot.insert(db)
        }
    }
}

enum CourseDataRepository {
    /// Replace the whole cached catalog with the synced file's courses (the
    /// published file is the full truth, so removed courses get pruned).
    /// Skipped entirely if a course fails to encode — never corrupts the
    /// cache. Atomic.
    static func replaceAll(with courses: [CuratedCourse], fetchedAt: Date) throws {
        let records = courses.compactMap { CuratedCourseRecord.from($0, fetchedAt: fetchedAt) }
        try Database.shared.write { db in
            try CuratedCourseRecord.deleteAll(db)
            for r in records { try r.insert(db) }
        }
    }

    static func course(byId id: String) throws -> CuratedCourse? {
        try Database.shared.read { db in
            try CuratedCourseRecord.filter(Column("id") == id).fetchOne(db)?.decoded()
        }
    }

    static func allCourses() throws -> [CuratedCourse] {
        try Database.shared.read { db in
            try CuratedCourseRecord.fetchAll(db).compactMap { $0.decoded() }
        }
    }

    /// Async-safe wrapper for `allCourses()`. GRDB's synchronous `read` traps
    /// (`unsafeForcedSync called from Swift Concurrent context`) when called
    /// from a `.task`/`.refreshable` closure — see the `.onAppear` note in
    /// ActiveRoundView. `MainActor.run` does NOT fix it (still inside a Task);
    /// hopping through a plain GCD main-queue block exits the cooperative pool
    /// so the sync read is legal. Soft-fails to [] like every call site does.
    static func allCoursesFromAsyncContext() async -> [CuratedCourse] {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                cont.resume(returning: (try? allCourses()) ?? [])
            }
        }
    }

    /// Nearest cached course whose centroid is within `within` metres of the
    /// coordinate, or nil. Tiny dataset → in-Swift haversine is fine.
    static func nearest(
        to coord: CLLocationCoordinate2D,
        within: CLLocationDistance
    ) throws -> CuratedCourse? {
        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let rows = try Database.shared.read { db in try CuratedCourseRecord.fetchAll(db) }
        let scored = rows
            .map { (row: $0, d: CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: origin)) }
            .filter { $0.d <= within }
            .min { $0.d < $1.d }
        return scored?.row.decoded()
    }

    /// Case-insensitive match of a detected course name against a cached
    /// course's name or aliases — the tiebreak/fallback for proximity.
    static func matching(name: String) throws -> CuratedCourse? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return try allCourses().first { course in
            if course.name.lowercased() == needle { return true }
            return course.aliases.contains { $0.lowercased() == needle }
        }
    }

    static func loadSyncMeta() throws -> CuratedSyncMeta {
        try Database.shared.read { db in
            try CuratedSyncMeta.fetchOne(db) ?? CuratedSyncMeta()
        }
    }

    static func saveSyncMeta(_ meta: CuratedSyncMeta) throws {
        try Database.shared.write { db in
            var m = meta
            m.id = 1
            try m.save(db)
        }
    }
}

enum LocalAnchorRepository {
    static func anchor(courseId: String, holeNumber: Int) throws -> LocalCourseAnchor? {
        let id = LocalCourseAnchor.makeID(courseId: courseId, holeNumber: holeNumber)
        return try Database.shared.read { db in
            try LocalCourseAnchor.filter(Column("id") == id).fetchOne(db)
        }
    }

    static func anchorsForCourse(_ courseId: String) throws -> [LocalCourseAnchor] {
        try Database.shared.read { db in
            try LocalCourseAnchor.filter(Column("courseId") == courseId)
                .order(Column("holeNumber"))
                .fetchAll(db)
        }
    }

    /// Upsert one anchor point (tee OR green) for a (course, hole) without
    /// clobbering the other — read-modify-write on the deterministic id.
    static func setPoint(
        courseId: String,
        holeNumber: Int,
        which: AnchorKind,
        point: GeoPoint
    ) throws {
        let id = LocalCourseAnchor.makeID(courseId: courseId, holeNumber: holeNumber)
        try Database.shared.write { db in
            var a = try LocalCourseAnchor.filter(Column("id") == id).fetchOne(db)
                ?? LocalCourseAnchor(
                    id: id,
                    courseId: courseId,
                    holeNumber: holeNumber,
                    teeLat: nil, teeLng: nil,
                    greenLat: nil, greenLng: nil,
                    capturedAt: Date()
                )
            switch which {
            case .tee:
                a.teeLat = point.lat
                a.teeLng = point.lng
            case .green:
                a.greenLat = point.lat
                a.greenLng = point.lng
            }
            a.capturedAt = Date()
            try a.save(db)
        }
    }

    enum AnchorKind { case tee, green }
}
