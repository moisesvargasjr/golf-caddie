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
    @Published private(set) var outstanding = 0
    @Published private(set) var lastTransferError: String?
    @Published private(set) var deliveredCount = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        refreshOutstanding()
    }

    /// Send a swing event / command. Encoded once; the queue handles delivery.
    func send(_ message: WatchToPhoneMessage) {
        guard WCSession.isSupported(), let data = try? message.encoded() else { return }
        WCSession.default.transferUserInfo([ShotContract.payloadKey: data])
    }

    var debugStatus: String {
        let s = WCSession.default
        let act = ["notActivated", "inactive", "activated"][s.activationState.rawValue]
        return "WC \(act) · companion \(s.isCompanionAppInstalled ? "yes" : "NO") · reachable \(s.isReachable ? "yes" : "no")"
    }

    // MARK: - Validation-session file transfer (unchanged behavior)

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

    private func refreshOutstanding() {
        outstanding = WCSession.default.outstandingFileTransfers.count
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
}
