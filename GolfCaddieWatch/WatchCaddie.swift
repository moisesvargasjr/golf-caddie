import Combine
import CoreLocation
import Foundation

/// On-wrist yardage: the watch's own fix + the cached catalog → yards to the
/// current hole's green, no phone involved (docs/WATCH_STANDALONE_SPIKE.md).
///
/// Hole + course come from the phone while a phone round is active (the phone
/// stays the round's owner); with no phone round the watch is on its own —
/// nearest cached course, holes stepped by hand.
@MainActor
final class WatchCaddie: ObservableObject {
    /// Fixes worse than this don't drive the yardage (or the workout route).
    static let maxAccuracyMeters: CLLocationAccuracy = 50
    /// A local yardage older than this is treated as gone (falls back to the phone's).
    static let staleAfter: TimeInterval = 20

    @Published private(set) var course: CuratedCourse?
    @Published private(set) var localYards: Int?
    @Published private(set) var lastFixAt: Date?
    /// The hole when there's no phone round to follow.
    @Published var watchOnlyHole = 1 { didSet { recompute() } }

    private var lastFix: CLLocation?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        WatchSession.shared.$phoneState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
        WatchCourseStore.shared.$courses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    var holeNumber: Int {
        let phone = WatchSession.shared.phoneState
        return phone.isActive ? phone.holeNumber : watchOnlyHole
    }

    var hole: CuratedHole? { course?.hole(holeNumber) }

    /// The local yardage, or nil once the last good fix has aged out.
    var freshLocalYards: Int? {
        guard let at = lastFixAt, Date().timeIntervalSince(at) < Self.staleAfter else { return nil }
        return localYards
    }

    func ingest(_ fix: CLLocation) {
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= Self.maxAccuracyMeters else { return }
        lastFix = fix
        lastFixAt = Date()
        recompute()
    }

    func stepHole(by delta: Int) {
        let count = max(course?.holes.count ?? 18, 1)
        watchOnlyHole = (watchOnlyHole - 1 + delta + count) % count + 1
    }

    func reset() {
        lastFix = nil
        lastFixAt = nil
        localYards = nil
    }

    private func recompute() {
        let store = WatchCourseStore.shared
        let phone = WatchSession.shared.phoneState

        let resolved: CuratedCourse? = {
            if phone.isActive, let id = phone.curatedCourseId, let linked = store.course(byId: id) {
                return linked
            }
            guard let fix = lastFix else { return course }
            // Sticky once found: a drive that strays toward a neighbouring
            // course mustn't flip the round to it.
            if let current = course, store.course(byId: current.id) != nil,
               Distance.meters(from: fix.coordinate, to: current.location.coordinate) <= CourseCatalog.nearestRadiusMeters {
                return store.course(byId: current.id)
            }
            return CourseCatalog.nearest(in: store.courses, to: fix.coordinate)
        }()
        if resolved != course { course = resolved }

        let yards = lastFix.flatMap { resolved?.yardsToGreen(from: $0.coordinate, holeNumber: holeNumber) }
        if yards != localYards { localYards = yards }
    }
}
