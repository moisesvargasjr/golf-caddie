import Foundation
import GRDB
import XCTest
@testable import GolfCaddie

/// Pins the v1 → v2 → v3 schema evolution. A bad migration on real user data
/// is the one failure mode our field testing can't catch around — this is the
/// most valuable test file in the scaffold.
@MainActor
final class MigrationTests: XCTestCase {

    func test_migrationsRegisteredInOrder() {
        XCTAssertEqual(
            Database.migrator.migrations,
            ["v1_initial_schema", "v2_curated_course", "v3_curated_link_and_anchors",
             "v4_shot_putt_confidence", "v5_custom_clubs"]
        )
    }

    // MARK: - v1

    func test_v1_createsCoreTables() throws {
        let q = try TestDatabase.makeInMemory(upTo: "v1_initial_schema")
        let expected = ["round", "hole", "shot", "penalty", "tracePoint", "clubConfiguration"]
        let tables = try tableNames(q)
        for name in expected {
            XCTAssertTrue(tables.contains(name), "v1 missing table '\(name)' (got \(tables))")
        }
    }

    func test_v1_createsIndexes() throws {
        let q = try TestDatabase.makeInMemory(upTo: "v1_initial_schema")
        let indexes = try indexNames(q)
        let expected = ["hole_roundID_idx", "shot_holeID_idx", "penalty_holeID_idx", "tracePoint_roundID_idx"]
        for idx in expected {
            XCTAssertTrue(indexes.contains(idx), "v1 missing index '\(idx)' (got \(indexes))")
        }
    }

    // MARK: - v2

    func test_v2_addsCuratedTables_withoutTouchingV1Data() throws {
        // v1 first, insert a round, then v2.
        let q = try TestDatabase.makeInMemory(upTo: "v1_initial_schema")
        let roundID = UUID()
        try q.write { db in
            try db.execute(
                sql: """
                INSERT INTO round (id, startedAt, endedAt, courseName, notes)
                VALUES (?, ?, NULL, ?, NULL)
                """,
                arguments: [roundID.uuidString, Date(), "The Oaks"]
            )
        }

        try Database.migrator.migrate(q, upTo: "v2_curated_course")

        // The round survived.
        let surviving = try q.read { db in
            try String.fetchOne(db, sql: "SELECT courseName FROM round WHERE id = ?", arguments: [roundID.uuidString])
        }
        XCTAssertEqual(surviving, "The Oaks")

        // New tables exist.
        let tables = try tableNames(q)
        XCTAssertTrue(tables.contains("curatedCourse"))
        XCTAssertTrue(tables.contains("curatedSyncMeta"))
    }

    // MARK: - v3

    func test_v3_addsCuratedCourseIdToRound_existingRowsAreNull() throws {
        // Migrate to v2 and plant a round (no curatedCourseId column yet).
        let q = try TestDatabase.makeInMemory(upTo: "v2_curated_course")
        let roundID = UUID()
        try q.write { db in
            try db.execute(
                sql: """
                INSERT INTO round (id, startedAt, endedAt, courseName, notes)
                VALUES (?, ?, NULL, NULL, NULL)
                """,
                arguments: [roundID.uuidString, Date()]
            )
        }

        try Database.migrator.migrate(q, upTo: "v3_curated_link_and_anchors")

        // Column exists.
        let columns = try q.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(round)")
                .map { $0["name"] as String? ?? "" }
        }
        XCTAssertTrue(columns.contains("curatedCourseId"), "missing curatedCourseId (got \(columns))")

        // Existing row's value is NULL.
        let curated = try q.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT curatedCourseId FROM round WHERE id = ?",
                arguments: [roundID.uuidString]
            )
        }
        XCTAssertNil(curated)
    }

    func test_v3_createsLocalCourseAnchor_withIndex() throws {
        let q = try TestDatabase.makeInMemory()
        let tables = try tableNames(q)
        XCTAssertTrue(tables.contains("localCourseAnchor"))
        let indexes = try indexNames(q)
        XCTAssertTrue(indexes.contains("localCourseAnchor_course_idx"))
    }

    // MARK: - v5 (B33 custom clubs)

    func test_v5_seedsCatalogWithLegacyIDs() throws {
        let q = try TestDatabase.makeInMemory()
        let rows = try q.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, shortName, kind, isArchived FROM club ORDER BY sortOrder")
        }
        XCTAssertEqual(rows.count, 18)
        XCTAssertEqual(rows.first?["id"] as String?, "driver")
        XCTAssertEqual(rows.last?["id"] as String?, "putter")
        XCTAssertEqual(rows.last?["kind"] as String?, "putter")
        // Every seed id is a legacy ClubID rawValue — the whole point of the
        // zero-data-migration design.
        let legacy = Set(ClubID.allCases.map(\.rawValue))
        for row in rows {
            let id = row["id"] as String? ?? ""
            XCTAssertTrue(legacy.contains(id), "seed id '\(id)' is not a legacy rawValue")
        }
        // Active shortName uniqueness enforced by the partial index.
        let indexes = try indexNames(q)
        XCTAssertTrue(indexes.contains("club_shortName_active_idx"))
    }

    /// The B33 regression guard: a v4 DB with a legacy bagJSON and shot rows
    /// carrying enum rawValues must migrate to v5 with both still readable.
    func test_v5_upgradePreservesLegacyBagAndShots() throws {
        let q = try TestDatabase.makeInMemory(upTo: "v4_shot_putt_confidence")
        let holeID = UUID().uuidString
        let roundID = UUID().uuidString
        try q.write { db in
            try db.execute(
                sql: "INSERT INTO clubConfiguration (id, bagJSON) VALUES (1, ?)",
                arguments: [#"["driver","gapWedge","putter"]"#]
            )
            try db.execute(
                sql: "INSERT INTO round (id, startedAt) VALUES (?, ?)",
                arguments: [roundID, Date()]
            )
            try db.execute(
                sql: "INSERT INTO hole (id, roundID, holeNumber) VALUES (?, ?, 1)",
                arguments: [holeID, roundID]
            )
            try db.execute(
                sql: """
                INSERT INTO shot (id, holeID, sequenceNumber, timestamp, hadGPS, club, source)
                VALUES (?, ?, 1, ?, 0, 'gapWedge', 'manual')
                """,
                arguments: [UUID().uuidString, holeID, Date()]
            )
        }

        try Database.migrator.migrate(q)

        // The legacy shot row still decodes through the Shot model, club intact.
        let shots = try q.read { db in
            try Shot.filter(Column("holeID") == holeID).fetchAll(db)
        }
        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(shots.first?.club, .gapWedge)

        // The legacy bagJSON still decodes (same bytes, same shape).
        let bagJSON = try q.read { db in
            try String.fetchOne(db, sql: "SELECT bagJSON FROM clubConfiguration WHERE id = 1")
        }
        let bag = try JSONDecoder().decode([String].self, from: Data((bagJSON ?? "[]").utf8))
        XCTAssertEqual(bag, ["driver", "gapWedge", "putter"])

        // And each bag id resolves to a seeded club row.
        for id in bag {
            let exists = try q.read { db in
                try Row.fetchOne(db, sql: "SELECT 1 FROM club WHERE id = ?", arguments: [id]) != nil
            }
            XCTAssertTrue(exists, "bag id '\(id)' has no club row after v5")
        }
    }

    // MARK: - Idempotence

    func test_fullMigrationSequence_isIdempotent() throws {
        let q = try TestDatabase.makeInMemory()
        // Re-running the migrator against an already-migrated queue must be a
        // no-op — GRDB tracks applied migration names.
        XCTAssertNoThrow(try Database.migrator.migrate(q))
    }

    // MARK: - helpers

    private func tableNames(_ queue: DatabaseQueue) throws -> [String] {
        try queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'"
            )
        }
    }

    private func indexNames(_ queue: DatabaseQueue) throws -> [String] {
        try queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
            )
        }
    }
}
