import Foundation
import GRDB

enum PenaltyType: String, Codable, CaseIterable, Identifiable {
    case obOrLost
    case water
    case unplayable
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .obOrLost: return "OB / Lost"
        case .water: return "Water"
        case .unplayable: return "Unplayable"
        case .other: return "Other"
        }
    }
}

struct Penalty: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "penalty"

    var id: UUID
    var holeID: UUID
    var type: PenaltyType
    var strokeCount: Int
    var timestamp: Date
    var notes: String?
}
