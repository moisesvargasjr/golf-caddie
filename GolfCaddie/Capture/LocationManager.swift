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

    /// Wall-clock instant the most recent location was *received* by this
    /// process, independent of the fix's own embedded `timestamp` and
    /// independent of `distanceFilter`. The glasses `gps.stale` freshness
    /// clock keys off this: it resets on ANY received location (see
    /// didUpdateLocations) so a stationary golfer with a valid recent fix is
    /// never flagged stale. nil until the first fix arrives.
    private(set) var lastLocationReceivedAt: Date?

    /// True only when location authorization/services are genuinely
    /// unavailable (denied/restricted) — used by the glasses `gps.stale`
    /// computation as the "actually unavailable" condition, distinct from a
    /// merely-aged-but-valid fix.
    var locationUnavailable: Bool {
        switch authorizationStatus {
        case .denied, .restricted:
            return true
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            return false
        @unknown default:
            return false
        }
    }

    /// Called on the main actor for every received fix. RoundController injects
    /// this to persist throttled breadcrumbs during an active round; kept as a
    /// closure so LocationManager stays round-agnostic.
    @ObservationIgnored
    var onLocationUpdate: ((CLLocation) -> Void)?

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
        // kCLDistanceFilterNone (was 5 m): the glasses gps.stale freshness
        // path needs fixes to keep arriving while the golfer is stationary
        // (addressing/putting/waiting). A movement-gated filter only delivers
        // after ~5 m of travel, so a perfectly valid recent fix while standing
        // still would age past the stale window and flag STALE constantly.
        // No shot-distance logic in this codebase reads distanceFilter
        // (distances are computed from stored shot coordinates in
        // GlassesStateMapper.yards / Distance), so removing the filter does
        // not affect shot distances — it only restores continuous delivery.
        manager.distanceFilter = kCLDistanceFilterNone
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
            // Reset the glasses gps.stale freshness clock on ANY received
            // location, independent of distanceFilter and of the fix's own
            // embedded timestamp.
            self.lastLocationReceivedAt = Date()
            if self.preciseFixContinuation != nil,
               last.horizontalAccuracy > 0,
               last.horizontalAccuracy <= 5 {
                self.resolvePreciseFix()
            }
            self.onLocationUpdate?(last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Soft-fail; degraded fix quality reflected via fixQuality computed property.
    }
}
