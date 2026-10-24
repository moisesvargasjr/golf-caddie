import SwiftUI
import XCTest
@testable import GolfCaddie

/// Deterministic scheduler: nothing fires until the test advances the clock.
@MainActor
final class TestAutoHideScheduler: AutoHideScheduler {
    private struct Pending {
        let id: Int
        let due: TimeInterval
        let action: @MainActor () -> Void
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Pending] = []
    private var nextID = 0

    var pendingCount: Int { pending.count }

    func schedule(after seconds: TimeInterval,
                  _ action: @escaping @MainActor () -> Void) -> AutoHideTimerHandle {
        let id = nextID
        nextID += 1
        pending = pending + [Pending(id: id, due: now + seconds, action: action)]
        return AutoHideTimerHandle { [weak self] in
            guard let self else { return }
            self.pending = self.pending.filter { $0.id != id }
        }
    }

    /// Moves the clock forward, firing every timer that falls due, in order.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = pending.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
            pending = pending.filter { $0.id != next.id }
            now = next.due
            next.action()
        }
        now = target
    }
}

@MainActor
final class AutoHideControllerTests: XCTestCase {
    private func display(_ w: CGFloat, _ h: CGFloat, _ cls: LayoutClass,
                         _ posture: HingePosture) -> DisplayContext {
        DisplayContext(layoutClass: cls, posture: posture, windowSize: CGSize(width: w, height: h))
    }

    private var folded: DisplayContext { display(466, 678, .compact, .closed) }
    private var foldedLandscape: DisplayContext { display(678, 466, .compact, .closed) }
    private var openWide: DisplayContext { display(951, 669, .expanded, .open) }
    private var openPortrait: DisplayContext { display(669, 951, .expanded, .open) }
    private var book: DisplayContext { display(951, 669, .expanded, .halfOpen) }
    private var iPhonePortrait: DisplayContext { display(402, 874, .compact, .unknown) }
    private var iPhoneLandscape: DisplayContext { display(874, 402, .compact, .unknown) }

    private func make(_ display: DisplayContext) -> (AutoHideController, TestAutoHideScheduler) {
        let scheduler = TestAutoHideScheduler()
        return (AutoHideController(display: display, scheduler: scheduler), scheduler)
    }

    // MARK: Policy table

    func testPolicyTable() {
        XCTAssertEqual(AutoHidePolicy.resolve(folded), .automatic)
        XCTAssertEqual(AutoHidePolicy.resolve(foldedLandscape), .automatic)
        XCTAssertEqual(AutoHidePolicy.resolve(iPhonePortrait), .automatic)
        XCTAssertEqual(AutoHidePolicy.resolve(openWide), .manual)
        XCTAssertEqual(AutoHidePolicy.resolve(openPortrait), .manual)
        XCTAssertEqual(AutoHidePolicy.resolve(book), .manual)
        XCTAssertEqual(AutoHidePolicy.resolve(iPhoneLandscape), .manual)
        // Expanded with no hinge reading (simulator) is still the open Duo.
        XCTAssertEqual(AutoHidePolicy.resolve(display(951, 669, .expanded, .unknown)), .manual)
        // Duo cover before the hinge reports (posture unknown) is portrait.
        XCTAssertEqual(AutoHidePolicy.resolve(display(466, 678, .compact, .unknown)), .automatic)
    }

    func testManualHideAvailability() {
        XCTAssertFalse(make(folded).0.manualHideAvailable)
        XCTAssertFalse(make(iPhonePortrait).0.manualHideAvailable)
        XCTAssertTrue(make(openWide).0.manualHideAvailable)
        XCTAssertTrue(make(openPortrait).0.manualHideAvailable)
        XCTAssertTrue(make(book).0.manualHideAvailable)
        XCTAssertTrue(make(iPhoneLandscape).0.manualHideAvailable)
    }

    // MARK: Timer

    func testStartsVisibleAndHidesAfterFiveSeconds() {
        let (controller, clock) = make(folded)
        XCTAssertFalse(controller.isHidden)
        XCTAssertTrue(controller.controlsVisible)
        clock.advance(by: 4.9)
        XCTAssertFalse(controller.isHidden)
        clock.advance(by: 0.1)
        XCTAssertTrue(controller.isHidden)
        XCTAssertFalse(controller.controlsVisible)
    }

    func testDefaultDelayIsFiveSeconds() {
        XCTAssertEqual(AutoHideController.defaultDelay, 5)
    }

    func testInteractionResetsTheTimer() {
        let (controller, clock) = make(iPhonePortrait)
        clock.advance(by: 3)
        controller.noteInteraction()
        clock.advance(by: 4.9)
        XCTAssertFalse(controller.isHidden)
        clock.advance(by: 0.1)
        XCTAssertTrue(controller.isHidden)
    }

    func testTapMapShowsAndRestarts() {
        let (controller, clock) = make(folded)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
        controller.tapMap()
        XCTAssertFalse(controller.isHidden)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
    }

    func testInteractionWhileHiddenShows() {
        let (controller, clock) = make(folded)
        clock.advance(by: 5)
        controller.noteInteraction()
        XCTAssertFalse(controller.isHidden)
    }

    func testOnlyOneTimerIsEverPending() {
        let (controller, clock) = make(folded)
        controller.noteInteraction()
        controller.noteInteraction()
        controller.tapMap()
        XCTAssertEqual(clock.pendingCount, 1)
    }

    // MARK: Pause reasons

    func testPausedNeverAutoHides() {
        let (controller, clock) = make(folded)
        controller.pause(.question)
        XCTAssertTrue(controller.isPaused)
        clock.advance(by: 60)
        XCTAssertFalse(controller.isHidden)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testPauseMidCountdownCancelsIt() {
        let (controller, clock) = make(folded)
        clock.advance(by: 4)
        controller.pause(.drag)
        clock.advance(by: 10)
        XCTAssertFalse(controller.isHidden)
    }

    func testResumeRestartsAFullCountdown() {
        let (controller, clock) = make(folded)
        controller.pause(.selection)
        clock.advance(by: 30)
        controller.resume(.selection)
        XCTAssertFalse(controller.isPaused)
        clock.advance(by: 4.9)
        XCTAssertFalse(controller.isHidden)
        clock.advance(by: 0.1)
        XCTAssertTrue(controller.isHidden)
    }

    func testEveryPauseReasonMustClear() {
        let (controller, clock) = make(folded)
        controller.pause(.question)
        controller.pause(.drag)
        XCTAssertEqual(controller.pauseReasons, [.question, .drag])
        controller.resume(.question)
        XCTAssertTrue(controller.isPaused)
        clock.advance(by: 30)
        XCTAssertFalse(controller.isHidden)
        controller.resume(.drag)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
    }

    func testInteractionWhilePausedDoesNotStartTheTimer() {
        let (controller, clock) = make(folded)
        controller.pause(.question)
        controller.noteInteraction()
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testResumingAReasonThatWasNotSetIsANoOp() {
        let (controller, clock) = make(folded)
        clock.advance(by: 3)
        controller.resume(.drag)
        clock.advance(by: 2)
        XCTAssertTrue(controller.isHidden, "an unrelated resume must not reset the countdown")
    }

    func testPauseDoesNotRevealHiddenControls() {
        // A drag on the map while hidden must not reflow the map framing.
        let (controller, clock) = make(folded)
        clock.advance(by: 5)
        controller.pause(.drag)
        XCTAssertTrue(controller.isHidden)
    }

    // MARK: Manual policy

    func testManualPolicyNeverAutoHides() {
        let (controller, clock) = make(openWide)
        clock.advance(by: 60)
        XCTAssertFalse(controller.isHidden)
        XCTAssertEqual(clock.pendingCount, 0)
        controller.noteInteraction()
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testManualHideAndShow() {
        let (controller, clock) = make(book)
        controller.setManuallyHidden(true)
        XCTAssertTrue(controller.isHidden)
        clock.advance(by: 60)
        XCTAssertTrue(controller.isHidden)
        controller.setManuallyHidden(false)
        XCTAssertFalse(controller.isHidden)
    }

    func testManualHideOnAutomaticPolicyCancelsTimerAndShowRestartsIt() {
        let (controller, clock) = make(folded)
        controller.setManuallyHidden(true)
        XCTAssertEqual(clock.pendingCount, 0)
        controller.setManuallyHidden(false)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
    }

    // MARK: Posture changes

    func testUnfoldWhileHiddenShowsAndStopsTheTimer() {
        let (controller, clock) = make(folded)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
        controller.update(display: openWide)
        XCTAssertEqual(controller.policy, .manual)
        XCTAssertFalse(controller.isHidden)
        clock.advance(by: 60)
        XCTAssertFalse(controller.isHidden)
    }

    func testUnfoldMidCountdownCancelsIt() {
        let (controller, clock) = make(folded)
        clock.advance(by: 3)
        controller.update(display: book)
        XCTAssertEqual(clock.pendingCount, 0)
        clock.advance(by: 10)
        XCTAssertFalse(controller.isHidden)
    }

    func testFoldFromManuallyHiddenShowsAndStartsCountdown() {
        let (controller, clock) = make(openWide)
        controller.setManuallyHidden(true)
        controller.update(display: folded)
        XCTAssertEqual(controller.policy, .automatic)
        XCTAssertFalse(controller.isHidden)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
    }

    func testSamePolicyUpdateKeepsTheCountdown() {
        let (controller, clock) = make(folded)
        clock.advance(by: 3)
        // Same policy (e.g. the cover screen rotated): no reset.
        controller.update(display: foldedLandscape)
        clock.advance(by: 2)
        XCTAssertTrue(controller.isHidden)
    }

    func testIPhoneRotationSwitchesPolicy() {
        let (controller, clock) = make(iPhonePortrait)
        controller.update(display: iPhoneLandscape)
        XCTAssertTrue(controller.manualHideAvailable)
        clock.advance(by: 10)
        XCTAssertFalse(controller.isHidden)
        controller.update(display: iPhonePortrait)
        XCTAssertFalse(controller.manualHideAvailable)
        clock.advance(by: 5)
        XCTAssertTrue(controller.isHidden)
    }

    func testPausedThroughAPostureChangeStaysPaused() {
        let (controller, clock) = make(folded)
        controller.pause(.question)
        controller.update(display: openWide)
        controller.update(display: folded)
        clock.advance(by: 30)
        XCTAssertFalse(controller.isHidden)
        XCTAssertEqual(controller.pauseReasons, [.question])
    }

    // MARK: Policy override (DEBUG -DebugAutoHide off)

    func testOverrideParsing() {
        XCTAssertEqual(AutoHidePolicy.forced(named: "off"), .manual)
        XCTAssertEqual(AutoHidePolicy.forced(named: "OFF"), .manual)
        XCTAssertEqual(AutoHidePolicy.forced(named: "manual"), .manual)
        XCTAssertEqual(AutoHidePolicy.forced(named: "on"), .automatic)
        XCTAssertNil(AutoHidePolicy.forced(named: nil))
        XCTAssertNil(AutoHidePolicy.forced(named: "bogus"))
    }

    func testOverrideForcesManualOnFolded() {
        let clock = TestAutoHideScheduler()
        let controller = AutoHideController(display: folded, scheduler: clock, policyOverride: .manual)
        XCTAssertEqual(controller.policy, .manual)
        clock.advance(by: 60)
        XCTAssertFalse(controller.isHidden)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testOverrideSurvivesDisplayChanges() {
        let clock = TestAutoHideScheduler()
        let controller = AutoHideController(display: openWide, scheduler: clock, policyOverride: .manual)
        controller.update(display: folded)
        controller.update(display: iPhonePortrait)
        XCTAssertEqual(controller.policy, .manual)
        clock.advance(by: 60)
        XCTAssertFalse(controller.isHidden)
    }

    // MARK: Production scheduler

    func testTaskSchedulerFiresAndCancels() async throws {
        let scheduler = TaskAutoHideScheduler()
        var fired = false
        var cancelledFired = false
        _ = scheduler.schedule(after: 0.01) { fired = true }
        let cancelled = scheduler.schedule(after: 0.01) { cancelledFired = true }
        cancelled.cancel()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(fired)
        XCTAssertFalse(cancelledFired)
    }
}
