import Foundation

/// Where a finished round is showing (Duo v2 plan rule 12): Logbook → the
/// round's card → tap a hole → the round map in review on that hole; ‹ CARD
/// (or Back to card › on the last hole) returns to the card. Immutable: each
/// step returns a new route.
///
/// PR 8 adds `.course` (the card's MAP: every hole on one satellite map, and
/// a tap on a hole glides into `.hole(n)` on the same map).
struct FinishedRoundRoute: Equatable, Sendable {
    enum Screen: Equatable, Sendable {
        case card
        case hole(Int)
    }

    let screen: Screen

    static let card = FinishedRoundRoute(screen: .card)

    /// Opens on the card, or straight on hole `hole` when one is given (the
    /// DEBUG `-DebugReviewHole` launch). Off-card holes open the card.
    static func initial(hole: Int?) -> FinishedRoundRoute {
        guard let hole else { return .card }
        return card.openingHole(hole)
    }

    /// The hole under review; nil on the card.
    var reviewHole: Int? {
        if case let .hole(n) = screen { return n }
        return nil
    }

    /// A hole picked on the card (or ‹ › / Next hole within the review).
    func openingHole(_ number: Int) -> FinishedRoundRoute {
        guard HoleScoring.holeRange.contains(number) else { return self }
        return FinishedRoundRoute(screen: .hole(number))
    }

    func backToCard() -> FinishedRoundRoute { .card }

    func applying(_ next: ReviewNavigation.Next) -> FinishedRoundRoute {
        switch next {
        case let .hole(n): return openingHole(n)
        case .backToCard: return backToCard()
        }
    }
}
