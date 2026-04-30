import Foundation
import GRDB

struct Hole: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "hole"

    var id: UUID
    var roundID: UUID
    var holeNumber: Int
    var par: Int?
    var confirmedAt: Date?
}
