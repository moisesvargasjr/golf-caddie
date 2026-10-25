import Foundation

/// Where a finished round is showing (Duo v2 plan rule 12): Logbook → the
/// round's card → tap a hole → the round map in review on that hole; ‹ CARD
/// (or Back to card › on the last hole) returns to the card. Immutable: each
/// step returns a new route.
///
/// PR 8: the card's MAP opens `.course` — every hole on one satellite map. A
/// tap on a hole glides into `.hole(n)` on that SAME map (`showsMap` stays
/// true, so `FinishedRoundScreen` keeps one `RoundMapScreen` alive), and
/// COURSE MAP glides back out to `.course`.
struct FinishedRoundRoute: Equatable, Sendable {
    enum Screen: Equatable, Sendable {
        case card
        case course
        case hole(Int)
    }

    let screen: Screen

    static let card = FinishedRoundRoute(screen: .card)

    /// Opens on the card, or straight on hole `hole` when one is given (the
    /// DEBUG `-DebugReviewHole` launch), or on the course map (`-DebugOpen
    /// course-map`). Off-card holes open the card (or the course map).
    static func initial(hole: Int?, courseMap: Bool = false) -> FinishedRoundRoute {
        let start = courseMap ? card.openingCourse() : card
        guard let hole else { return start }
        return start.openingHole(hole)
    }

    /// The hole under review; nil on the card and the course map.
    var reviewHole: Int? {
        if case let .hole(n) = screen { return n }
        return nil
    }

    /// The round map is on screen (course map or a hole's review).
    var showsMap: Bool { screen != .card }

    /// The whole-course pose of the map.
    var showsCourse: Bool { screen == .course }

    /// A hole picked on the card or the course map (or ‹ › / Next hole
    /// within the review).
    func openingHole(_ number: Int) -> FinishedRoundRoute {
        guard HoleScoring.holeRange.contains(number) else { return self }
        return FinishedRoundRoute(screen: .hole(number))
    }

    /// MAP on the card, or COURSE MAP in a hole's review.
    func openingCourse() -> FinishedRoundRoute { FinishedRoundRoute(screen: .course) }

    func backToCard() -> FinishedRoundRoute { .card }

    func applying(_ next: ReviewNavigation.Next) -> FinishedRoundRoute {
        switch next {
        case let .hole(n): return openingHole(n)
        case .backToCard: return backToCard()
        }
    }
}
