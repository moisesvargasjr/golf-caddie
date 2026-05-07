import Observation
import UIKit

@Observable
@MainActor
final class BatteryMonitor {
    private(set) var level: Float = -1
    private(set) var state: UIDevice.BatteryState = .unknown

    @ObservationIgnored
    private var observers: [NSObjectProtocol] = []

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    var hasReading: Bool { level >= 0 }

    var percent: Int? {
        guard hasReading else { return nil }
        return Int((level * 100).rounded())
    }

    var iconName: String {
        guard hasReading else { return "battery.0" }
        let bolt = (state == .charging || state == .full) ? ".bolt" : ""
        switch level {
        case 0.875...: return "battery.100\(bolt)"
        case 0.625 ..< 0.875: return "battery.75\(bolt)"
        case 0.375 ..< 0.625: return "battery.50\(bolt)"
        case 0.125 ..< 0.375: return "battery.25\(bolt)"
        default: return "battery.0\(bolt)"
        }
    }

    private func refresh() {
        level = UIDevice.current.batteryLevel
        state = UIDevice.current.batteryState
    }
}
