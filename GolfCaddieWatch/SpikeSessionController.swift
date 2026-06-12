import Foundation
import SwiftUI
import WatchKit

/// State machine for one recording session: workout session (keeps sensors
/// alive) + motion recorder (binary logs) + ground-truth marks + battery
/// samples, ending in a WCSession file transfer to the phone.
@MainActor
final class SpikeSessionController: ObservableObject {
    enum Phase {
        case idle
        case recording
    }

    @Published private(set) var phase: Phase = .idle
    @Published var selectedLabel: RepLabel = .fullShot
    @Published private(set) var repCounts: [RepLabel: Int] = [:]
    @Published private(set) var deliveredHz: Double = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastError: String?

    private let workout = WorkoutKeeper()
    private let recorder = MotionRecorder()
    private var meta: SessionMeta?
    private var sessionDir: URL?
    private var anchorTimer: Timer?
    private var batteryTimer: Timer?

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        WatchTransfer.shared.activate()
        recorder.onRateSample = { [weak self] hz in self?.deliveredHz = hz }
        workout.onFailure = { [weak self] message in self?.lastError = "Workout: \(message)" }
    }

    var batteryPercent: Int {
        Int((WKInterfaceDevice.current().batteryLevel * 100).rounded())
    }

    func toggle() async {
        switch phase {
        case .idle: await start()
        case .recording: stop()
        }
    }

    func start() async {
        guard phase == .idle else { return }
        lastError = nil
        do {
            try await workout.requestAuthorization()

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let id = "spike-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4).lowercased())"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dir = docs.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var m = SessionMeta(sessionId: id, device: .current())
            m.startedAtWallClock = Date().timeIntervalSince1970
            m.anchors.append(.now())
            m.battery.append(.now())

            try workout.start()
            try recorder.start(directory: dir)

            meta = m
            sessionDir = dir
            startedAt = Date()
            repCounts = [:]
            phase = .recording
            scheduleTimers()
            WKInterfaceDevice.current().play(.start)
        } catch {
            lastError = error.localizedDescription
            workout.stop()
            _ = recorder.stop()
        }
    }

    func mark() {
        guard phase == .recording else { return }
        let label = selectedLabel
        let next = (repCounts[label] ?? 0) + 1
        repCounts[label] = next
        meta?.marks.append(
            GroundTruthMark(
                label: label.rawValue,
                repIndex: next,
                uptime: ProcessInfo.processInfo.systemUptime,
                wallClock: Date().timeIntervalSince1970
            )
        )
        WKInterfaceDevice.current().play(.success)
    }

    func stop() {
        guard phase == .recording, var m = meta, let dir = sessionDir else { return }
        anchorTimer?.invalidate()
        batteryTimer?.invalidate()
        anchorTimer = nil
        batteryTimer = nil

        let counts = recorder.stop()
        workout.stop()

        m.anchors.append(.now())
        m.battery.append(.now())
        m.endedAtWallClock = Date().timeIntervalSince1970
        m.counts = ["dm": counts.dm, "accel": counts.accel, "gyro": counts.gyro]
        m.gyroSource = recorder.gyroSource
        do {
            let data = try JSONEncoder().encode(m)
            try data.write(to: dir.appendingPathComponent("session.json"))
            WatchTransfer.shared.send(sessionDir: dir, sessionId: m.sessionId)
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }

        meta = nil
        sessionDir = nil
        startedAt = nil
        deliveredHz = 0
        phase = .idle
        WKInterfaceDevice.current().play(.stop)
    }

    private func scheduleTimers() {
        anchorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.meta?.anchors.append(.now()) }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.meta?.battery.append(.now()) }
        }
    }
}
