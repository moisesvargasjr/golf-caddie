import XCTest
@testable import GolfCaddie

/// Pure decisions behind the tracking screen: auto-hide wiring, what the
/// panel shows (late-start entry), hole navigation, the one-time tip, the
/// penalty and putts questions and their text.
@MainActor
final class RoundMapRulesTests: XCTestCase {
    // MARK: Auto-hide wiring

    func testNothingOpenPausesNothing() {
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: false,
                                                   shotSelected: false, dragging: false), [])
    }

    func testEachOpenThingPausesItsReason() {
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: true, entryOpen: false,
                                                   shotSelected: false, dragging: false), [.question])
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: true,
                                                   shotSelected: false, dragging: false), [.question])
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: false,
                                                   shotSelected: true, dragging: false), [.selection])
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: false,
                                                   shotSelected: false, dragging: true), [.drag])
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: true, entryOpen: true,
                                                   shotSelected: true, dragging: true),
                       [.question, .selection, .drag])
    }

    func testChangesPauseNewAndResumeGoneReasons() {
        let delta = AutoHideWiring.changes(from: [.question, .drag], to: [.selection, .drag])
        XCTAssertEqual(delta.pause, [.selection])
        XCTAssertEqual(delta.resume, [.question])
    }

    func testApplyDrivesTheController() {
        let scheduler = TestAutoHideScheduler()
        let display = DisplayContext(layoutClass: .compact, posture: .closed,
                                     windowSize: CGSize(width: 466, height: 678))
        let controller = AutoHideController(display: display, scheduler: scheduler)
        AutoHideWiring.apply([.selection], to: controller)
        XCTAssertEqual(controller.pauseReasons, [.selection])
        scheduler.advance(by: 30)
        XCTAssertTrue(controller.controlsVisible, "a selected pin keeps the controls up")
        AutoHideWiring.apply([], to: controller)
        XCTAssertEqual(controller.pauseReasons, [])
        scheduler.advance(by: AutoHideController.defaultDelay)
        XCTAssertFalse(controller.controlsVisible, "hides again once nothing is open")
    }

    // MARK: Panel state / late-start entry visibility

    func testLiveTrackingHole() {
        XCTAssertEqual(HolePanelState.resolve(mode: .tracking, isLive: true, isTracked: true,
                                              needsEntry: false, isHandScored: false), .live)
    }

    func testCasualLiveHoleIsLive() {
        // PR 5: the casual live hole shows the round so far + Finish (the
        // score grid opens on Finish), not an always-open entry.
        XCTAssertEqual(HolePanelState.resolve(mode: .casual, isLive: true, isTracked: true,
                                              needsEntry: false, isHandScored: false), .live)
    }

    func testHoleBeforeLateStartShowsEntry() {
        XCTAssertEqual(HolePanelState.resolve(mode: .tracking, isLive: false, isTracked: false,
                                              needsEntry: true, isHandScored: false), .entry)
    }

    func testHandScoredPastHoleStaysEditableAsEntry() {
        XCTAssertEqual(HolePanelState.resolve(mode: .tracking, isLive: false, isTracked: false,
                                              needsEntry: false, isHandScored: true), .entry)
    }

    func testFinishedTrackedHoleIsPastTracked() {
        XCTAssertEqual(HolePanelState.resolve(mode: .tracking, isLive: false, isTracked: true,
                                              needsEntry: false, isHandScored: false), .pastTracked)
    }

    func testSkippedPastHoleWithNothingLoggedShowsEntry() {
        XCTAssertEqual(HolePanelState.resolve(mode: .tracking, isLive: false, isTracked: false,
                                              needsEntry: false, isHandScored: false), .entry)
    }

    func testNotTrackedText() {
        XCTAssertEqual(RoundMapFormat.notTrackedText(holeNumber: 4, startingHole: 7),
                       "NOT TRACKED · YOU STARTED ON HOLE 7")
        XCTAssertEqual(RoundMapFormat.notTrackedText(holeNumber: 9, startingHole: 7), "NOT TRACKED")
        XCTAssertEqual(RoundMapFormat.notTrackedText(holeNumber: 2, startingHole: nil), "NOT TRACKED")
    }

    // MARK: Navigation

    func testPreviousFromLiveViewsThePastHole() {
        XCTAssertEqual(HoleNavigation.previous(viewing: 8, live: 8), .view(7))
        XCTAssertNil(HoleNavigation.previous(viewing: 1, live: 8))
    }

    func testPreviousLandingOnLiveFollowsLive() {
        XCTAssertEqual(HoleNavigation.previous(viewing: 9, live: 8), .live)
    }

    func testNextWalksBackToLive() {
        XCTAssertEqual(HoleNavigation.next(viewing: 6, live: 8), .view(7))
        XCTAssertEqual(HoleNavigation.next(viewing: 7, live: 8), .live)
    }

    func testNextOnTheLiveHoleSkipsAhead() {
        XCTAssertEqual(HoleNavigation.next(viewing: 8, live: 8), .skipAhead)
    }

    func testNextWrapsForABackNineStart() {
        XCTAssertEqual(HoleNavigation.next(viewing: 18, live: 2), .view(1))
        XCTAssertEqual(HoleNavigation.next(viewing: 18, live: 1), .live)
    }

    func testGridPick() {
        XCTAssertEqual(HoleNavigation.gridPick(8, live: 8, isFinished: true, isBeforeStart: false), .live)
        XCTAssertEqual(HoleNavigation.gridPick(3, live: 8, isFinished: true, isBeforeStart: false), .view(3))
        XCTAssertEqual(HoleNavigation.gridPick(2, live: 8, isFinished: false, isBeforeStart: true), .view(2))
        XCTAssertEqual(HoleNavigation.gridPick(12, live: 8, isFinished: false, isBeforeStart: false), .skipAhead)
    }

    // MARK: One-time tip

    func testTipShowsOnceAndPersists() throws {
        let suite = "RoundMapRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let tip = HoldToAddTip(defaults: defaults)
        XCTAssertFalse(tip.hasBeenSeen)
        XCTAssertEqual(tip.consume(), HoldToAddTip.message)
        XCTAssertTrue(tip.hasBeenSeen)
        XCTAssertNil(tip.consume())
        // A new instance (next launch) reads the stored flag.
        XCTAssertNil(HoldToAddTip(defaults: defaults).consume())
    }

    // MARK: Text

    func testRoundScoreText() {
        XCTAssertNil(RoundMapFormat.roundScoreText(holes: [(par: 4, score: nil)]))
        XCTAssertEqual(RoundMapFormat.roundScoreText(holes: [(par: 4, score: 5), (par: 3, score: 3),
                                                             (par: 5, score: nil)]), "+1 · 2 SCORED")
        XCTAssertEqual(RoundMapFormat.roundScoreText(holes: [(par: 5, score: 4)]), "-1 · 1 SCORED")
        XCTAssertEqual(RoundMapFormat.roundScoreText(holes: [(par: nil, score: 6)]), "E · 1 SCORED")
        XCTAssertEqual(RoundMapFormat.roundToPar(holes: [(par: 4, score: 5)]), "+1")
    }

    func testResultLine() {
        XCTAssertEqual(RoundMapFormat.resultLine(score: 5, par: 4, putts: 2), "5 (+1) · 2 putts")
        XCTAssertEqual(RoundMapFormat.resultLine(score: 3, par: 3, putts: 1), "3 (E) · 1 putt")
        XCTAssertEqual(RoundMapFormat.resultLine(score: 6, par: nil, putts: nil), "6")
        XCTAssertEqual(RoundMapFormat.resultLine(score: nil, par: 4, putts: nil), "No score yet")
    }

    func testHoleCaption() {
        XCTAssertEqual(RoundMapFormat.holeCaption(par: 4, length: 398, unit: "yd", roundToPar: nil),
                       "PAR 4 · 398 YD")
        XCTAssertEqual(RoundMapFormat.holeCaption(par: 4, length: 398, unit: nil, roundToPar: "+1"),
                       "PAR 4 · 398 · +1")
        XCTAssertEqual(RoundMapFormat.holeCaption(par: nil, length: nil, unit: nil, roundToPar: nil), "PAR —")
    }
}
