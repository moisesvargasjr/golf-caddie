import Foundation
import WatchConnectivity

/// The watch's single WCSession owner. Subsumes the old WatchTransfer:
///   - swing events / commands → `transferUserInfo` (queued, FIFO, survives
///     disconnects — must-not-lose, same robustness as file transfer);
///   - raw validation-session files → `transferFile` (persistent queue);
///   - phone → watch glance state ← `didReceiveApplicationContext` (latest-wins).
@MainActor
final class WatchSession: NSObject, ObservableObject {
    static let shared = WatchSession()

    @Published private(set) var phoneState = PhoneStateUpdate.inactive
    #if DEBUG
    /// Outstanding *file* transfers (validation-session bins) — drives the spike
    /// RESEND affordance on the start screen (validation-only, B20).
    @Published private(set) var outstanding = 0
    @Published private(set) var deliveredCount = 0
    #endif
    /// Outstanding watch→phone *messages* (swings + commands) still queued for
    /// delivery — drives the play-screen "SYNCING N" chip (B4). When the phone
    /// is unreachable (in the bag / dead) this stays > 0 so a backlog is visible
    /// rather than falsely reassuring; it drains to 0 once the link recovers.
    @Published private(set) var outstandingMessages = 0
    @Published private(set) var lastTransferError: String?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        refreshOutstanding()
    }

    /// Send a swing event / command. Encoded once; the queue handles delivery.
    /// Refreshes the outstanding-message count so the "SYNCING N" chip reflects
    /// the just-queued transfer immediately (it clears via `didFinish
    /// userInfoTransfer` once the phone acknowledges).
    func send(_ message: WatchToPhoneMessage) {
        guard WCSession.isSupported(), let data = try? message.encoded() else { return }
        WCSession.default.transferUserInfo([ShotContract.payloadKey: data])
        refreshOutstanding()
    }

    /// No phone push has ever landed (fresh install / reinstall): ask the phone
    /// to send the catalog regardless of what it believes it delivered. Queued,
    /// so it survives the phone being away; once per launch is enough.
    private var requestedCatalog = false
    func requestCatalogIfNeeded() {
        guard WCSession.isSupported(), !requestedCatalog, WatchCourseStore.shared.needsPhonePush else { return }
        requestedCatalog = true
        WCSession.default.transferUserInfo([ShotContract.catalogRequestKey: true])
    }

    // MARK: - GPS/battery telemetry transfer (spike step 6 — Release builds too)

    /// Telemetry files still on the watch awaiting confirmed delivery.
    @Published private(set) var telemetryPending = 0
    /// The session currently being recorded — never (re)queued mid-write.
    var activeTelemetrySessionId: String?

    /// Queue a finished session's files. A file is deleted only once
    /// `didFinish fileTransfer` confirms delivery; anything left behind (failed
    /// transfer, app killed) is re-queued by `requeueTelemetry` at next launch.
    func sendTelemetry(sessionDir: URL, sessionId: String) {
        guard WCSession.isSupported() else { return }
        let queued = Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL.path })
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)) ?? []
        for url in files where !queued.contains(url.standardizedFileURL.path) {
            WCSession.default.transferFile(url, metadata: [
                ShotContract.fileKindKey: WatchTelemetryFormat.fileKind,
                WatchTelemetryFormat.sessionIdKey: sessionId,
                WatchTelemetryFormat.filenameKey: url.lastPathComponent,
            ])
        }
        refreshTelemetryPending()
    }

    func requeueTelemetry() {
        for dir in telemetryDirs() where dir.lastPathComponent != activeTelemetrySessionId {
            sendTelemetry(sessionDir: dir, sessionId: dir.lastPathComponent)
        }
        refreshTelemetryPending()
    }

    private func telemetryDirs() -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirs = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        return dirs.filter { $0.lastPathComponent.hasPrefix(WatchTelemetryFormat.sessionPrefix) }
    }

    private func refreshTelemetryPending() {
        telemetryPending = telemetryDirs()
            .filter { $0.lastPathComponent != activeTelemetrySessionId }
            .reduce(0) { $0 + ((try? FileManager.default.contentsOfDirectory(atPath: $1.path).count) ?? 0) }
    }

    /// Delivery confirmed → the watch copy can go (and the folder, once empty).
    private func telemetryDelivered(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let dir = url.deletingLastPathComponent()
        if ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty { try? fm.removeItem(at: dir) }
        refreshTelemetryPending()
    }

    var isPhoneReachable: Bool { WCSession.isSupported() && WCSession.default.isReachable }

    var debugStatus: String {
        let s = WCSession.default
        let act = ["notActivated", "inactive", "activated"][s.activationState.rawValue]
        return "WC \(act) · companion \(s.isCompanionAppInstalled ? "yes" : "NO") · reachable \(s.isReachable ? "yes" : "no")"
    }

    #if DEBUG
    // MARK: - Validation-session file transfer (spike-only, B20)

    func send(sessionDir: URL, sessionId: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            WCSession.default.transferFile(url, metadata: ["sessionId": sessionId, "filename": url.lastPathComponent])
        }
        refreshOutstanding()
    }

    /// Re-queue every session directory still on disk (recovery for failed
    /// transfers — sources are never deleted by transferFile).
    func resendAll() {
        lastTransferError = nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirs = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dir in dirs where dir.lastPathComponent.hasPrefix("spike-") {
            send(sessionDir: dir, sessionId: dir.lastPathComponent)
        }
    }
    #endif

    private func refreshOutstanding() {
        #if DEBUG
        outstanding = WCSession.default.outstandingFileTransfers.count
        #endif
        // Round traffic only. The one-off catalog request also rides
        // transferUserInfo, and watch-only it showed "SYNC 1" with nothing
        // shot-related queued.
        outstandingMessages = WCSession.default.outstandingUserInfoTransfers
            .filter { $0.userInfo[ShotContract.payloadKey] != nil }.count
    }

    #if DEBUG
    func debugSetPhoneState(_ state: PhoneStateUpdate) { phoneState = state }
    #endif
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.requestCatalogIfNeeded()
            self.requeueTelemetry()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[ShotContract.payloadKey] as? Data,
              let state = try? PhoneStateUpdate.decode(data) else { return }
        Task { @MainActor in self.phoneState = state }
    }

    /// Phone → watch course catalog push (WatchCatalogPusher). The temp file is
    /// deleted when this callback returns — read it now.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[ShotContract.fileKindKey] as? String == ShotContract.courseCatalogKind,
              let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in WatchCourseStore.shared.installPhonePush(data) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        let filename = url.lastPathComponent
        let failure = error?.localizedDescription
        if fileTransfer.file.metadata?[ShotContract.fileKindKey] as? String == WatchTelemetryFormat.fileKind {
            Task { @MainActor in
                if let failure {
                    self.lastTransferError = "\(filename): \(failure)" // file kept; re-queued next launch
                } else {
                    self.telemetryDelivered(url)
                }
            }
            return
        }
        #if DEBUG
        Task { @MainActor in
            if let failure {
                self.lastTransferError = "\(filename): \(failure)"
            } else {
                self.deliveredCount += 1
            }
            self.refreshOutstanding()
        }
        #endif
    }

    /// A queued swing/command transfer finished (delivered or errored). Drains
    /// the "SYNCING N" backlog as the phone acknowledges each one (B4). The
    /// effect is idempotent on the phone (B2), so the system's at-least-once
    /// redelivery on reconnect can't double-apply.
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let failure = error?.localizedDescription
        Task { @MainActor in
            if let failure { self.lastTransferError = failure }
            self.refreshOutstanding()
        }
    }
}
