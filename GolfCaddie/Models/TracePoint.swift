import Foundation
import GRDB

struct TracePoint: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "tracePoint"

    var id: UUID
    var roundID: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var accuracy: Double
}
