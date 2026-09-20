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

    var holeNumber: Int { phoneState.isActive ? phoneState.holeNumber : watchOnlyHole }

    var hole: CuratedHole? { course?.hole(holeNumber) }

    func update(phoneState: PhoneStateUpdate) {
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
