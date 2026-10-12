import CoreLocation
import Foundation
import HealthKit

/// Runs an HKWorkoutSession for the duration of a round. The session is what
/// keeps Core Motion and GPS delivering in the background / wrist-down; the
/// live builder + route builder save the round to Health as a golf workout
/// with its map. Sessions shorter than `minimumSavedDuration` are discarded so
/// test starts don't litter Fitness.
final class WorkoutKeeper: NSObject, HKWorkoutSessionDelegate {
    enum KeeperError: LocalizedError {
        case healthDataUnavailable
        var errorDescription: String? { "Health data unavailable on this device" }
    }

    static let minimumSavedDuration: TimeInterval = 120

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var routePointCount = 0
    private var startedAt: Date?

    /// Reported on the main queue if the session fails mid-recording.
    var onFailure: (@MainActor (String) -> Void)?

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw KeeperError.healthDataUnavailable }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try await store.requestAuthorization(toShare: share, read: read)
    }

    func start() throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor
        let s = try HKWorkoutSession(healthStore: store, configuration: config)
        s.delegate = self
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        let now = Date()
        s.startActivity(with: now)
        b.beginCollection(withStart: now) { _, _ in }
        session = s
        builder = b
        routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        routePointCount = 0
        startedAt = now
    }

    /// Append already-filtered fixes to the workout route.
    func addRoute(_ locations: [CLLocation]) {
        guard let routeBuilder, !locations.isEmpty else { return }
        routePointCount += locations.count
        routeBuilder.insertRouteData(locations) { _, _ in }
    }

    func stop() {
        guard let s = session else { return }
        let b = builder, route = routeBuilder
        let hasRoute = routePointCount > 0
        let tooShort = Date().timeIntervalSince(startedAt ?? Date()) < Self.minimumSavedDuration
        session = nil; builder = nil; routeBuilder = nil; startedAt = nil

        s.end()
        b?.endCollection(withEnd: Date()) { _, _ in
            if tooShort {
                b?.discardWorkout()
                route?.discard()
                return
            }
            b?.finishWorkout { workout, _ in
                guard let workout, hasRoute else { route?.discard(); return }
                route?.finishRoute(with: workout, metadata: nil) { _, _ in }
            }
        }
    }

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        if let onFailure {
            DispatchQueue.main.async { onFailure(message) }
        }
    }
}
