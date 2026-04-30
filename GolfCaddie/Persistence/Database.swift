import Foundation
import GRDB

enum Database {
    static let shared: DatabaseQueue = {
        do {
            return try makeQueue()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }()

    private static func makeQueue() throws -> DatabaseQueue {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = supportDir.appendingPathComponent("golfcaddie.sqlite")
        let queue = try DatabaseQueue(path: dbURL.path)
        try migrator.migrate(queue)
        return queue
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "round") { t in
                t.column("id", .text).primaryKey()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("courseName", .text)
                t.column("notes", .text)
            }

            try db.create(table: "hole") { t in
                t.column("id", .text).primaryKey()
                t.column("roundID", .text).notNull()
                    .references("round", onDelete: .cascade)
                t.column("holeNumber", .integer).notNull()
                t.column("par", .integer)
                t.column("confirmedAt", .datetime)
            }
            try db.create(index: "hole_roundID_idx", on: "hole", columns: ["roundID"])

            try db.create(table: "shot") { t in
                t.column("id", .text).primaryKey()
                t.column("holeID", .text).notNull()
                    .references("hole", onDelete: .cascade)
                t.column("sequenceNumber", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("gpsAccuracy", .double)
                t.column("hadGPS", .boolean).notNull()
                t.column("club", .text)
                t.column("source", .text).notNull()
                t.column("notes", .text)
            }
            try db.create(index: "shot_holeID_idx", on: "shot", columns: ["holeID"])

            try db.create(table: "penalty") { t in
                t.column("id", .text).primaryKey()
                t.column("holeID", .text).notNull()
                    .references("hole", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("strokeCount", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("notes", .text)
            }
            try db.create(index: "penalty_holeID_idx", on: "penalty", columns: ["holeID"])

            try db.create(table: "tracePoint") { t in
                t.column("id", .text).primaryKey()
                t.column("roundID", .text).notNull()
                    .references("round", onDelete: .cascade)
                t.column("timestamp", .datetime).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("accuracy", .double).notNull()
            }
            try db.create(index: "tracePoint_roundID_idx", on: "tracePoint", columns: ["roundID"])

            try db.create(table: "clubConfiguration") { t in
                t.column("id", .integer).primaryKey()
                t.check(sql: "id = 1")
                t.column("bagJSON", .text).notNull()
            }
        }

        return migrator
    }
}
