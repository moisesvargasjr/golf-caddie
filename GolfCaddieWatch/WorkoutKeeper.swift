import Foundation
import HealthKit

/// Runs an HKWorkoutSession for the duration of a recording purely to keep
/// Core Motion delivering in the background / wrist-down. No live builder —
/// we deliberately do not save a workout to Health.
final class WorkoutKeeper: NSObject, HKWorkoutSessionDelegate {
    enum KeeperError: LocalizedError {
        case healthDataUnavailable
        var errorDescription: String? { "Health data unavailable on this device" }
    }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    /// Reported on the main queue if the session fails mid-recording.
    var onFailure: (@MainActor (String) -> Void)?

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw KeeperError.healthDataUnavailable }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
    }

    func start() throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor
        let s = try HKWorkoutSession(healthStore: store, configuration: config)
        s.delegate = self
        s.startActivity(with: Date())
        session = s
    }

    func stop() {
        session?.end()
        session = nil
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
