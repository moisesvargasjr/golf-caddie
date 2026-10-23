import Foundation
import GRDB

/// Which device recorded a trail point (B38). NULL in the database means `phone`
/// (every row written before v9 is a phone breadcrumb).
enum TracePointSource: String, Codable {
    case phone
    case watch
}

struct TracePoint: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "tracePoint"

    var id: UUID
    var roundID: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var source: TracePointSource? = nil

    var isWatch: Bool { source == .watch }
}
