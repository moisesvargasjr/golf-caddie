import Foundation
import Observation

/// How the in-round controls hide on a display (Duo v2 rule 5).
enum AutoHidePolicy: Equatable, Sendable {
    /// Hide after `AutoHideController.defaultDelay` with no touch; tapping the
    /// map brings them back. Folded Duo and iPhone portrait.
    case automatic
    /// Never hide on a timer; the layout offers a manual hide button. Open Duo
    /// (wide or portrait), book pose and iPhone landscape.
    case manual

    static func resolve(_ display: DisplayContext) -> AutoHidePolicy {
        // Unfolded Duo, flat or book: plenty of room, manual only.
        if display.layoutClass == .expanded { return .manual }
        if display.posture == .halfOpen { return .manual }
        // Folded Duo (cover screen), either orientation.
        if display.posture == .closed { return .automatic }
        // Regular iPhone (or the cover before the hinge reports).
        return display.isLandscape ? .manual : .automatic
    }
}

/// Something open on screen that must keep the controls from auto-hiding.
enum AutoHidePauseReason: Hashable, Sendable, CaseIterable {
    /// A question is open (putts, penalty, score grid).
    case question
    /// A pin / shot is selected.
    case selection
    /// A pin is being dragged.
    case drag
    /// The screen's mode has auto-hide off (a finished round's review).
    case modeOff
}

/// Cancels one scheduled auto-hide.
@MainActor
final class AutoHideTimerHandle {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        let cancel = onCancel
        onCancel = nil
        cancel?()
    }
}

/// Runs `action` after a delay unless the returned handle is cancelled.
/// Injected so tests drive the clock (see `TestAutoHideScheduler`).
@MainActor
protocol AutoHideScheduler: AnyObject {
    func schedule(after seconds: TimeInterval,
                  _ action: @escaping @MainActor () -> Void) -> AutoHideTimerHandle
}

/// Production scheduler: one main-actor `Task` per timer.
@MainActor
final class TaskAutoHideScheduler: AutoHideScheduler {
    nonisolated init() {}

    func schedule(after seconds: TimeInterval,
                  _ action: @escaping @MainActor () -> Void) -> AutoHideTimerHandle {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
        return AutoHideTimerHandle { task.cancel() }
    }
}

/// Shows and hides the in-round controls per `AutoHidePolicy`.
///
/// - Starts visible. Under `.automatic`, hides `delay` seconds after the last
///   touch (`noteInteraction`) or map tap (`tapMap`), both of which show the
///   controls and restart the countdown.
/// - While any pause reason is active the countdown is stopped and nothing
///   auto-hides; clearing the last reason restarts a full countdown. Pausing
///   does not reveal hidden controls (a drag must not reflow the map framing).
/// - `setManuallyHidden` works under either policy (`manualHideAvailable`
///   says whether the layout should offer the button).
/// - A display change that flips the policy (fold/unfold/book/rotate) shows
///   the controls; under `.automatic` it starts a fresh countdown, under
///   `.manual` it cancels any countdown. Same-policy changes do nothing.
@Observable
@MainActor
final class AutoHideController {
    nonisolated static let defaultDelay: TimeInterval = 5

    private(set) var policy: AutoHidePolicy
    private(set) var isHidden = false
    private(set) var pauseReasons: Set<AutoHidePauseReason> = []

    private let delay: TimeInterval
    private let scheduler: any AutoHideScheduler
    @ObservationIgnored private var timer: AutoHideTimerHandle?

    init(display: DisplayContext,
         delay: TimeInterval = AutoHideController.defaultDelay,
         scheduler: any AutoHideScheduler = TaskAutoHideScheduler()) {
        self.policy = AutoHidePolicy.resolve(display)
        self.delay = delay
        self.scheduler = scheduler
        restartCountdown()
    }

    var controlsVisible: Bool { !isHidden }
    var manualHideAvailable: Bool { policy == .manual }
    var isPaused: Bool { !pauseReasons.isEmpty }

    /// Re-resolve the policy for a new display (call on every context change).
    func update(display: DisplayContext) {
        let next = AutoHidePolicy.resolve(display)
        guard next != policy else { return }
        policy = next
        isHidden = false
        restartCountdown()
    }

    /// Any touch on the controls: show them and restart the countdown.
    func noteInteraction() {
        isHidden = false
        restartCountdown()
    }

    /// A tap on the map background brings the controls back.
    func tapMap() {
        noteInteraction()
    }

    func pause(_ reason: AutoHidePauseReason) {
        pauseReasons = pauseReasons.union([reason])
        cancelCountdown()
    }

    func resume(_ reason: AutoHidePauseReason) {
        guard pauseReasons.contains(reason) else { return }
        pauseReasons = pauseReasons.subtracting([reason])
        restartCountdown()
    }

    func setManuallyHidden(_ hidden: Bool) {
        isHidden = hidden
        if hidden {
            cancelCountdown()
        } else {
            restartCountdown()
        }
    }

    // MARK: Countdown

    private func restartCountdown() {
        cancelCountdown()
        guard policy == .automatic, pauseReasons.isEmpty, !isHidden else { return }
        timer = scheduler.schedule(after: delay) { [weak self] in
            self?.countdownFinished()
        }
    }

    private func cancelCountdown() {
        timer?.cancel()
        timer = nil
    }

    private func countdownFinished() {
        timer = nil
        guard policy == .automatic, pauseReasons.isEmpty else { return }
        isHidden = true
    }
}
