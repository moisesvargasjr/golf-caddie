import Foundation

// Duo v2 PR 7: the pure rules behind a finished round's review on the round
// map (RoundReviewTests). The view code only reads these.

// MARK: - Next hole ›

/// Next hole › walks the round in play order: from the starting hole to 18,
/// then (for a round that began later) on from hole 1 to the hole before the
/// start. On the round's last hole it reads Back to card ›. The ‹ › chevrons
/// stay plain 1…18 (`HoleNavigation` with no live hole).
enum ReviewNavigation {
    enum Next: Equatable, Sendable {
        case hole(Int)
        case backToCard

        var title: String {
            switch self {
            case .hole: return "Next hole ›"
            case .backToCard: return "Back to card ›"
            }
        }

        /// Mono caps for the small outlined button beside a score entry.
        var shortTitle: String { title.uppercased() }

        var accessibilityLabel: String {
            switch self {
            case let .hole(n): return "Next hole, hole \(n)"
            case .backToCard: return "Back to the scorecard"
            }
        }
    }

    private static let holes = HoleScoring.holeRange

    /// The round's first hole; out-of-range or missing starts are hole 1.
    static func firstHole(startingHole: Int?) -> Int {
        guard let startingHole, holes.contains(startingHole) else { return holes.lowerBound }
        return startingHole
    }

    /// Every hole once, in the order the round was played.
    static func playOrder(startingHole: Int?) -> [Int] {
        let first = firstHole(startingHole: startingHole)
        return Array(first...holes.upperBound) + Array(holes.lowerBound..<first)
    }

    static func next(after viewing: Int, startingHole: Int?) -> Next {
        let order = playOrder(startingHole: startingHole)
        guard let index = order.firstIndex(of: viewing), index + 1 < order.count else { return .backToCard }
        return .hole(order[index + 1])
    }
}

// MARK: - Text

enum ReviewText {
    /// "RESULT · 3 SHOTS + 2 PUTTS", with "+ 1 PEN" when penalised;
    /// "RESULT · ENTERED BY HAND" for a typed-in score.
    static func resultLabel(fullShots: Int, penaltyStrokes: Int, putts: Int, handScored: Bool) -> String {
        guard !handScored else { return "RESULT · ENTERED BY HAND" }
        var parts = ["\(fullShots) \(fullShots == 1 ? "SHOT" : "SHOTS")"]
        if penaltyStrokes > 0 { parts.append("\(penaltyStrokes) PEN") }
        parts.append("\(putts) \(putts == 1 ? "PUTT" : "PUTTS")")
        return "RESULT · " + parts.joined(separator: " + ")
    }

    /// "+1 · BOGEY", "E · PAR"; "" without a score or a par.
    static func toParLabel(score: Int?, par: Int?) -> String {
        guard let score, let par else { return "" }
        let diff = score - par
        return "\(RoundMapFormat.toPar(diff)) · \(ScoreNaming.spoken(strokes: score, toPar: diff).uppercased())"
    }

    /// The round on the review's cluster / header: "OCT 23 · 79 (+7)". Holes
    /// without a par count toward the total but not the to-par.
    static func roundText(dateText: String, holes: [(par: Int?, score: Int?)]) -> String {
        let scored = holes.compactMap { hole in hole.score.map { (par: hole.par, score: $0) } }
        guard !scored.isEmpty else { return "\(dateText) · NO SCORE" }
        let total = scored.reduce(0) { $0 + $1.score }
        let rated = scored.compactMap { hole in hole.par.map { hole.score - $0 } }
        guard !rated.isEmpty else { return "\(dateText) · \(total)" }
        return "\(dateText) · \(total) (\(RoundMapFormat.toPar(rated.reduce(0, +))))"
    }

    /// "OCT 23" for the round's date.
    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    /// The message that goes with Share round.
    static func shareText(courseName: String?, roundText: String) -> String {
        let course = courseName.flatMap { $0.isEmpty ? nil : $0 } ?? "Golf round"
        return "\(course) · \(roundText) — from The Fairway Logbook"
    }

    static let reviewHint = "DRAG A PIN TO MOVE IT · TAP A SHOT, THEN A CLUB"
}

// MARK: - Putts stepper

/// PUTTS − n + on a finished hole: one putt at a time, within `puttRange`.
enum ReviewPutts {
    static func stepped(_ putts: Int?, by delta: Int) -> Int {
        let range = HoleScoring.puttRange
        return min(max((putts ?? 0) + delta, range.lowerBound), range.upperBound)
    }

    static func canDecrease(_ putts: Int?) -> Bool { (putts ?? 0) > HoleScoring.puttRange.lowerBound }
    static func canIncrease(_ putts: Int?) -> Bool { (putts ?? 0) < HoleScoring.puttRange.upperBound }
}
