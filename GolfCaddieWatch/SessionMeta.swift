import Foundation
import WatchKit

/// Wire/disk schema for `session.json` — must stay in sync with the Python
/// parser in `scripts/swing_spike/spikelib.py` (schemaVersion 1).

struct ClockAnchor: Codable {
    let wallClock: Double // unix epoch seconds
    let uptime: Double // ProcessInfo.systemUptime — same timebase as CMLogItem.timestamp

    static func now() -> ClockAnchor {
        ClockAnchor(wallClock: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime)
    }
}

struct GroundTruthMark: Codable {
    let label: String
    let repIndex: Int
    let uptime: Double
    let wallClock: Double
}

struct BatterySample: Codable {
    let uptime: Double
    let level: Double // 0...1, -1 if unknown

    static func now() -> BatterySample {
        BatterySample(
            uptime: ProcessInfo.processInfo.systemUptime,
            level: Double(WKInterfaceDevice.current().batteryLevel)
        )
    }
}

struct DeviceInfo: Codable {
    let model: String
    let systemVersion: String

    static func current() -> DeviceInfo {
        let d = WKInterfaceDevice.current()
        return DeviceInfo(model: d.model, systemVersion: "\(d.systemName) \(d.systemVersion)")
    }
}

struct SessionMeta: Codable {
    var schemaVersion = 1
    let sessionId: String
    let device: DeviceInfo
    var anchors: [ClockAnchor] = []
    var marks: [GroundTruthMark] = []
    var battery: [BatterySample] = []
    var counts: [String: Int] = [:]
    /// "raw" or "deviceMotion" — watchOS hides the raw gyro, so gyro.bin is
    /// fused rotationRate there. Analysis should know which it's looking at.
    var gyroSource: String?
    var startedAtWallClock: Double?
    var endedAtWallClock: Double?
}

enum RepLabel: String, CaseIterable, Identifiable, Codable {
    case fullShot = "full_shot"
    case practiceSwing = "practice_swing"
    case chip
    case putt
    case noise

    var id: String { rawValue }

    var display: String {
        switch self {
        case .fullShot: "Full shot"
        case .practiceSwing: "Practice swing"
        case .chip: "Chip"
        case .putt: "Putt"
        case .noise: "Noise"
        }
    }
}
