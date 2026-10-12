import CoreLocation
import Foundation
import WatchKit

/// Spike step 6: logs every watch fix + periodic battery to a session folder in
/// Documents, handed to WatchSession for transfer at stop. Format lives in
/// Shared/WatchTelemetryFormat. On by default for the spike (a forgotten toggle
/// would waste a field-test round); the start screen can turn it off.
@MainActor
final class WatchTelemetryRecorder: ObservableObject {
    private static let enabledKey = "watchTelemetry.enabled"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    private var session: WatchTelemetrySession?
    private var dir: URL?
    private var fixes: FileHandle?
    private var battery: FileHandle?
    private var batteryTimer: Timer?

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var isRecording: Bool { session != nil }
    var activeSessionId: String? { session?.sessionId }

    func start() {
        guard enabled, session == nil else { return }
        let now = Date()
        let id = WatchTelemetryFormat.sessionId(
            startedAt: now, suffix: String(UUID().uuidString.prefix(4)).lowercased())
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            fixes = try Self.open(d.appendingPathComponent(WatchTelemetryFormat.fixesFile),
                                  header: WatchTelemetryFormat.fixesHeader)
            battery = try Self.open(d.appendingPathComponent(WatchTelemetryFormat.batteryFile),
                                    header: WatchTelemetryFormat.batteryHeader)
        } catch {
            fixes = nil; battery = nil
            return // telemetry must never block a round
        }
        let device = WKInterfaceDevice.current()
        dir = d
        session = WatchTelemetrySession(
            sessionId: id, startedAt: now.timeIntervalSince1970, endedAt: nil,
            deviceModel: Self.machineIdentifier, systemVersion: device.systemVersion,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            fixCount: 0, batteryStart: Self.batteryPercent, batteryEnd: nil
        )
        sampleBattery()
        batteryTimer = Timer.scheduledTimer(
            withTimeInterval: WatchTelemetryFormat.batteryInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.sampleBattery() }
        }
    }

    func record(_ fix: CLLocation, reachable: Bool, hole: Int, localYards: Int?, phoneYards: Int?) {
        guard session != nil, let fixes else { return }
        let row = WatchTelemetryFormat.fixRow(
            fix, receivedAt: Date(), reachable: reachable, hole: hole, localYards: localYards, phoneYards: phoneYards)
        try? fixes.write(contentsOf: Data((row + "\n").utf8))
        session?.fixCount += 1
    }

    /// Finalize the session; returns its folder for transfer (nil if not recording).
    func stop() -> (dir: URL, sessionId: String)? {
        guard var s = session, let d = dir else { return nil }
        batteryTimer?.invalidate(); batteryTimer = nil
        sampleBattery()
        try? fixes?.close(); try? battery?.close()
        fixes = nil; battery = nil
        s.endedAt = Date().timeIntervalSince1970
        s.batteryEnd = Self.batteryPercent
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: d.appendingPathComponent(WatchTelemetryFormat.sessionFile), options: .atomic)
        }
        session = nil; dir = nil
        return (d, s.sessionId)
    }

    private func sampleBattery() {
        guard let battery else { return }
        let device = WKInterfaceDevice.current()
        let row = WatchTelemetryFormat.batteryRow(
            at: Date(), level: device.batteryLevel, state: device.batteryState.rawValue)
        try? battery.write(contentsOf: Data((row + "\n").utf8))
    }

    private static var batteryPercent: Int? {
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? nil : Int((level * 100).rounded())
    }

    private static func open(_ url: URL, header: String) throws -> FileHandle {
        try Data((header + "\n").utf8).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    /// e.g. "Watch7,12" — distinguishes the Ultra 4 from older hardware in the data.
    private static var machineIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
