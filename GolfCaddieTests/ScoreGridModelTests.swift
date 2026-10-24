import XCTest
@testable import GolfCaddie

/// Casual Finish: the 1–10+ score grid and its putts row → (strokes, putts),
/// plus the casual traits and per-layout decisions.
@MainActor
final class ScoreGridModelTests: XCTestCase {
    // MARK: Picking

    func testStartsWithNothingPicked() {
        let draft = ScoreGridDraft.empty
        XCTAssertNil(draft.strokes)
        XCTAssertNil(draft.putts)
        XCTAssertFalse(draft.canSave)
        XCTAssertThrowsError(try draft.result()) { error in
            XCTAssertEqual(error as? ScoreGridError, .noScore)
        }
    }

    func testPickingAScoreDefaultsPuttsToTwo() {
        let draft = ScoreGridDraft.empty.picking(strokes: 5)
        XCTAssertEqual(draft.strokes, 5)
        XCTAssertEqual(draft.putts, 2)
        XCTAssertEqual(try draft.result(), ScoreGridResult(strokes: 5, putts: 2))
    }

    func testPickingAOneDefaultsToOnePutt() {
        let draft = ScoreGridDraft.empty.picking(strokes: 1)
        XCTAssertEqual(draft.putts, 1)
    }

    func testPuttsPickedFirstAreKept() {
        let draft = ScoreGridDraft.empty.picking(putts: 3).picking(strokes: 6)
        XCTAssertEqual(try draft.result(), ScoreGridResult(strokes: 6, putts: 3))
    }

    func testRepickingTheScoreKeepsThePutts() {
        let draft = ScoreGridDraft.empty.picking(strokes: 5).picking(putts: 1).picking(strokes: 4)
        XCTAssertEqual(draft.putts, 1)
    }

    // MARK: Putts ≤ strokes

    func testPuttsNeverExceedStrokes() {
        let draft = ScoreGridDraft.empty.picking(strokes: 5).picking(putts: 4).picking(strokes: 2)
        XCTAssertEqual(try draft.result(), ScoreGridResult(strokes: 2, putts: 2))
    }

    func testPuttsAboveStrokesAreUnavailable() {
        let draft = ScoreGridDraft.empty.picking(strokes: 2)
        XCTAssertTrue(draft.isPuttsAvailable(0))
        XCTAssertTrue(draft.isPuttsAvailable(2))
        XCTAssertFalse(draft.isPuttsAvailable(3))
        XCTAssertFalse(draft.isPuttsAvailable(4))
        XCTAssertTrue(ScoreGridDraft.empty.isPuttsAvailable(4))
    }

    func testPickingUnavailablePuttsIsClamped() {
        let draft = ScoreGridDraft.empty.picking(strokes: 2).picking(putts: 4)
        XCTAssertEqual(draft.putts, 2)
    }

    func testInitClampsOutOfRangeValues() {
        let draft = ScoreGridDraft(strokes: 0, putts: -3)
        XCTAssertEqual(draft.strokes, HoleScoring.strokeRange.lowerBound)
        XCTAssertEqual(draft.putts, 0)
        XCTAssertEqual(ScoreGridDraft(strokes: 99, putts: nil).strokes, HoleScoring.strokeRange.upperBound)
    }

    // MARK: 10+ and 4+

    func testTenPlusRecordsTen() {
        let draft = ScoreGridDraft.empty.picking(strokes: 10)
        XCTAssertEqual(draft.strokes, 10)
        XCTAssertTrue(draft.isScoreSelected(10))
    }

    func testTenPlusKeepsAHigherStoredScore() {
        let draft = ScoreGridDraft(strokes: 12, putts: 3)
        XCTAssertTrue(draft.isScoreSelected(10))
        XCTAssertFalse(draft.isScoreSelected(9))
        XCTAssertEqual(draft.picking(strokes: 10).strokes, 12)
        XCTAssertEqual(draft.picking(strokes: 7).strokes, 7)
    }

    func testFourPlusKeepsAHigherStoredPuttCount() {
        let draft = ScoreGridDraft(strokes: 12, putts: 6)
        XCTAssertTrue(draft.isPuttsSelected(4))
        XCTAssertEqual(draft.picking(putts: 4).putts, 6)
        XCTAssertEqual(draft.picking(putts: 2).putts, 2)
    }

    func testInitialFromAHandScoredHole() {
        var hole = Hole(id: UUID(), roundID: UUID(), holeNumber: 3, par: 4, confirmedAt: nil)
        XCTAssertEqual(ScoreGridDraft.initial(hole: hole), .empty)
        hole.scoreSource = .hand
        hole.handStrokes = 6
        hole.handPutts = 3
        XCTAssertEqual(ScoreGridDraft.initial(hole: hole), ScoreGridDraft(strokes: 6, putts: 3))
        XCTAssertEqual(ScoreGridDraft.initial(hole: nil), .empty)
    }

    func testInitialFromAHandScoreWithoutPuttsDefaultsThem() {
        var hole = Hole(id: UUID(), roundID: UUID(), holeNumber: 3, par: 4, confirmedAt: nil)
        hole.scoreSource = .hand
        hole.handStrokes = 5
        XCTAssertEqual(ScoreGridDraft.initial(hole: hole), ScoreGridDraft(strokes: 5, putts: 2))
    }

    // MARK: Labels

    func testCells() {
        XCTAssertEqual(ScoreGridModel.scoreCells, Array(1...10))
        XCTAssertEqual(ScoreGridModel.puttCells, [0, 1, 2, 3, 4])
        XCTAssertEqual(ScoreGridModel.scoreLabel(10), "10+")
        XCTAssertEqual(ScoreGridModel.scoreLabel(7), "7")
        XCTAssertEqual(ScoreGridModel.puttsLabel(4), "4+")
    }

    func testNamesAgainstPar() {
        XCTAssertEqual(ScoreGridModel.name(strokes: 2, par: 4), "EAGLE")
        XCTAssertEqual(ScoreGridModel.name(strokes: 3, par: 4), "BIRDIE")
        XCTAssertEqual(ScoreGridModel.name(strokes: 4, par: 4), "PAR")
        XCTAssertEqual(ScoreGridModel.name(strokes: 5, par: 4), "BOGEY")
        XCTAssertEqual(ScoreGridModel.name(strokes: 6, par: 4), "DOUBLE")
        XCTAssertEqual(ScoreGridModel.name(strokes: 7, par: 4), "TRIPLE")
        XCTAssertEqual(ScoreGridModel.name(strokes: 8, par: 4), "")
        XCTAssertEqual(ScoreGridModel.name(strokes: 1, par: 3), "ACE")
        XCTAssertEqual(ScoreGridModel.name(strokes: 5, par: nil), "")
    }

    func testCellAccessibilityLabels() {
        XCTAssertEqual(ScoreGridModel.scoreAccessibilityLabel(5, par: 4), "5, bogey")
        XCTAssertEqual(ScoreGridModel.scoreAccessibilityLabel(10, par: 4), "10 or more")
        XCTAssertEqual(ScoreGridModel.scoreAccessibilityLabel(6, par: nil), "6")
        XCTAssertEqual(ScoreGridModel.puttsAccessibilityLabel(1), "1 putt")
        XCTAssertEqual(ScoreGridModel.puttsAccessibilityLabel(4), "4 or more putts")
    }

    func testTitles() {
        XCTAssertEqual(ScoreGridModel.title(holeNumber: 8), "Score on hole 8?")
        XCTAssertEqual(ScoreGridModel.saveTitle(strokes: nil, holeNumber: 8, advances: true, compact: false),
                       "Pick a score")
        XCTAssertEqual(ScoreGridModel.saveTitle(strokes: 5, holeNumber: 8, advances: true, compact: false),
                       "Save 5 · hole 9 ›")
        XCTAssertEqual(ScoreGridModel.saveTitle(strokes: 5, holeNumber: 18, advances: true, compact: false),
                       "Save 5 · hole 1 ›")
        XCTAssertEqual(ScoreGridModel.saveTitle(strokes: 5, holeNumber: 8, advances: true, compact: true),
                       "Save 5 · next ›")
        XCTAssertEqual(ScoreGridModel.saveTitle(strokes: 6, holeNumber: 3, advances: false, compact: true),
                       "Save 6 · hole 3")
    }

    // MARK: Casual traits and layouts

    func testCasualTraits() {
        XCTAssertFalse(RoundMapMode.casual.tracksShots)
        XCTAssertTrue(RoundMapMode.casual.showsYardage)
        XCTAssertFalse(RoundMapMode.casual.finishAsksPutts)
        XCTAssertEqual(RoundMapMode.casual.finishQuestion, .score)
        XCTAssertTrue(RoundMapMode.casual.entryUsesScoreGrid)
        XCTAssertTrue(RoundMapMode.casual.showsRoundSoFar)
        XCTAssertTrue(RoundMapMode.casual.allowsAutoHide)
        XCTAssertFalse(RoundMapMode.casual.allowsHoldToAdd)
        XCTAssertEqual(RoundMapMode.casual.captionTag, "CASUAL")
    }

    func testTrackingKeepsItsTraits() {
        XCTAssertEqual(RoundMapMode.tracking.finishQuestion, .putts)
        XCTAssertFalse(RoundMapMode.tracking.entryUsesScoreGrid)
        XCTAssertFalse(RoundMapMode.tracking.showsRoundSoFar)
        XCTAssertNil(RoundMapMode.tracking.captionTag)
    }

    func testRoundScoresVariantPerLayout() {
        XCTAssertEqual(RoundMapLayout.openWide.roundScoresVariant, .list)
        XCTAssertEqual(RoundMapLayout.openPortrait.roundScoresVariant, .list)
        XCTAssertEqual(RoundMapLayout.book.roundScoresVariant, .list)
        XCTAssertEqual(RoundMapLayout.phoneLandscape.roundScoresVariant, .list)
        XCTAssertEqual(RoundMapLayout.folded.roundScoresVariant, .squares)
        XCTAssertEqual(RoundMapLayout.phonePortrait.roundScoresVariant, .chips)
    }

    func testScoreGridOpensInASheetOnlyOnFoldedAndPhonePortrait() {
        let sheets = RoundMapLayout.allCases.filter(\.asksInBottomSheet)
        XCTAssertEqual(Set(sheets), [.folded, .phonePortrait])
    }

    func testCasualCaption() {
        XCTAssertEqual(RoundMapFormat.tagged("PAR 4 · 398 YD", tag: "CASUAL"), "PAR 4 · 398 YD · CASUAL")
        XCTAssertEqual(RoundMapFormat.tagged("PAR 4", tag: nil), "PAR 4")
    }

    // MARK: Auto-hide in casual

    func testCasualLiveHoleLetsControlsAutoHide() {
        // The casual live hole is no longer an always-open entry, so nothing
        // pauses auto-hide until Finish opens the grid.
        let state = HolePanelState.resolve(mode: .casual, isLive: true, isTracked: false,
                                           needsEntry: false, isHandScored: false)
        XCTAssertEqual(state, .live)
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: state == .entry,
                                                   shotSelected: false, dragging: false), [])
    }

    func testOpenScoreGridPausesAutoHide() {
        let question: RoundMapQuestion? = .score
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: question != nil, entryOpen: false,
                                                   shotSelected: false, dragging: false), [.question])
    }

    func testFoldedCasualAutoHidesButPausesWhileTheGridIsOpen() {
        let scheduler = TestAutoHideScheduler()
        let folded = DisplayContext(layoutClass: .compact, posture: .closed,
                                    windowSize: CGSize(width: 466, height: 678))
        let controller = AutoHideController(display: folded, scheduler: scheduler)
        XCTAssertEqual(controller.policy, .automatic)
        AutoHideWiring.apply([.question], to: controller)
        XCTAssertTrue(controller.isPaused)
        scheduler.advance(by: 30)
        XCTAssertTrue(controller.controlsVisible, "the open score grid keeps the controls up")
        AutoHideWiring.apply([], to: controller)
        XCTAssertFalse(controller.isPaused)
        scheduler.advance(by: AutoHideController.defaultDelay)
        XCTAssertFalse(controller.controlsVisible, "hides again once the grid is closed")
    }
}
