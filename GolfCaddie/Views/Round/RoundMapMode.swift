import Foundation

/// What `RoundMapScreen` is doing with the hole on screen (Duo v2,
/// Architecture C). One screen, three modes:
///
/// - `.tracking`: the live round with shot tracking.
/// - `.casual`: the live round, score only — the round so far in the panel,
///   Finish hole opens the 1–10+ score grid.
/// - `.review` (PR 7): a finished round. Add the case and answer each trait
///   below; the layouts read only the traits, never the case.
enum RoundMapMode: Equatable, Sendable {
    case tracking
    case casual

    /// Shots are logged as they happen (+ SHOT, pins, the club list).
    var tracksShots: Bool { self == .tracking }

    /// The live hole shows the TO PIN yardage (review shows the result).
    /// Casual keeps it: the casual boards all show the yardage card.
    var showsYardage: Bool { true }

    /// Finish hole asks only for putts (tracking) instead of a score.
    var finishAsksPutts: Bool { finishQuestion == .putts }

    /// The question Finish hole opens on the live hole.
    var finishQuestion: RoundMapQuestion { self == .casual ? .score : .putts }

    /// A hole entered by hand (a past casual hole, a hole before a late
    /// start) uses the 1–10+ score grid instead of the strokes/putts steppers.
    var entryUsesScoreGrid: Bool { self == .casual }

    /// The panel lists the round so far (list / chips / squares by layout)
    /// where tracking lists the hole's shots and clubs.
    var showsRoundSoFar: Bool { self == .casual }

    /// Tag after the par in the hole caption ("PAR 4 · CASUAL").
    var captionTag: String? { self == .casual ? "CASUAL" : nil }

    /// Auto-hide applies at all (review turns it off — plan rule 12).
    var allowsAutoHide: Bool { true }

    /// Holding the map adds a shot.
    var allowsHoldToAdd: Bool { self == .tracking }
}

/// The one open question the panel (or bottom sheet) is asking.
enum RoundMapQuestion: Equatable, Sendable {
    /// Finish hole (tracking): putts 0–4+.
    case putts
    /// + PENALTY: what happened?
    case penalty
    /// Finish hole (casual): score 1–10+ plus a putts row.
    case score
}
