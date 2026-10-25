import Foundation
import GRDB

/// How a hole's score was recorded (v10). `tracked` = strokes are the logged
/// shots plus penalty strokes; `hand` = the golfer typed the score in (a late
/// start's earlier holes, or a casual-mode Finish), held in `handStrokes` /
/// `handPutts`. A NULL column (every pre-v10 row) reads as tracked.
/// `notPlayed` (after build 134) = the golfer marked the hole not played: NP
/// on the card, no score, left out of every total. Stored in the same TEXT
/// column, so it needs no migration.
enum HoleScoreSource: String, Codable, CaseIterable {
    case tracked
    case hand
    case notPlayed
}

struct Hole: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "hole"

    var id: UUID
    var roundID: UUID
    var holeNumber: Int
    var par: Int?
    var confirmedAt: Date?
    /// v10. nil = legacy row, read as `.tracked` (see `effectiveScoreSource`).
    /// Column names match the property names, so the synthesized coding keys
    /// map them with no explicit `CodingKeys`.
    var scoreSource: HoleScoreSource? = nil
    /// v10. The hand-entered gross score (penalties included); only meaningful
    /// when `scoreSource == .hand`.
    var handStrokes: Int? = nil
    /// v10. The hand-entered putt count; nil = not given.
    var handPutts: Int? = nil
    /// v11. The tee shot's finish (FIR); nil = not given.
    var teeShot: TeeShotResult? = nil
    /// v11. The golfer's GIR when they changed it in review; nil = worked out
    /// from the shots (`ScorecardModel.greenInRegulation`).
    var girOverride: Bool? = nil
}

extension Hole {
    var effectiveScoreSource: HoleScoreSource { scoreSource ?? .tracked }
    var isHandScored: Bool { effectiveScoreSource == .hand }
    /// Marked not played: no score, left out of every total.
    var isNotPlayed: Bool { scoreSource == .notPlayed }
}
