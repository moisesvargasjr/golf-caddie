import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// Duo v2 data rules: penalty STROKES (wrong ball = 2) drive scores, hand
/// scores count in totals, and holes before a late start with no entry are
/// flagged (ADD) and left out of the totals.
@MainActor
final class HandScoreAndPenaltyTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    // MARK: - Penalty strokes

    func testWrongBallIsTwoStrokesAndObStaysOne() {
        XCTAssertEqual(PenaltyType.wrongBall.strokes, 2)
        XCTAssertEqual(PenaltyType.obOrLost.strokes, 1)
        XCTAssertEqual(PenaltyType.water.strokes, 1)
        XCTAssertEqual(Penalty.make(holeID: UUID(), type: .wrongBall).strokeCount, 2)
    }

    func testWatchKindsStayInLockstepWithWrongBall() {
        XCTAssertNotNil(WatchPenaltyKind(rawValue: PenaltyType.wrongBall.rawValue))
    }

    func testLiveWrongBallAddsTwoStrokes() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(mode: .tracking)
        try controller.addPenaltyToCurrentHole(type: .wrongBall)
        try controller.addPenaltyToCurrentHole(type: .obOrLost)
        XCTAssertEqual(controller.currentHolePenaltyStrokes, 3)
        let hole = try XCTUnwrap(controller.currentHole)
        XCTAssertEqual(try PenaltyRepository.penaltiesForHole(hole.id).map(\.strokeCount).sorted(), [1, 2])
    }

    func testScoreUsesPenaltyStrokesNotRows() throws {
        let hole = Hole(id: UUID(), roundID: UUID(), holeNumber: 1, par: 4, confirmedAt: Date())
        let shots = (1...4).map { ScorecardModelTests.shot(hole.id, $0, club: nil) }
        let penalties = [Penalty.make(holeID: hole.id, type: .wrongBall)]
        XCTAssertEqual(HoleScoring.score(hole: hole, shots: shots, penaltyStrokes: penalties.totalStrokes), 6)
        let model = ScorecardModel.build(
            holes: [.init(hole: hole, shots: shots, penaltyStrokes: penalties.totalStrokes)], course: nil)
        XCTAssertEqual(model.columns[0].score, 6)
        XCTAssertEqual(model.columns[0].penalties, 2)
    }

    // MARK: - setHandScore

    func testHandScoreCreatesTheRowOnlyWhenEntered() throws {
        let round = try TestDatabase.seedRound()
        try TestDatabase.seedHole(roundID: round.id, holeNumber: 4)
        XCTAssertNil(try HoleRepository.hole(forRound: round.id, number: 2), "no empty rows before the start")

        let hole = try HoleRepository.setHandScore(roundID: round.id, holeNumber: 2, strokes: 5, putts: 2)

        XCTAssertEqual(try HoleRepository.holesForRound(round.id).map(\.holeNumber), [2, 4])
        XCTAssertEqual(hole.scoreSource, .hand)
        XCTAssertEqual(hole.handStrokes, 5)
        XCTAssertEqual(hole.handPutts, 2)
        XCTAssertNotNil(hole.confirmedAt)
        XCTAssertNil(try HoleRepository.hole(forRound: round.id, number: 1), "only the entered hole")
    }

    func testHandScoreUpdatesAnExistingRowInPlace() throws {
        let round = try TestDatabase.seedRound()
        let existing = try TestDatabase.seedHole(roundID: round.id, holeNumber: 3, par: 4)
        try HoleRepository.setHandScore(roundID: round.id, holeNumber: 3, strokes: 4, putts: nil)
        let updated = try HoleRepository.setHandScore(roundID: round.id, holeNumber: 3, strokes: 7, putts: 3)
        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.par, 4)
        XCTAssertEqual(try HoleRepository.holesForRound(round.id).count, 1)
        XCTAssertEqual(try HoleRepository.hole(byID: existing.id)?.handStrokes, 7)
    }

    func testHandScoreRejectsImpossibleValues() throws {
        let round = try TestDatabase.seedRound()
        XCTAssertThrowsError(try HoleRepository.setHandScore(roundID: round.id, holeNumber: 1, strokes: 0, putts: nil))
        XCTAssertThrowsError(try HoleRepository.setHandScore(roundID: round.id, holeNumber: 1, strokes: 3, putts: 4))
        XCTAssertThrowsError(try HoleRepository.setHandScore(roundID: round.id, holeNumber: 19, strokes: 3, putts: 1))
        XCTAssertTrue(try HoleRepository.holesForRound(round.id).isEmpty, "nothing written on a rejected entry")
    }

    // MARK: - Scorecard totals

    private func trackedInput(_ number: Int, roundID: UUID, strokes: Int, putts: Int) -> ScorecardModel.HoleInput {
        ScorecardModelTests.input(number, par: 4, full: strokes - putts, putts: putts, roundID: roundID)
    }

    private func handInput(_ number: Int, roundID: UUID, strokes: Int, putts: Int?) -> ScorecardModel.HoleInput {
        let hole = Hole(id: UUID(), roundID: roundID, holeNumber: number, par: 4, confirmedAt: Date(),
                        scoreSource: .hand, handStrokes: strokes, handPutts: putts)
        return .init(hole: hole, shots: [], penaltyStrokes: 0)
    }

    func testHandScoredHolesCountInTotals() {
        let roundID = UUID()
        let model = ScorecardModel.build(holes: [
            handInput(1, roundID: roundID, strokes: 6, putts: 2),
            trackedInput(2, roundID: roundID, strokes: 5, putts: 2),
        ], course: nil, startingHole: 2)
        XCTAssertEqual(model.columns[0].score, 6)
        XCTAssertEqual(model.columns[0].putts, 2)
        XCTAssertEqual(model.columns[0].scoreSource, .hand)
        XCTAssertNil(model.columns[0].gir, "no shots to judge GIR from")
        XCTAssertFalse(model.columns[0].needsEntry)
        XCTAssertEqual(model.out.score, 11)
        XCTAssertEqual(model.out.putts, 4)
    }

    func testHolesBeforeTheStartWithoutEntryAreFlaggedAndExcluded() {
        let roundID = UUID()
        let model = ScorecardModel.build(holes: [
            handInput(2, roundID: roundID, strokes: 5, putts: nil),
            trackedInput(4, roundID: roundID, strokes: 4, putts: 2),
            trackedInput(5, roundID: roundID, strokes: 3, putts: 1),
        ], course: nil, startingHole: 4)
        XCTAssertEqual(model.holesNeedingEntry, [1, 3])
        XCTAssertNil(model.columns[0].score)
        XCTAssertNil(model.columns[2].score)
        XCTAssertFalse(model.columns[3].needsEntry, "the starting hole itself is tracked")
        XCTAssertFalse(model.columns[6].needsEntry, "holes after the start aren't ADD")
        XCTAssertEqual(model.out.score, 12, "5 by hand + 4 + 3; ADD holes left out")
    }

    func testLegacyRoundsFlagNothing() {
        let model = ScorecardModel.build(
            holes: [trackedInput(4, roundID: UUID(), strokes: 4, putts: 2)], course: nil)
        XCTAssertTrue(model.holesNeedingEntry.isEmpty)
    }

    // MARK: - startRound(startingHole:mode:)

    func testStartRoundPersistsModeAndStartingHoleWithoutEarlierRows() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(startingHole: 5, mode: .casual)
        let round = try XCTUnwrap(controller.currentRound)
        XCTAssertTrue(controller.isCasualMode)
        let stored = try XCTUnwrap(try RoundRepository.round(id: round.id))
        XCTAssertEqual(stored.mode, .casual)
        XCTAssertEqual(stored.startingHole, 5)
        XCTAssertEqual(try HoleRepository.holesForRound(round.id).map(\.holeNumber), [5])
    }

    func testTrackingModeStartsTracking() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(startingHole: 1, mode: .tracking)
        XCTAssertFalse(controller.isCasualMode)
        XCTAssertEqual(controller.currentRound?.mode, .tracking)
    }

    func testLiveHandScoreSurvivesConfirm() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(startingHole: 1, mode: .casual)
        let hole = try XCTUnwrap(controller.currentHole)
        try controller.setHandScoreOnCurrentHole(strokes: 5, putts: 2)
        try controller.confirmHoleAndAdvance(par: 4)
        let stored = try XCTUnwrap(try HoleRepository.hole(byID: hole.id))
        XCTAssertEqual(stored.scoreSource, .hand)
        XCTAssertEqual(stored.handStrokes, 5)
        XCTAssertEqual(stored.par, 4)
    }

    // MARK: - setPuttCount

    func testSetPuttCountTrimsAndAppendsPutts() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1, club: "driver")
        try TestDatabase.seedShot(holeID: hole.id, sequence: 2, club: "sevenIron")

        try ShotRepository.setPuttCount(3, holeID: hole.id, putterID: Club.putterID)
        var shots = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(shots.map(\.isPutt), [false, false, true, true, true])
        XCTAssertEqual(shots.map(\.sequenceNumber), [1, 2, 3, 4, 5])

        try ShotRepository.setPuttCount(1, holeID: hole.id, putterID: Club.putterID)
        shots = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(shots.map(\.isPutt), [false, false, true])
        XCTAssertEqual(shots.map(\.sequenceNumber), [1, 2, 3])
        XCTAssertThrowsError(try ShotRepository.setPuttCount(-1, holeID: hole.id, putterID: nil))
    }
}

// MARK: - Par after a course re-link

extension HandScoreAndPenaltyTests {
    func testAnAutoFilledParFollowsTheNewCourse() {
        // Linked The Fountains by mistake (hole 1 par 3), then The Vineyard (par 4).
        XCTAssertEqual(CourseRelinkPars.parAfterRelink(current: 3, previousCoursePar: 3, newCoursePar: 4), .some(4))
    }

    func testAHandTypedParStays() {
        XCTAssertNil(CourseRelinkPars.parAfterRelink(current: 5, previousCoursePar: 3, newCoursePar: 4))
    }

    func testUnlinkingClearsAnAutoFilledPar() {
        XCTAssertEqual(CourseRelinkPars.parAfterRelink(current: 3, previousCoursePar: 3, newCoursePar: nil), .some(nil))
    }

    func testNoParOrTheSameParIsLeftAlone() {
        XCTAssertNil(CourseRelinkPars.parAfterRelink(current: nil, previousCoursePar: 3, newCoursePar: 4))
        XCTAssertNil(CourseRelinkPars.parAfterRelink(current: 4, previousCoursePar: 4, newCoursePar: 4))
    }
}

extension HandScoreAndPenaltyTests {
    /// A → B correction where the courses' pars differ: auto-filled pars move,
    /// a hand-typed par stays, and an unlink clears what A filled.
    func testRelinkChangesFollowTheNewCourseAndKeepHandPars() throws {
        func course(_ id: String, pars: [Int]) -> CuratedCourse {
            CuratedCourse(id: id, name: id, aliases: [], location: GeoPoint(lat: 0, lng: 0),
                          holes: pars.enumerated().map { CuratedHole(number: $0.offset + 1, par: $0.element) })
        }
        try CourseDataRepository.replaceAll(with: [course("A", pars: [3, 4, 5]), course("B", pars: [4, 4, 4])],
                                            fetchedAt: Date())
        let round = try TestDatabase.seedRound()
        let one = try HoleRepository.setHandScore(roundID: round.id, holeNumber: 1, strokes: 4, putts: 2)
        let two = try HoleRepository.setHandScore(roundID: round.id, holeNumber: 2, strokes: 4, putts: 2)
        let three = try HoleRepository.setHandScore(roundID: round.id, holeNumber: 3, strokes: 4, putts: 2)
        try HoleRepository.setPar(holeID: one.id, par: 3)    // A's par, auto-filled
        try HoleRepository.setPar(holeID: two.id, par: 4)    // the same on both courses
        try HoleRepository.setPar(holeID: three.id, par: 6)  // typed by hand

        let toB = try CourseRelinkPars.changes(roundID: round.id, from: "A", to: "B")
        XCTAssertEqual(toB.map(\.holeID), [one.id])
        XCTAssertEqual(toB.map(\.par), [4])

        let unlink = try CourseRelinkPars.changes(roundID: round.id, from: "A", to: nil)
        XCTAssertEqual(unlink.map(\.holeID), [one.id, two.id])
        XCTAssertEqual(unlink.map(\.par), [nil, nil])

        XCTAssertTrue(try CourseRelinkPars.changes(roundID: round.id, from: nil, to: "B").isEmpty)
        XCTAssertTrue(try CourseRelinkPars.changes(roundID: round.id, from: "A", to: "A").isEmpty)
    }
}

extension HandScoreAndPenaltyTests {
    /// The open CARD reloads on `ScoringChanges`: a hole finished elsewhere
    /// (the watch's Finish Hole goes through the same repositories) must emit.
    func testScoringChangesEmitsWhenAHoleIsFinishedElsewhere() async throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1, par: 4)
        var iterator = ScoringChanges.values().makeAsyncIterator()
        _ = try await iterator.next() // the value on subscribe
        var finished = hole
        finished.confirmedAt = Date()
        try HoleRepository.update(finished)
        let next = try await iterator.next()
        XCTAssertNotNil(next)
    }

    // MARK: - Not played

    func testRemainingUnscoredFollowsPlayOrder() {
        XCTAssertEqual(HoleScoring.remainingUnscored(liveHole: 15, startingHole: 1, scored: Set(1...14)), [15, 16, 17, 18])
        // Started on 10: after 18 comes 1 … 9.
        XCTAssertEqual(HoleScoring.remainingUnscored(liveHole: 7, startingHole: 10, scored: Set(10...18).union(1...6)),
                       [7, 8, 9])
        XCTAssertEqual(HoleScoring.remainingUnscored(liveHole: 18, startingHole: nil, scored: Set(1...17)), [18])
        // A late start's earlier holes are ADD, not "remaining".
        XCTAssertEqual(HoleScoring.remainingUnscored(liveHole: 16, startingHole: 4, scored: Set(4...15)), [16, 17, 18])
    }

    func testEndRoundMarksTheRemainingHolesNotPlayed() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(mode: .tracking)
        let round = try XCTUnwrap(controller.currentRound)
        try controller.setHandScoreOnCurrentHole(strokes: 5, putts: 2)
        try controller.confirmHoleAndAdvance(par: 4)
        try controller.endRound(markingNotPlayed: Array(2...18))

        let holes = try HoleRepository.holesForRound(round.id)
        XCTAssertEqual(holes.filter(\.isNotPlayed).map(\.holeNumber), Array(2...18))
        let first = try XCTUnwrap(holes.first { $0.holeNumber == 1 })
        XCTAssertFalse(first.isNotPlayed)
        XCTAssertNil(HoleScoring.score(hole: holes[1], shots: [], penaltyStrokes: 0))
        XCTAssertFalse(HoleScoring.needsEntry(holeNumber: 2, startingHole: 5, hole: holes[1], hasTrackedData: false),
                       "NP is an answer, not ADD")

        // Resume lands on the last played hole, and playing an NP hole clears it.
        try controller.resumeRound(XCTUnwrap(try RoundRepository.round(id: round.id)))
        XCTAssertEqual(controller.currentHole?.holeNumber, 1)
        controller.goToHole(2)
        XCTAssertFalse(try XCTUnwrap(try HoleRepository.hole(forRound: round.id, number: 2)).isNotPlayed)
    }

    func testMarkingNotPlayedNeverTouchesAScoredHoleAndUndoes() throws {
        let round = try TestDatabase.seedRound()
        try HoleRepository.setHandScore(roundID: round.id, holeNumber: 3, strokes: 4, putts: 2)
        try HoleRepository.setNotPlayed(true, roundID: round.id, holeNumbers: [3, 4])
        XCTAssertFalse(try XCTUnwrap(try HoleRepository.hole(forRound: round.id, number: 3)).isNotPlayed)
        XCTAssertTrue(try XCTUnwrap(try HoleRepository.hole(forRound: round.id, number: 4)).isNotPlayed)
        try HoleRepository.setNotPlayed(false, roundID: round.id, holeNumbers: [4])
        let four = try XCTUnwrap(try HoleRepository.hole(forRound: round.id, number: 4))
        XCTAssertFalse(four.isNotPlayed)
        XCTAssertNil(four.scoreSource)
        // Entering a score on an NP hole makes it a hand score.
        try HoleRepository.setNotPlayed(true, roundID: round.id, holeNumbers: [5])
        try HoleRepository.setHandScore(roundID: round.id, holeNumber: 5, strokes: 6, putts: 2)
        XCTAssertEqual(try HoleRepository.hole(forRound: round.id, number: 5)?.scoreSource, .hand)
    }

    func testNotPlayedHolesStayOutOfTheCardTotals() {
        let roundID = UUID()
        let played = Hole(id: UUID(), roundID: roundID, holeNumber: 1, par: 4, confirmedAt: Date(),
                          scoreSource: .hand, handStrokes: 5, handPutts: 2)
        let np = Hole(id: UUID(), roundID: roundID, holeNumber: 2, par: 5, confirmedAt: nil, scoreSource: .notPlayed)
        let card = ScorecardModel.build(holes: [.init(hole: played, shots: [], penaltyStrokes: 0),
                                                .init(hole: np, shots: [], penaltyStrokes: 0)], course: nil)
        XCTAssertTrue(card.columns[1].isNotPlayed)
        XCTAssertNil(card.columns[1].score)
        XCTAssertEqual(card.total.score, 5)
        XCTAssertEqual(card.notPlayedHoles, [2])
    }

    func testEndRoundSummary() {
        let summary = EndRoundSummary(courseName: "Native Oaks", scored: [1: 5, 2: 4], pars: [1: 4, 2: 4],
                                      remaining: [3, 4, 5])
        XCTAssertEqual(summary.headline, "NATIVE OAKS · 2 HOLES SCORED · 9 (+1)")
        XCTAssertEqual(summary.markTitle, "Mark holes 3–5 not played")
        XCTAssertEqual(summary.footer(marking: true), "15 OF 18 PLAYED · 9 (+1) · NOT COMPLETE")
        XCTAssertEqual(summary.footer(marking: false), "2 OF 18 SCORED · 3 TO ADD · NOT COMPLETE")
        XCTAssertEqual(EndRoundSummary(courseName: nil, scored: [:], pars: [:], remaining: [18]).markTitle,
                       "Mark hole 18 not played")
    }
}
