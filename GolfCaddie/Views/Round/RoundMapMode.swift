import Foundation

/// What `RoundMapScreen` is doing with the hole on screen (Duo v2,
/// Architecture C). One screen, three modes:
///
/// - `.tracking` (this PR): the live round with shot tracking.
/// - `.casual`: the live round, score only. Until PR 5 lands the score grid it
///   is a stop-gap — the panel shows the strokes/putts entry for the live hole.
/// - `.review` (PR 7): a finished round. Add the case and answer each trait
///   below; the layouts read only the traits, never the case.
enum RoundMapMode: Equatable, Sendable {
    case tracking
    case casual

    /// Shots are logged as they happen (+ SHOT, pins, the club list).
    var tracksShots: Bool { self == .tracking }

    /// The live hole shows the TO PIN yardage (review shows the result).
    var showsYardage: Bool { true }

    /// Finish hole asks only for putts (tracking) instead of a score entry.
    var finishAsksPutts: Bool { self == .tracking }

    /// The live hole is entered by hand (strokes + putts) instead of tracked.
    var liveHoleIsHandEntry: Bool { self == .casual }

    /// Auto-hide applies at all (review turns it off — plan rule 12).
    var allowsAutoHide: Bool { true }

    /// Holding the map adds a shot.
    var allowsHoldToAdd: Bool { self == .tracking }
}

/// The one open question the panel (or bottom sheet) is asking.
enum RoundMapQuestion: Equatable, Sendable {
    /// Finish hole: putts 0–4+.
    case putts
    /// + PENALTY: what happened?
    case penalty
}
