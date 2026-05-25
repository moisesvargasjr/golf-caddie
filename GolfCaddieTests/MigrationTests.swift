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
            ["v1_initial_schema", "v2_curated_course", "v3_curated_link_and_anchors"]
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
