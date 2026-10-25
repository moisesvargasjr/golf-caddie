import CoreGraphics
import Foundation

// Duo v2 PR 6: the scorecard's pure rules, shared by every card variant so the
// open Duo, the folded Duo and the iPhone agree on what a hole shows and does.

/// Which card a display gets (Duo v2 plan, "Scorecards").
enum ScorecardVariant: String, Equatable, CaseIterable {
    /// Fully open, wide: the traditional double-ruled card, all 18 in one row.
    case traditional
    /// Fully open, portrait: front nine on the top page, back nine below the hinge.
    case frontOverBack
    /// Folded Duo and iPhone portrait: front / back nine tabs.
    case tabs
    /// iPhone landscape: a front-over-back paper card.
    case landscapeCard

    static func resolve(_ context: DisplayContext) -> ScorecardVariant {
        switch (context.layoutClass, context.isLandscape) {
        case (.expanded, true): return .traditional
        case (.expanded, false): return .frontOverBack
        case (.compact, true): return .landscapeCard
        case (.compact, false): return .tabs
        }
    }

    var accessibilityID: String { "scorecard.\(rawValue)" }
}

/// Row sizes for the tabs card: the folded Duo (678 pt tall) uses the tighter
/// rows from its mockup, the taller iPhone the roomier ones.
enum ScorecardTabsMetrics {
    static let tallScreen: CGFloat = 800

    static func rowHeight(windowHeight: CGFloat) -> CGFloat { windowHeight >= tallScreen ? 48 : 40 }
    static func subtotalHeight(windowHeight: CGFloat) -> CGFloat { windowHeight >= tallScreen ? 46 : 40 }
}

enum ScorecardNine: String, Equatable, CaseIterable {
    case front, back

    var holes: ClosedRange<Int> { self == .front ? 1...9 : 10...18 }
    /// OUT / IN.
    var totalLabel: String { self == .front ? "OUT" : "IN" }
    var name: String { self == .front ? "FRONT" : "BACK" }
    var title: String { self == .front ? "Front nine" : "Back nine" }

    /// The nine the live hole is on; the front nine for a finished round.
    static func initial(currentHole: Int?) -> ScorecardNine {
        (currentHole ?? 1) >= 10 ? .back : .front
    }
}

/// What a hole's score cell shows.
enum ScorecardCell: Equatable {
    case score(Int, ScoreMark)
    /// No score to show and one can be typed in: before the starting hole
    /// (Decision 2), or any unscored hole of a finished round.
    case add
    /// The live hole, not finished yet.
    case now
    case blank

    static func resolve(_ column: ScorecardColumn, currentHole: Int?) -> ScorecardCell {
        if column.needsEntry { return .add }
        if let score = column.score { return .score(score, .mark(toPar: column.toPar)) }
        if column.number == currentHole { return .now }
        // A finished round's hole with no score: ADD, like before the start.
        if currentHole == nil, !column.isConfirmed { return .add }
        return .blank
    }
}

/// What picking a hole on the card offers (the CTA under / beside the card).
enum ScorecardPick: Equatable {
    case addScore(Int)
    case editScore(Int)
    /// PR 7 routes this to the hole's review on the map; in the live round it
    /// jumps to that hole.
    case openHole(Int)
    case backToHole(Int)
    case notPlayed(Int)

    static func resolve(_ column: ScorecardColumn, currentHole: Int?) -> ScorecardPick {
        let n = column.number
        if column.needsEntry { return .addScore(n) }
        if n == currentHole { return .backToHole(n) }
        if column.scoreSource == .hand { return .editScore(n) }
        if column.score != nil || column.isConfirmed { return .openHole(n) }
        // A finished round's unscored hole (tracking was missed): type the
        // score straight in. In a live round it is a hole not reached yet.
        if currentHole == nil { return .addScore(n) }
        return .notPlayed(n)
    }

    var holeNumber: Int {
        switch self {
        case let .addScore(n), let .editScore(n), let .openHole(n), let .backToHole(n), let .notPlayed(n):
            return n
        }
    }

    /// `openHole` needs a caller-supplied route; without one it is a no-op, so
    /// the CTA hides.
    func isAvailable(canOpenHole: Bool) -> Bool {
        switch self {
        case .addScore, .editScore, .backToHole: return true
        case .openHole: return canOpenHole
        case .notPlayed: return false
        }
    }

    func title(variant: ScorecardVariant, isFinished: Bool) -> String {
        switch self {
        case let .addScore(n): return "Add hole \(n) score ›"
        case let .editScore(n): return "Edit hole \(n) score ›"
        case let .openHole(n):
            if isFinished { return "Review hole \(n) on the map ›" }
            return variant == .traditional ? "Open hole \(n) on the map ›" : "Open hole \(n) ›"
        case let .backToHole(n): return "Back to hole \(n) ›"
        case .notPlayed: return "Not played yet"
        }
    }
}

/// Every string the cards print or speak.
enum ScorecardText {
    static func toPar(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    static func number(_ value: Int?) -> String { value.map(String.init) ?? "—" }

    static func strokes(_ n: Int) -> String { n == 1 ? "1 stroke" : "\(n) strokes" }
    static func putts(_ n: Int) -> String { n == 1 ? "1 putt" : "\(n) putts" }

    /// "Hole 4, par 3, 4 strokes, 2 putts" / "Hole 2, not tracked, add score".
    static func accessibilityLabel(_ column: ScorecardColumn, currentHole: Int?) -> String {
        var parts = ["Hole \(column.number)"]
        if column.needsEntry { return (parts + ["not tracked, add score"]).joined(separator: ", ") }
        if let par = column.par { parts.append("par \(par)") }
        switch ScorecardCell.resolve(column, currentHole: currentHole) {
        case let .score(score, _):
            parts.append(strokes(score))
            if let p = column.putts { parts.append(putts(p)) }
            if column.scoreSource == .hand { parts.append("entered by hand") }
        case .now: parts.append("in progress")
        case .add: parts.append("no score, add score")
        case .blank: parts.append("not played yet")
        }
        return parts.joined(separator: ", ")
    }

    /// "Out, par 36, 41 strokes, 16 putts".
    static func totalAccessibilityLabel(_ name: String, _ totals: ScorecardTotals) -> String {
        guard let score = totals.score else { return "\(name), no score yet" }
        var parts = [name]
        if let par = totals.par { parts.append("par \(par)") }
        parts.append(strokes(score))
        if let p = totals.putts { parts.append(putts(p)) }
        return parts.joined(separator: ", ")
    }

    /// "1–2, 4, 6–7": runs of consecutive holes collapse to a range.
    static func holeList(_ holes: [Int]) -> String {
        var runs: [(Int, Int)] = []
        for n in holes.sorted() {
            if let last = runs.last, n == last.1 + 1 {
                runs[runs.count - 1] = (last.0, n)
            } else {
                runs.append((n, n))
            }
        }
        return runs.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)–\($0.1)" }.joined(separator: ", ")
    }

    /// The italic note under the front nine on the open-portrait card.
    static func needsEntryNote(_ holes: [Int]) -> String? {
        guard !holes.isEmpty else { return nil }
        if holes.count == 1 { return "Hole \(holes[0]) wasn't tracked. Tap it to add its score." }
        return "Holes \(holeList(holes)) weren't tracked. Tap one to add its score."
    }

    /// The red stamp in the iPhone-landscape header.
    static func needsEntryStamp(_ holes: [Int]) -> String? {
        guard !holes.isEmpty else { return nil }
        return "\(holes.count == 1 ? "HOLE" : "HOLES") \(holeList(holes)) · TAP TO ADD"
    }

    /// The handwritten line in the open card's selected-hole panel.
    static func story(_ column: ScorecardColumn, currentHole: Int?, startingHole: Int?) -> String {
        switch ScorecardCell.resolve(column, currentHole: currentHole) {
        case .add:
            let start = startingHole.map { " — you started on hole \($0)" } ?? ""
            return "Not tracked\(start). Add the score you kept."
        case .now:
            return "You are here. Finish the hole to fill it in."
        case .blank:
            return "Not played yet."
        case let .score(score, _):
            guard column.scoreSource == .hand else { return column.story ?? strokes(score) }
            var parts = [strokes(score)]
            if let p = column.putts { parts.append(putts(p)) }
            let start = startingHole.map { " (you started on \($0))" } ?? ""
            parts.append("entered by hand\(start)")
            return parts.joined(separator: " · ")
        }
    }

    /// "4H 05M"; nil while the round is open.
    static func duration(from start: Date, to end: Date?) -> String? {
        guard let end, end > start else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return String(format: "%dH %02dM", minutes / 60, minutes % 60)
    }

    /// "IN PROGRESS · THRU 7" / "TRACKED · 4H 05M".
    static func status(round: Round, scored: Int) -> String {
        guard round.endedAt != nil else { return "IN PROGRESS · THRU \(scored)" }
        let kind: String
        switch round.mode {
        case .some(.tracking): kind = "TRACKED"
        case .some(.casual): kind = "CASUAL"
        case .none: kind = "FINISHED"
        }
        return [kind, duration(from: round.startedAt, to: round.endedAt)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The way back out: to the live hole's map, or to the logbook.
    static func dismissTitle(variant: ScorecardVariant, currentHole: Int?) -> String {
        guard let currentHole else { return "‹ LOGBOOK" }
        switch variant {
        case .traditional: return "‹ HOLE \(currentHole)"
        case .frontOverBack: return "BACK TO MAP"
        case .tabs, .landscapeCard: return "MAP"
        }
    }
}

extension ScorecardModel {
    func columns(_ nine: ScorecardNine) -> [ScorecardColumn] { nine == .front ? front : back }
    func totals(_ nine: ScorecardNine) -> ScorecardTotals { nine == .front ? out : inn }
    func girCount(_ nine: ScorecardNine) -> Int { columns(nine).filter { $0.gir == true }.count }
    func firCount(_ nine: ScorecardNine) -> Int { columns(nine).filter { $0.teeShot == .fairway }.count }

    /// Holes with a score on the card (ADD holes and unplayed holes excluded).
    var scoredCount: Int { columns.filter { $0.score != nil }.count }

    func column(_ number: Int) -> ScorecardColumn? {
        columns.first { $0.number == number }
    }
}
