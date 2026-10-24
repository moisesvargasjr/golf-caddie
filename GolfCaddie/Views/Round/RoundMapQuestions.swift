import Foundation

// Pure models for the in-panel questions (RoundMapQuestionsTests).

// MARK: - + PENALTY: what happened?

struct PenaltyOption: Identifiable, Equatable, Sendable {
    let type: PenaltyType
    /// Button title, as on the canvas ("OB OR LOST").
    let title: String
    /// What it costs: "+1 · REHIT", "+2".
    let costText: String

    var id: String { type.rawValue }
    var strokes: Int { type.strokes }

    /// Plan rule 8 + Decision 1: OB and lost ball are one type (stroke and
    /// distance); wrong ball costs two.
    static let all: [PenaltyOption] = [
        PenaltyOption(type: .obOrLost, title: "OB OR LOST", costText: cost(.obOrLost, note: "REHIT")),
        PenaltyOption(type: .water, title: "WATER", costText: cost(.water)),
        PenaltyOption(type: .unplayable, title: "UNPLAYABLE", costText: cost(.unplayable)),
        PenaltyOption(type: .wrongBall, title: "WRONG BALL", costText: cost(.wrongBall)),
        PenaltyOption(type: .other, title: "OTHER", costText: cost(.other)),
    ]

    private static func cost(_ type: PenaltyType, note: String? = nil) -> String {
        ["+\(type.strokes)", note].compactMap { $0 }.joined(separator: " · ")
    }

    /// Toast after picking one: "WATER · +1 on hole 8".
    static func addedText(_ type: PenaltyType, holeNumber: Int) -> String {
        let title = all.first { $0.type == type }?.title ?? type.displayName.uppercased()
        return "\(title) · +\(type.strokes) on hole \(holeNumber)"
    }
}

// MARK: - Finish hole: putts 0–4+

enum PuttsQuestionModel {
    /// 0, 1, 2, 3 and "4+" (which records 4), the same as the watch.
    static let options: [Int] = [0, 1, 2, 3, 4]
    static let defaultPutts = 2

    static func label(_ putts: Int) -> String {
        putts >= options.last ?? 4 ? "\(options.last ?? 4)+" : "\(putts)"
    }

    /// Pre-selected answer: the putts already logged, else two.
    static func initialChoice(loggedPutts: Int) -> Int {
        loggedPutts > 0 ? min(loggedPutts, options.last ?? 4) : defaultPutts
    }

    /// Score the hole will get: full shots + penalty strokes + putts.
    static func score(fullShots: Int, penaltyStrokes: Int, putts: Int) -> Int {
        fullShots + max(0, penaltyStrokes) + max(0, putts)
    }

    /// "5 (+1) · 2 SHOTS + 1 PEN + 2 PUTTS" — the line under the options.
    static func summary(fullShots: Int, penaltyStrokes: Int, putts: Int, par: Int?) -> String {
        let total = score(fullShots: fullShots, penaltyStrokes: penaltyStrokes, putts: putts)
        var head = "\(total)"
        if let par { head += " (\(RoundMapFormat.toPar(total - par)))" }
        var parts = ["\(fullShots) \(fullShots == 1 ? "SHOT" : "SHOTS")"]
        if penaltyStrokes > 0 { parts.append("\(penaltyStrokes) PEN") }
        parts.append("\(putts) \(putts == 1 ? "PUTT" : "PUTTS")")
        return head + " · " + parts.joined(separator: " + ")
    }

    /// The confirm button: "Save · hole 9 ›" (wrapping 18 → 1).
    static func confirmTitle(holeNumber: Int) -> String {
        "Save · hole \(holeNumber % HoleScoring.holeRange.upperBound + 1) ›"
    }
}

// MARK: - Hand entry: strokes + putts (late start / skipped holes, tracking)

/// The steppers' working values. Immutable: every step returns a new draft.
struct HandScoreDraft: Equatable, Sendable {
    private(set) var strokes: Int
    private(set) var putts: Int

    init(strokes: Int, putts: Int) {
        let s = Self.clampStrokes(strokes)
        self.strokes = s
        self.putts = Self.clampPutts(putts, strokes: s)
    }

    /// Starts from the hole's hand score, else par and two putts.
    static func initial(hole: Hole?, par: Int?) -> HandScoreDraft {
        HandScoreDraft(strokes: hole?.handStrokes ?? par ?? 4,
                       putts: hole?.handPutts ?? PuttsQuestionModel.defaultPutts)
    }

    func steppingStrokes(by delta: Int) -> HandScoreDraft {
        HandScoreDraft(strokes: strokes + delta, putts: putts)
    }

    func steppingPutts(by delta: Int) -> HandScoreDraft {
        HandScoreDraft(strokes: strokes, putts: putts + delta)
    }

    var canDecreaseStrokes: Bool { strokes > HoleScoring.strokeRange.lowerBound }
    var canIncreaseStrokes: Bool { strokes < HoleScoring.strokeRange.upperBound }
    var canDecreasePutts: Bool { putts > HoleScoring.puttRange.lowerBound }
    var canIncreasePutts: Bool { putts < min(strokes, HoleScoring.puttRange.upperBound) }

    /// "PAR", "+1", "-1" against par; "" without one.
    func summary(par: Int?) -> String {
        guard let par else { return "" }
        let diff = strokes - par
        return diff == 0 ? "PAR" : RoundMapFormat.toPar(diff)
    }

    private static func clampStrokes(_ value: Int) -> Int {
        min(max(value, HoleScoring.strokeRange.lowerBound), HoleScoring.strokeRange.upperBound)
    }

    private static func clampPutts(_ value: Int, strokes: Int) -> Int {
        min(max(value, HoleScoring.puttRange.lowerBound), min(strokes, HoleScoring.puttRange.upperBound))
    }
}

/// Labels for the entry's save button.
enum HandEntryText {
    static func saveTitle(holeNumber: Int, alreadyScored: Bool, advancesHole: Bool) -> String {
        if advancesHole { return PuttsQuestionModel.confirmTitle(holeNumber: holeNumber) }
        return alreadyScored ? "Update hole \(holeNumber)" : "Save hole \(holeNumber)"
    }
}
