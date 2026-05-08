import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    enum FixQuality {
        case none
        case degraded
        case acceptable
        case good
    }

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var latestLocation: CLLocation?
    private(set) var isTracking = false

    @ObservationIgnored
    private let manager: CLLocationManager

    @ObservationIgnored
    private var preciseFixContinuation: CheckedContinuation<CLLocation?, Never>?

    @ObservationIgnored
    private var preciseFixTimeoutTask: Task<Void, Never>?

    override init() {
        let mgr = CLLocationManager()
        self.manager = mgr
        self.authorizationStatus = mgr.authorizationStatus
        super.init()
        mgr.delegate = self
        mgr.pausesLocationUpdatesAutomatically = false
    }

    var fixQuality: FixQuality {
        guard let acc = latestLocation?.horizontalAccuracy, acc > 0 else { return .none }
        if acc <= 5 { return .good }
        if acc <= 20 { return .acceptable }
        return .degraded
    }

    func requestWhenInUse() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestAlways() {
        let status = manager.authorizationStatus
        if status == .notDetermined || status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func startTracking() {
        guard !isTracking else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    func captureBestFix(timeout: TimeInterval = 5.0) async -> CLLocation? {
        if preciseFixContinuation != nil {
            resolvePreciseFix()
        }

        let baseline = manager.desiredAccuracy
        manager.desiredAccuracy = kCLLocationAccuracyBest
        defer {
            manager.desiredAccuracy = baseline
        }

        if let loc = latestLocation,
           loc.horizontalAccuracy > 0,
           loc.horizontalAccuracy <= 5,
           Date().timeIntervalSince(loc.timestamp) < 1.0 {
            return loc
        }

        return await withCheckedContinuation { continuation in
            preciseFixContinuation = continuation
            preciseFixTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.resolvePreciseFix()
            }
        }
    }

    private func resolvePreciseFix() {
        let cont = preciseFixContinuation
        preciseFixContinuation = nil
        preciseFixTimeoutTask?.cancel()
        preciseFixTimeoutTask = nil
        cont?.resume(returning: latestLocation)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.latestLocation = last
            if self.preciseFixContinuation != nil,
               last.horizontalAccuracy > 0,
               last.horizontalAccuracy <= 5 {
                self.resolvePreciseFix()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Soft-fail; degraded fix quality reflected via fixQuality computed property.
    }
}
