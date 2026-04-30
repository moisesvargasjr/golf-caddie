import Foundation
import GRDB

struct Round: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "round"

    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var courseName: String?
    var notes: String?
}
