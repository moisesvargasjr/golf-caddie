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
        outstandingMessages = WCSession.default.outstandingUserInfoTransfers.count
    }

    #if DEBUG
    func debugSetPhoneState(_ state: PhoneStateUpdate) { phoneState = state }
    #endif
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[ShotContract.payloadKey] as? Data,
              let state = try? PhoneStateUpdate.decode(data) else { return }
        Task { @MainActor in self.phoneState = state }
    }

    #if DEBUG
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let filename = fileTransfer.file.fileURL.lastPathComponent
        let failure = error?.localizedDescription
        Task { @MainActor in
            if let failure {
                self.lastTransferError = "\(filename): \(failure)"
            } else {
                self.deliveredCount += 1
            }
            self.refreshOutstanding()
        }
    }
    #endif

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
