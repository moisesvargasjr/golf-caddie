import Foundation
import GRDB

enum PenaltyType: String, Codable, CaseIterable, Identifiable {
    case obOrLost
    case water
    case unplayable
    /// Playing a wrong ball: a two-stroke penalty (Rule 6.3c).
    case wrongBall
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .obOrLost: return "OB / Lost"
        case .water: return "Water"
        case .unplayable: return "Unplayable"
        case .wrongBall: return "Wrong ball"
        case .other: return "Other"
        }
    }

    /// Penalty strokes this kind adds — stored per row in `Penalty.strokeCount`
    /// (a v1 column) so a later rule change never rewrites old scores.
    var strokes: Int {
        switch self {
        case .wrongBall: return 2
        case .obOrLost, .water, .unplayable, .other: return 1
        }
    }
}

struct Penalty: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "penalty"

    var id: UUID
    var holeID: UUID
    var type: PenaltyType
    /// Strokes this penalty adds to the hole. Scores sum this, never the row count.
    var strokeCount: Int
    var timestamp: Date
    var notes: String?
}

extension Penalty {
    /// A new penalty row carrying its type's stroke count.
    static func make(holeID: UUID, type: PenaltyType, at timestamp: Date = Date()) -> Penalty {
        Penalty(id: UUID(), holeID: holeID, type: type, strokeCount: type.strokes,
                timestamp: timestamp, notes: nil)
    }
}

extension Sequence where Element == Penalty {
    /// Total penalty STROKES (sum of `strokeCount`), which is what a score adds.
    var totalStrokes: Int { reduce(0) { $0 + $1.strokeCount } }
}
