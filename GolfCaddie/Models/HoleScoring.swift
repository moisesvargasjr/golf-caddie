import Foundation

/// The one scoring rule every surface shares, so hand scores, penalty strokes
/// and "not tracked" holes read the same on the scorecard, the hole screen and
/// the totals. Pure.
enum HoleScoring {
    /// Bounds for a hand-entered score (the casual grid goes 1–10+).
    static let strokeRange = 1...30
    static let puttRange = 0...20
    /// Hole numbers on the card (mirrors `RoundController.holesPerRound`).
    static let holeRange = 1...18

    /// Gross score for a hole: the hand score when it was entered by hand,
    /// otherwise strokes logged + penalty strokes. nil when there is no hole
    /// row, a hand-scored row has no strokes, or the hole was marked not played.
    static func score(hole: Hole?, shots: [Shot], penaltyStrokes: Int) -> Int? {
        guard let hole, !hole.isNotPlayed else { return nil }
        if hole.isHandScored { return hole.handStrokes }
        return shots.count + penaltyStrokes
    }

    /// Putts: the hand count for a hand-scored hole, else the putt-flagged shots.
    static func putts(hole: Hole?, shots: [Shot]) -> Int? {
        guard let hole, !hole.isNotPlayed else { return nil }
        if hole.isHandScored { return hole.handPutts }
        return shots.filter(\.isPutt).count
    }

    /// A hole before the round's starting hole that has no score yet: the
    /// scorecard shows ADD and leaves it out of the totals (Decision 2).
    static func needsEntry(holeNumber: Int, startingHole: Int?, hole: Hole?,
                           hasTrackedData: Bool) -> Bool {
        guard let startingHole, holeNumber < startingHole, hole?.isNotPlayed != true else { return false }
        if let hole, hole.isHandScored, hole.handStrokes != nil { return false }
        return !hasTrackedData
    }

    /// The holes End round offers to mark not played: the live hole and the
    /// ones after it with no score yet, up to 18 — or, once a round that began
    /// on the back nine has wrapped onto the front, up to the hole before its
    /// start. `scored` holds the numbers that have one. Holes before a late
    /// start are left for ADD (they were played, just not tracked).
    static func remainingUnscored(liveHole: Int, startingHole: Int?, scored: Set<Int>) -> [Int] {
        let start = startingHole ?? 1
        let last = liveHole >= start ? holeRange.upperBound : start - 1
        guard liveHole <= last else { return [] }
        return (liveHole...last).filter { !scored.contains($0) }
    }

    /// Throws unless `strokes`/`putts` are a plausible hand score.
    static func validateHandScore(strokes: Int, putts: Int?) throws {
        guard strokeRange.contains(strokes) else { throw HoleEditError.invalidStrokes(strokes) }
        if let putts {
            guard puttRange.contains(putts), putts <= strokes else { throw HoleEditError.invalidPutts(putts) }
        }
    }
}

enum HoleEditError: Error, Equatable, LocalizedError {
    case invalidStrokes(Int)
    case invalidPutts(Int)
    case invalidHoleNumber(Int)
    /// The shot or penalty is no longer on this hole.
    case notFound

    var errorDescription: String? {
        switch self {
        case let .invalidStrokes(n): return "\(n) isn't a valid score for a hole."
        case let .invalidPutts(n): return "\(n) isn't a valid number of putts."
        case let .invalidHoleNumber(n): return "Hole \(n) isn't on the card."
        case .notFound: return "That item was already removed."
        }
    }
}
