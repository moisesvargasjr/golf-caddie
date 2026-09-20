import Foundation
import SwiftUI
import WatchKit

/// A detected swing awaiting confirmation on the watch (drives the DetectCard).
struct DetectedSwing: Identifiable, Equatable {
    let id = UUID()
    let detectionUptime: Double
    let impactPeakG: Double
    let arcGyro: Double
}

/// The watch's round-session brain. Runs a workout session (keeps Core Motion
/// alive) feeding ONE motion path into the live swing detector; each detection
/// fires a haptic and emits a SwingEvent to the phone. In validation mode it
/// ALSO records the raw binary files + ground-truth marks and transfers them,
/// for continued FP/FN measurement against the offline detector.
@MainActor
final class LiveSessionController: ObservableObject {
    @Published private(set) var running = false
    #if DEBUG
    @Published var validationMode = false
    #endif
    @Published private(set) var deliveredHz: Double = 0
    /// Live peak impact (g) for the "listening" meter; 0 when idle.
    @Published private(set) var liveImpact: Double = 0
    @Published private(set) var detectionCount = 0

    /// Impact threshold a real ball-strike crosses — the meter's full-scale mark.
    let impactThreshold = LiveSwingDetector.Params().impactThreshG
    @Published private(set) var lastDetectionAt: Date?
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastError: String?

    /// A detected swing awaiting on-watch confirmation (the DetectCard). nil
    /// when no card is showing.
    @Published private(set) var pending: DetectedSwing?

    #if DEBUG
    /// Validation-mode ground-truth labelling (spike-only, B20).
    @Published var selectedLabel: RepLabel = .fullShot
    @Published private(set) var repCounts: [RepLabel: Int] = [:]
    #endif

    /// On-wrist yardage (watch GPS + cached catalog).
    let caddie = WatchCaddie()

    private let workout = WorkoutKeeper()
    private let recorder = MotionRecorder()
    private let location = WatchLocationProvider()
    private var detector: LiveSwingDetector?

    // Club state: the effective club is whichever of {phone, local Crown} has
    // the higher epoch (resolves the cross-device race without clock compares).
    @Published private(set) var localClub: (short: String, epoch: Int)?

    #if DEBUG
    private var meta: SessionMeta?
    private var sessionDir: URL?
    private var anchorTimer: Timer?
    private var batteryTimer: Timer?
    #endif

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        WatchSession.shared.activate()
        recorder.onRateSample = { [weak self] hz in self?.deliveredHz = hz }
        workout.onFailure = { [weak self] message in self?.lastError = "Workout: \(message)" }
        location.onFix = { [weak self] fix in
            guard let self, self.running else { return }
            self.caddie.ingest(fix)
            if fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= WatchCaddie.maxAccuracyMeters {
                self.workout.addRoute([fix])
            }
        }
        Task { await WatchCourseStore.shared.fetchIfStale() }
    }

    /// A phone round owns hole, club and shots; without one the watch runs on
    /// its own (yardage + workout only — shot logging stays phone-side for now).
    var phoneLed: Bool { WatchSession.shared.phoneState.isActive }

    var batteryPercent: Int { Int((WKInterfaceDevice.current().batteryLevel * 100).rounded()) }

    /// Club to stamp on a SwingEvent — local Crown selection wins iff its epoch
    /// is higher than the phone's last-known, else the phone's.
    var effectiveClubShort: String? {
        let phone = WatchSession.shared.phoneState
        if let local = localClub, local.epoch >= phone.clubEpoch { return local.short }
        return phone.currentClubShortName
    }

    /// Crown picker (M6) calls this; bumps the local epoch above the phone's so
    /// the change wins, and notifies the phone.
    func selectClub(short: String) {
        let nextEpoch = max(WatchSession.shared.phoneState.clubEpoch, localClub?.epoch ?? 0) + 1
        localClub = (short, nextEpoch)
        WatchSession.shared.send(.command(.clubChange(shortName: short, epoch: nextEpoch)))
    }

    /// PUTT +1 key — logs one putt per tap. No debounce: putts are commonly
    /// batch-logged a few rapid taps at a time after the fact (you sink it, then
    /// tap to catch up), so consecutive same-spot taps are real putts, not
    /// accidental double-taps (field note 2026-06-30).
    func sendPutt() {
        WatchSession.shared.send(.command(.puttPlusOne))
        WKInterfaceDevice.current().play(.success)
    }

    func toggle() async {
        if running { stop() } else { await start() }
    }

    func start() async {
        guard !running else { return }
        lastError = nil
        do {
            try await workout.requestAuthorization()

            let det = LiveSwingDetector()
            det.onDetection = { [weak self] detection in
                // Fires on the motion queue — hop to main for UI + WC.
                Task { @MainActor in self?.handleDetection(detection) }
            }
            det.onActivity = { [weak self] g in
                Task { @MainActor in self?.liveImpact = g }
            }
            detector = det
            recorder.onAccel = { [weak det] t, x, y, z in det?.ingestAccel(t: t, x: x, y: y, z: z) }
            recorder.onGyro = { [weak det] t, x, y, z in det?.ingestGyro(t: t, x: x, y: y, z: z) }

            #if DEBUG
            var dir: URL?
            if validationMode {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let id = "spike-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4).lowercased())"
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let d = docs.appendingPathComponent(id, isDirectory: true)
                try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                var m = SessionMeta(sessionId: id, device: .current())
                m.startedAtWallClock = Date().timeIntervalSince1970
                m.anchors.append(.now())
                m.battery.append(.now())
                meta = m
                sessionDir = d
                dir = d
            }
            #else
            let dir: URL? = nil // raw recording is validation-only (B20)
            #endif

            try workout.start()
            try recorder.start(recordRawTo: dir)
            location.start()

            detectionCount = 0
            startedAt = Date()
            running = true
            #if DEBUG
            repCounts = [:]
            scheduleTimers()
            #endif
            WKInterfaceDevice.current().play(.start)
        } catch {
            lastError = error.localizedDescription
            workout.stop()
            recorder.stop()
            location.stop()
            detector = nil
        }
    }

    private func handleDetection(_ detection: LiveSwingDetector.Detection) {
        detectionCount += 1
        lastDetectionAt = Date()
        WKInterfaceDevice.current().play(.notification)
        // Watch-only: there's no round to log into yet — count it, skip the card.
        guard phoneLed else { return }
        // Raise the confirm card (one at a time). Confirm/timeout emits the
        // event; "Not a shot" drops it. The phone-side step-gate is the backstop
        // for any practice swing that auto-logs before the user dismisses.
        guard pending == nil else { return }
        pending = DetectedSwing(
            detectionUptime: detection.t,
            impactPeakG: detection.impactPeakG,
            arcGyro: detection.arcGyro
        )
    }

    /// DetectCard "Log it" / countdown timeout — emit the swing to the phone.
    func confirmPending() {
        guard let p = pending else { return }
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let nowWall = Date().timeIntervalSince1970
        let wallClock = nowWall - (nowUptime - p.detectionUptime)
        let event = SwingEvent(
            id: UUID(),
            watchWallClock: wallClock,
            watchUptime: p.detectionUptime,
            club: effectiveClubShort,
            confidence: min(1.0, p.impactPeakG / 20.0),
            source: .auto,
            impactPeakG: p.impactPeakG,
            arcGyro: p.arcGyro
        )
        WatchSession.shared.send(.swing(event))
        pending = nil
    }

    /// DetectCard "Not a shot" — discard without emitting.
    func dismissPending() {
        pending = nil
    }

    #if DEBUG
    /// Validation-mode ground-truth mark (spike-only, B20).
    func mark() {
        guard running, validationMode else { return }
        let label = selectedLabel
        let next = (repCounts[label] ?? 0) + 1
        repCounts[label] = next
        meta?.marks.append(GroundTruthMark(
            label: label.rawValue, repIndex: next,
            uptime: ProcessInfo.processInfo.systemUptime, wallClock: Date().timeIntervalSince1970
        ))
        WKInterfaceDevice.current().play(.success)
    }
    #endif

    func stop() {
        guard running else { return }
        #if DEBUG
        anchorTimer?.invalidate(); batteryTimer?.invalidate()
        anchorTimer = nil; batteryTimer = nil
        #endif

        #if DEBUG
        let counts = recorder.stop()
        #else
        recorder.stop()
        #endif
        workout.stop()
        location.stop()
        caddie.reset()
        detector = nil

        #if DEBUG
        // Validation/spike: finalize and ship the raw session (B20).
        if var m = meta, let dir = sessionDir {
            m.anchors.append(.now())
            m.battery.append(.now())
            m.endedAtWallClock = Date().timeIntervalSince1970
            m.counts = ["dm": counts.dm, "accel": counts.accel, "gyro": counts.gyro]
            m.gyroSource = recorder.gyroSource
            do {
                let data = try JSONEncoder().encode(m)
                try data.write(to: dir.appendingPathComponent("session.json"))
                WatchSession.shared.send(sessionDir: dir, sessionId: m.sessionId)
            } catch {
                lastError = "Save failed: \(error.localizedDescription)"
            }
        }
        meta = nil; sessionDir = nil
        #endif
        startedAt = nil
        deliveredHz = 0
        liveImpact = 0
        running = false
        WKInterfaceDevice.current().play(.stop)
    }

    #if DEBUG
    /// Force the play screens (no workout / motion) for simulator UI previews,
    /// with a fixed half-threshold impact so the listening meter is visible.
    func debugEnterPreview() {
        guard !running else { return }
        running = true
        startedAt = Date()
        liveImpact = impactThreshold * 0.5
    }
    #endif

    #if DEBUG
    /// Validation/spike telemetry sampling (anchors + battery into the session) — B20.
    private func scheduleTimers() {
        anchorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.meta?.anchors.append(.now()) }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.meta?.battery.append(.now()) }
        }
    }
    #endif
}
