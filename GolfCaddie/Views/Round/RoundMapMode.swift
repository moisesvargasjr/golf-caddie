import Foundation

/// What `RoundMapScreen` is doing with the hole on screen (Duo v2,
/// Architecture C). One screen, three modes:
///
/// - `.tracking`: the live round with shot tracking.
/// - `.casual`: the live round, score only — the round so far in the panel,
///   Finish hole opens the 1–10+ score grid.
/// - `.review` (PR 7): a finished round (`live: nil`). The result card
///   instead of the yardage, Next hole › instead of Finish hole, no + SHOT,
///   watch status or auto-hide; pins, clubs, putts and penalties stay
///   editable. The layouts read only the traits below, never the case.
enum RoundMapMode: Equatable, Sendable {
    case tracking
    case casual
    case review

    /// Shots show as pins with the shot list and club list (+ SHOT itself
    /// only on the live hole, which review never has).
    var tracksShots: Bool { self != .casual }

    /// The live hole shows the TO PIN yardage (review shows the result).
    /// Casual keeps it: the casual boards all show the yardage card.
    var showsYardage: Bool { self != .review }

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
    var captionTag: String? {
        switch self {
        case .tracking: return nil
        case .casual: return "CASUAL"
        case .review: return "REVIEW"
        }
    }

    /// Auto-hide applies at all (review turns it off — plan rule 12).
    var allowsAutoHide: Bool { self != .review }

    /// Review auto-hides too on the folded Duo (Review-Folded-v2-Clear): its
    /// one bottom panel covers much of the small screen.
    func allowsAutoHide(on layout: RoundMapLayout) -> Bool { allowsAutoHide || layout == .folded }

    /// Holding the map adds a shot.
    var allowsHoldToAdd: Bool { self != .casual }

    /// The panel's primary is Next hole › (Back to card › on the last hole)
    /// instead of Finish hole / Back to hole N.
    var advancesWithNextHole: Bool { self == .review }

    /// "WATCH IS DETECTING SWINGS" and other live-watch hints.
    var showsWatchStatus: Bool { self != .review }

    /// The result card carries a PUTTS − n + stepper (Review-* boards).
    var editsPuttsInResult: Bool { self == .review }

    /// CARD opens the live card; in review it goes back to the round's card.
    var cardButtonTitle: String { self == .review ? "‹ CARD" : "CARD" }
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
