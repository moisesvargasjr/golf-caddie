import Foundation

/// The card's data for one round, read from the database.
struct ScorecardSnapshot: Equatable {
    let model: ScorecardModel
    /// The curated course's name, when the round is linked to one.
    let courseName: String?
    /// AT THIS COURSE: your best earlier rounds here (`CourseHistory`).
    var history: [CourseHistoryRow] = []
}

/// One earlier round at the same course, as AT THIS COURSE lists it.
struct CourseHistoryRow: Identifiable, Equatable {
    let round: Round
    /// "OCT 05".
    let dateText: String
    let score: Int
    /// "+12", "E"; nil without par.
    let toParText: String?
    let holesScored: Int

    var id: UUID { round.id }
    var isComplete: Bool { holesScored >= HoleScoring.holeRange.count }

    /// "COMPLETE · TRACKED" / "NOT COMPLETE · 14 HOLES".
    var note: String {
        guard isComplete else { return "NOT COMPLETE · \(holesScored) \(holesScored == 1 ? "HOLE" : "HOLES")" }
        switch round.mode {
        case .some(.tracking): return "COMPLETE · TRACKED"
        case .some(.casual): return "COMPLETE · CASUAL"
        case .none: return "COMPLETE"
        }
    }

    var accessibilityLabel: String {
        "Open the \(dateText.lowercased()) round, \(score)" + (toParText.map { ", \($0)" } ?? "")
            + (isComplete ? "" : ", not complete, \(holesScored) holes")
    }
}

/// AT THIS COURSE (Round-Open-History): your 3 best earlier rounds at the
/// round's course, complete rounds first (lowest score), then incomplete ones
/// (most holes) labelled NOT COMPLETE. Pure.
enum CourseHistory {
    static let limit = 3

    /// Same curated course when both are linked, else the same course name.
    static func isSameCourse(_ a: Round, _ b: Round) -> Bool {
        if let x = a.curatedCourseId, let y = b.curatedCourseId { return x == y }
        let name = { (r: Round) in r.courseName?.trimmingCharacters(in: .whitespaces).lowercased() ?? "" }
        return !name(a).isEmpty && name(a) == name(b)
    }

    static func rows(for round: Round, entries: [HomeRoundEntry]) -> [CourseHistoryRow] {
        let rows = entries
            .filter { $0.round.id != round.id && $0.round.endedAt != nil && isSameCourse($0.round, round) }
            .filter { !$0.cells.isEmpty }
            .map { CourseHistoryRow(round: $0.round, dateText: $0.dateText, score: $0.score,
                                    toParText: $0.deltaText, holesScored: $0.cells.count) }
        let complete = rows.filter(\.isComplete).sorted { ($0.score, $0.round.startedAt) < ($1.score, $1.round.startedAt) }
        let partial = rows.filter { !$0.isComplete }
            .sorted { $0.holesScored != $1.holesScored ? $0.holesScored > $1.holesScored : $0.score < $1.score }
        return Array((complete + partial).prefix(limit))
    }
}

/// Loads a round's card and saves hand-entered scores. The only database
/// access the scorecard views make.
@MainActor
enum ScorecardLoader {
    static func load(round: Round, curatedCourseId: String?) throws -> ScorecardSnapshot {
        let holes = try HoleRepository.holesForRound(round.id)
        let inputs = try holes.map { hole in
            ScorecardModel.HoleInput(
                hole: hole,
                shots: try ShotRepository.shotsForHole(hole.id),
                penaltyStrokes: try PenaltyRepository.penaltiesForHole(hole.id).totalStrokes)
        }
        let course = curatedCourseId.flatMap { try? CourseDataRepository.course(byId: $0) }
        let anchors = curatedCourseId.flatMap { try? LocalAnchorRepository.anchorsForCourse($0) } ?? []
        let model = ScorecardModel.build(
            holes: inputs, course: course,
            localAnchors: Dictionary(anchors.map { ($0.holeNumber, $0) }, uniquingKeysWith: { a, _ in a }),
            startingHole: round.startingHole)
        return ScorecardSnapshot(model: model, courseName: course?.name, history: history(for: round))
    }

    /// Earlier rounds at this round's course, scored like Home's entries.
    static func history(for round: Round) -> [CourseHistoryRow] {
        let others = ((try? RoundRepository.allRounds()) ?? [])
            .filter { $0.id != round.id && $0.endedAt != nil && CourseHistory.isSameCourse($0, round) }
        return CourseHistory.rows(for: round, entries: others.compactMap { try? HomeData.entry(for: $0) })
    }

    /// Writes the draft through `HoleSession`, so the live hole (if it is the
    /// one) goes through `RoundController` and any other hole through the
    /// repositories — creating its row only now (no empty pre-start rows).
    static func saveHandScore(_ draft: CardScoreDraft, roundID: UUID, live: LiveHoleEditing?) throws {
        let session = HoleSession(roundID: roundID, holeNumber: draft.holeNumber, live: live)
        try session.setHandScore(strokes: draft.strokes, putts: draft.putts)
    }
}

/// The strokes / putts being entered for a hole that wasn't tracked. Each
/// step returns a new draft; the values always pass
/// `HoleScoring.validateHandScore` (strokes 1…30, putts 0…strokes).
struct CardScoreDraft: Equatable, Identifiable {
    let holeNumber: Int
    let par: Int?
    let isEdit: Bool
    let strokes: Int
    let putts: Int

    var id: Int { holeNumber }

    static let defaultPutts = 2
    /// Strokes to start from when the hole has no par.
    static let defaultStrokes = 4

    /// Starts from the hole's hand score when it has one, else par and 2 putts
    /// (the mockup's defaults).
    init(column: ScorecardColumn) {
        let existing = column.scoreSource == .hand ? column.score : nil
        let strokes = Self.clampStrokes(existing ?? column.par ?? Self.defaultStrokes)
        let putts = existing != nil ? (column.putts ?? Self.defaultPutts) : Self.defaultPutts
        self.init(holeNumber: column.number, par: column.par, isEdit: existing != nil,
                  strokes: strokes, putts: putts)
    }

    private init(holeNumber: Int, par: Int?, isEdit: Bool, strokes: Int, putts: Int) {
        self.holeNumber = holeNumber
        self.par = par
        self.isEdit = isEdit
        self.strokes = strokes
        self.putts = min(max(putts, HoleScoring.puttRange.lowerBound),
                         min(strokes, HoleScoring.puttRange.upperBound))
    }

    private static func clampStrokes(_ n: Int) -> Int {
        min(max(n, HoleScoring.strokeRange.lowerBound), HoleScoring.strokeRange.upperBound)
    }

    private func with(strokes: Int? = nil, putts: Int? = nil) -> CardScoreDraft {
        CardScoreDraft(holeNumber: holeNumber, par: par, isEdit: isEdit,
                       strokes: Self.clampStrokes(strokes ?? self.strokes), putts: putts ?? self.putts)
    }

    var canIncrementStrokes: Bool { strokes < HoleScoring.strokeRange.upperBound }
    var canDecrementStrokes: Bool { strokes > HoleScoring.strokeRange.lowerBound }
    var canIncrementPutts: Bool { putts < min(strokes, HoleScoring.puttRange.upperBound) }
    var canDecrementPutts: Bool { putts > HoleScoring.puttRange.lowerBound }

    func incrementingStrokes() -> CardScoreDraft { with(strokes: strokes + 1) }
    /// Putts follow strokes down so they never exceed them.
    func decrementingStrokes() -> CardScoreDraft { with(strokes: strokes - 1) }
    func incrementingPutts() -> CardScoreDraft { canIncrementPutts ? with(putts: putts + 1) : self }
    func decrementingPutts() -> CardScoreDraft { with(putts: putts - 1) }

    /// "PAR", "+1", "-1"; the stroke count when the hole has no par.
    var summary: String {
        guard let par else { return ScorecardText.strokes(strokes).uppercased() }
        let diff = strokes - par
        return diff == 0 ? "PAR" : ScorecardText.toPar(diff)
    }
}
