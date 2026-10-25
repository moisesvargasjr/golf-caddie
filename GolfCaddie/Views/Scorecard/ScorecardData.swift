import Foundation

/// The card's data for one round, read from the database.
struct ScorecardSnapshot: Equatable {
    let model: ScorecardModel
    /// The curated course's name, when the round is linked to one.
    let courseName: String?
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
        return ScorecardSnapshot(model: model, courseName: course?.name)
    }

    /// Writes the draft through `HoleSession`, so the live hole (if it is the
    /// one) goes through `RoundController` and any other hole through the
    /// repositories — creating its row only now (no empty pre-start rows).
    static func saveHandScore(_ draft: HandScoreDraft, roundID: UUID, live: LiveHoleEditing?) throws {
        let session = HoleSession(roundID: roundID, holeNumber: draft.holeNumber, live: live)
        try session.setHandScore(strokes: draft.strokes, putts: draft.putts)
    }
}

/// The strokes / putts being entered for a hole that wasn't tracked. Each
/// step returns a new draft; the values always pass
/// `HoleScoring.validateHandScore` (strokes 1…30, putts 0…strokes).
struct HandScoreDraft: Equatable, Identifiable {
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

    private func with(strokes: Int? = nil, putts: Int? = nil) -> HandScoreDraft {
        HandScoreDraft(holeNumber: holeNumber, par: par, isEdit: isEdit,
                       strokes: Self.clampStrokes(strokes ?? self.strokes), putts: putts ?? self.putts)
    }

    var canIncrementStrokes: Bool { strokes < HoleScoring.strokeRange.upperBound }
    var canDecrementStrokes: Bool { strokes > HoleScoring.strokeRange.lowerBound }
    var canIncrementPutts: Bool { putts < min(strokes, HoleScoring.puttRange.upperBound) }
    var canDecrementPutts: Bool { putts > HoleScoring.puttRange.lowerBound }

    func incrementingStrokes() -> HandScoreDraft { with(strokes: strokes + 1) }
    /// Putts follow strokes down so they never exceed them.
    func decrementingStrokes() -> HandScoreDraft { with(strokes: strokes - 1) }
    func incrementingPutts() -> HandScoreDraft { canIncrementPutts ? with(putts: putts + 1) : self }
    func decrementingPutts() -> HandScoreDraft { with(putts: putts - 1) }

    /// "PAR", "+1", "-1"; the stroke count when the hole has no par.
    var summary: String {
        guard let par else { return ScorecardText.strokes(strokes).uppercased() }
        let diff = strokes - par
        return diff == 0 ? "PAR" : ScorecardText.toPar(diff)
    }
}
