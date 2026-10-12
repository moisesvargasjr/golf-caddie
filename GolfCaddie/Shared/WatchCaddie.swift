import Combine
import CoreLocation
import Foundation

/// On-wrist yardage: the watch's own fix + the cached catalog → yards to the
/// current hole's green, no phone involved (docs/WATCH_STANDALONE_SPIKE.md).
///
/// Hole + course come from the phone while a phone round is active (the phone
/// stays the round's owner); with no phone round the watch is on its own —
/// nearest cached course, holes stepped by hand.
///
/// Lives in Shared (inputs injected, no watch singletons) so the phone test
/// target can cover it — the watch has no test target. The watch wires
/// `update(phoneState:)` / `update(courses:)` / `ingest(_:)` in
/// LiveSessionController.
@MainActor
final class WatchCaddie: ObservableObject {
    /// Schedules `fire` after `delay` seconds; returns a cancel closure.
    typealias ExpiryScheduler = (_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> () -> Void

    /// Fixes worse than this don't drive the yardage (or the workout route).
    static let maxAccuracyMeters: CLLocationAccuracy = 50

    @Published private(set) var course: CuratedCourse?
    /// Yards to the green computed on the wrist. Actively cleared once the last
    /// good fix is `staleAfter` old — even if no further fix or other update
    /// ever arrives — so the display falls back to the phone's value (or
    /// clears, watch-only) instead of freezing on an old number.
    @Published private(set) var localYards: Int?
    /// The hole when there's no phone round to follow.
    @Published var watchOnlyHole = 1 { didSet { recompute() } }

    private let staleAfter: TimeInterval
    private let now: () -> Date
    private let scheduleExpiry: ExpiryScheduler

    private var courses: [CuratedCourse] = []
    /// Published: `holeNumber`/`hole` derive from it, so a phone hole change
    /// must redraw the yardage screen even when the yardage itself is unchanged
    /// (found on the simulator: the header kept showing the previous hole).
    @Published private var phoneState = PhoneStateUpdate.inactive
    private var lastFix: CLLocation?
    private var lastFixAt: Date?
    private var cancelExpiry: (() -> Void)?

    init(
        staleAfter: TimeInterval = 20,
        now: @escaping () -> Date = Date.init,
        scheduleExpiry: @escaping ExpiryScheduler = WatchCaddie.taskScheduler
    ) {
        self.staleAfter = staleAfter
        self.now = now
        self.scheduleExpiry = scheduleExpiry
    }

    /// Holes per round, for wrapping (18 → 1 so a back-nine start rolls onto the
    /// front; mirrors the phone's `RoundController.holesPerRound`).
    static let holesPerRound = 18

    /// Hole steps the golfer made on the watch that the phone hasn't reflected
    /// yet. Next/Previous Hole are queued commands: the phone's hole arrives back
    /// seconds later — or, with the phone out of range, not for holes. Applying
    /// the step here keeps the wrist yardage on the hole actually being played;
    /// each phone hole change consumes the part of the step it accounts for.
    @Published private(set) var pendingHoleSteps = 0

    var holeNumber: Int {
        guard phoneState.isActive else { return watchOnlyHole }
        let n = Self.holesPerRound
        return ((phoneState.holeNumber - 1 + pendingHoleSteps) % n + n) % n + 1
    }

    /// True while the watch is ahead of (or behind) the phone's hole.
    var holeIsAheadOfPhone: Bool { phoneState.isActive && pendingHoleSteps != 0 }

    /// The watch sent a Next (+1) / Previous (−1) Hole command.
    func holeStepRequested(by delta: Int) {
        guard phoneState.isActive else { return }
        pendingHoleSteps += delta
        recompute()
    }

    var hole: CuratedHole? { course?.hole(holeNumber) }

    func update(phoneState: PhoneStateUpdate) {
        let old = self.phoneState
        if !phoneState.isActive || !old.isActive {
            pendingHoleSteps = 0 // round started/ended: nothing to reconcile against
        } else if phoneState.holeNumber != old.holeNumber, pendingHoleSteps != 0 {
            // The phone moved: consume that much of our pending step (signed,
            // shortest way round the 18 → 1 wrap). Overshoot or a move the other
            // way means the phone was changed by hand — it wins.
            let n = Self.holesPerRound
            var moved = (phoneState.holeNumber - old.holeNumber) % n
            if moved > n / 2 { moved -= n }
            if moved < -n / 2 { moved += n }
            let remaining = pendingHoleSteps - moved
            let sameDirection = (remaining >= 0) == (pendingHoleSteps >= 0)
            pendingHoleSteps = sameDirection && abs(remaining) < abs(pendingHoleSteps) ? remaining : 0
        }
        self.phoneState = phoneState
        recompute()
    }

    func update(courses: [CuratedCourse]) {
        self.courses = courses
        recompute()
    }

    func ingest(_ fix: CLLocation) {
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= Self.maxAccuracyMeters else { return }
        lastFix = fix
        lastFixAt = now()
        // One pending expiry at a time: it re-arms itself for the remainder if
        // newer fixes arrived, so 1 Hz fixes don't churn a timer per fix.
        if cancelExpiry == nil { armExpiry(after: staleAfter) }
        recompute()
    }

    func stepHole(by delta: Int) {
        let count = max(course?.holes.count ?? 18, 1)
        watchOnlyHole = (watchOnlyHole - 1 + delta + count) % count + 1
    }

    func reset() {
        cancelExpiry?()
        cancelExpiry = nil
        lastFix = nil
        lastFixAt = nil
        recompute()
    }

    private func armExpiry(after delay: TimeInterval) {
        cancelExpiry = scheduleExpiry(delay) { [weak self] in self?.expiryFired() }
    }

    private func expiryFired() {
        cancelExpiry = nil
        guard let at = lastFixAt else { return }
        let remaining = staleAfter - now().timeIntervalSince(at)
        if remaining > 0 {
            armExpiry(after: remaining)
            return
        }
        // Aged out with no newer fix: drop it. The resolved course stays (sticky).
        lastFix = nil
        lastFixAt = nil
        recompute()
    }

    private func recompute() {
        let resolved: CuratedCourse? = {
            if phoneState.isActive, let id = phoneState.curatedCourseId,
               let linked = courses.first(where: { $0.id == id }) {
                return linked
            }
            guard let fix = lastFix else {
                // No fix: keep the current course, refreshed from the catalog.
                return course.flatMap { c in courses.first { $0.id == c.id } } ?? course
            }
            // Sticky once found: a drive that strays toward a neighbouring
            // course mustn't flip the round to it.
            if let current = course.flatMap({ c in courses.first { $0.id == c.id } }),
               Distance.meters(from: fix.coordinate, to: current.location.coordinate) <= CourseCatalog.nearestRadiusMeters {
                return current
            }
            return CourseCatalog.nearest(in: courses, to: fix.coordinate)
        }()
        if resolved != course { course = resolved }

        let yards = lastFix.flatMap { resolved?.yardsToGreen(from: $0.coordinate, holeNumber: holeNumber) }
        if yards != localYards { localYards = yards }
    }

    /// Default scheduler: a sleeping main-actor Task (the workout session keeps
    /// the watch app running, so it fires wrist-down too).
    nonisolated static let taskScheduler: ExpiryScheduler = { delay, fire in
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            fire()
        }
        return { task.cancel() }
    }
}
