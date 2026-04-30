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
        DatabaseMigrator()
    }
}
