import Foundation

// Casual Finish hole: a 1–10+ score grid plus a putts row (0–4+), saved as a
// hand score. Pure, so it is unit tested (ScoreGridModelTests).

/// What the grid saves.
struct ScoreGridResult: Equatable, Sendable {
    let strokes: Int
    let putts: Int
}

enum ScoreGridError: Error, Equatable, LocalizedError {
    /// Save was tapped before a score was picked.
    case noScore

    var errorDescription: String? { "Pick a score first." }
}

/// The grid's working values. Immutable: every pick returns a new draft.
/// Putts never exceed strokes; "10+" and "4+" record 10 and 4 but keep a
/// higher count already stored (a 12 typed in elsewhere stays 12).
struct ScoreGridDraft: Equatable, Sendable {
    let strokes: Int?
    let putts: Int?

    static let empty = ScoreGridDraft(strokes: nil, putts: nil)

    init(strokes: Int?, putts: Int?) {
        let s = strokes.map(Self.clampStrokes)
        self.strokes = s
        self.putts = putts.map { Self.clampPutts($0, strokes: s) }
    }

    /// The hole's hand score when it has one (editing a past casual hole),
    /// else nothing picked — the canvas starts the grid empty.
    static func initial(hole: Hole?) -> ScoreGridDraft {
        guard let hole, hole.isHandScored, let strokes = hole.handStrokes else { return .empty }
        return ScoreGridDraft(strokes: strokes,
                              putts: hole.handPutts ?? min(PuttsQuestionModel.defaultPutts, strokes))
    }

    /// Picks a score cell; putts default to two (one on a 1) the first time.
    func picking(strokes cell: Int) -> ScoreGridDraft {
        let value = Self.keepingHigher(current: strokes, cell: cell, top: ScoreGridModel.topScoreCell)
        return ScoreGridDraft(strokes: value, putts: putts ?? min(PuttsQuestionModel.defaultPutts, value))
    }

    /// Picks a putts cell (clamped to the strokes already picked).
    func picking(putts cell: Int) -> ScoreGridDraft {
        let value = Self.keepingHigher(current: putts, cell: cell, top: ScoreGridModel.topPuttsCell)
        return ScoreGridDraft(strokes: strokes, putts: value)
    }

    var canSave: Bool { strokes != nil }

    /// The hand score to save; validated the same way the store validates it.
    func result() throws -> ScoreGridResult {
        guard let strokes else { throw ScoreGridError.noScore }
        let putts = min(self.putts ?? min(PuttsQuestionModel.defaultPutts, strokes), strokes)
        try HoleScoring.validateHandScore(strokes: strokes, putts: putts)
        return ScoreGridResult(strokes: strokes, putts: putts)
    }

    func isScoreSelected(_ cell: Int) -> Bool {
        strokes.map { min($0, ScoreGridModel.topScoreCell) == cell } ?? false
    }

    func isPuttsSelected(_ cell: Int) -> Bool {
        putts.map { min($0, ScoreGridModel.topPuttsCell) == cell } ?? false
    }

    /// Putts above the picked score can't be chosen.
    func isPuttsAvailable(_ cell: Int) -> Bool {
        strokes.map { cell <= $0 } ?? true
    }

    private static func keepingHigher(current: Int?, cell: Int, top: Int) -> Int {
        guard cell >= top, let current, current >= cell else { return cell }
        return current
    }

    private static func clampStrokes(_ value: Int) -> Int {
        min(max(value, HoleScoring.strokeRange.lowerBound), HoleScoring.strokeRange.upperBound)
    }

    private static func clampPutts(_ value: Int, strokes: Int?) -> Int {
        let ceiling = min(strokes ?? HoleScoring.puttRange.upperBound, HoleScoring.puttRange.upperBound)
        return min(max(value, HoleScoring.puttRange.lowerBound), ceiling)
    }
}

/// Cells, labels and titles for the grid.
enum ScoreGridModel {
    static let scoreCells = Array(1...10)
    static let puttCells = PuttsQuestionModel.options
    static var topScoreCell: Int { scoreCells.last ?? 10 }
    static var topPuttsCell: Int { puttCells.last ?? 4 }

    /// "7", "10+".
    static func scoreLabel(_ cell: Int) -> String {
        cell >= topScoreCell ? "\(topScoreCell)+" : "\(cell)"
    }

    /// "2", "4+".
    static func puttsLabel(_ cell: Int) -> String { PuttsQuestionModel.label(cell) }

    /// "BOGEY" under a cell, against the hole's par.
    static func name(strokes: Int, par: Int?) -> String { ScoreNaming.stamp(strokes: strokes, par: par) }

    static func scoreAccessibilityLabel(_ cell: Int, par: Int?) -> String {
        if cell >= topScoreCell { return "\(topScoreCell) or more" }
        guard let par else { return "\(cell)" }
        return "\(cell), \(ScoreNaming.spoken(strokes: cell, toPar: cell - par))"
    }

    static func puttsAccessibilityLabel(_ cell: Int) -> String {
        if cell >= topPuttsCell { return "\(topPuttsCell) or more putts" }
        return "\(cell) \(cell == 1 ? "putt" : "putts")"
    }

    static func title(holeNumber: Int) -> String { "Score on hole \(holeNumber)?" }

    /// "Pick a score" until one is picked; "Save 5 · hole 9 ›" (side panel)
    /// or "Save 5 · next ›" (sheet) when it moves the round on; "Save 6 ·
    /// hole 3" when editing a past hole.
    static func saveTitle(strokes: Int?, holeNumber: Int, advances: Bool, compact: Bool) -> String {
        guard let strokes else { return "Pick a score" }
        guard advances else { return "Save \(strokes) · hole \(holeNumber)" }
        if compact { return "Save \(strokes) · next ›" }
        return "Save \(strokes) · hole \(holeNumber % HoleScoring.holeRange.upperBound + 1) ›"
    }
}

/// How `RoundScoresList` draws the round so far on each layout.
enum RoundScoresVariant: Equatable, Sendable {
    /// Rows in the side panel (open Duo, book, iPhone landscape).
    case list
    /// A sideways row of chips in the bottom panel (iPhone portrait).
    case chips
    /// Stacked squares in the lower right box (folded).
    case squares
}

extension RoundMapLayout {
    var roundScoresVariant: RoundScoresVariant {
        switch self {
        case .folded: return .squares
        case .phonePortrait: return .chips
        case .openWide, .openPortrait, .book, .phoneLandscape: return .list
        }
    }
}
