import Foundation
import GRDB

enum ShotSource: String, Codable {
    case button
    case actionButton
    case manual
    case glasses
    case watchAuto // auto-detected by the watch swing detector, fused on the phone
}

struct Shot: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "shot"

    var id: UUID
    var holeID: UUID
    var sequenceNumber: Int
    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
    var gpsAccuracy: Double?
    var hadGPS: Bool
    var club: ClubID?
    var source: ShotSource
    var notes: String?
}
