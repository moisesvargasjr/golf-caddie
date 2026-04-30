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
