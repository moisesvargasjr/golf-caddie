import CoreLocation
import Foundation

/// The watch's own GPS — a trimmed copy of the phone's `LocationManager`
/// (best accuracy, no distance filter). Runs only inside the workout session,
/// which is what keeps fixes flowing wrist-down. Note the system sources fixes
/// from the phone's GPS while the phone is in Bluetooth range; the watch's
/// L1/L5 receiver takes over when it isn't.
@MainActor
final class WatchLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isTracking = false

    /// Every received fix, on the main actor.
    var onFix: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func start() {
        guard !isTracking else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stop() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        isTracking = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for fix in locations { self.onFix?(fix) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Soft-fail, like the phone: no fix simply means the phone's pushed
        // yardage (if any) stays on screen.
    }
}
