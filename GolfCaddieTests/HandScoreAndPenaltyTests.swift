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
        XCTAssertEqual(RoundController.parAfterRelink(current: 3, previousCoursePar: 3, newCoursePar: 4), .some(4))
    }

    func testAHandTypedParStays() {
        XCTAssertNil(RoundController.parAfterRelink(current: 5, previousCoursePar: 3, newCoursePar: 4))
    }

    func testUnlinkingClearsAnAutoFilledPar() {
        XCTAssertEqual(RoundController.parAfterRelink(current: 3, previousCoursePar: 3, newCoursePar: nil), .some(nil))
    }

    func testNoParOrTheSameParIsLeftAlone() {
        XCTAssertNil(RoundController.parAfterRelink(current: nil, previousCoursePar: 3, newCoursePar: 4))
        XCTAssertNil(RoundController.parAfterRelink(current: 4, previousCoursePar: 4, newCoursePar: 4))
    }
}
