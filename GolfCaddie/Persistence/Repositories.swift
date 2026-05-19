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
