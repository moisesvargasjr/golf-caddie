import Foundation
import WatchConnectivity

/// Queues completed session files to the phone. `transferFile` is the right
/// primitive here: the queue is persistent, survives app/watch restarts, and
/// drains opportunistically when the phone app runs — no live link required.
@MainActor
final class WatchTransfer: NSObject, ObservableObject {
    static let shared = WatchTransfer()

    @Published private(set) var outstanding = 0
    @Published private(set) var lastTransferError: String?
    @Published private(set) var deliveredCount = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        refreshOutstanding()
    }

    /// Debug string for the controls page — where is the pipe broken?
    var debugStatus: String {
        let s = WCSession.default
        let act = ["notActivated", "inactive", "activated"][s.activationState.rawValue]
        return "WC \(act) · companion \(s.isCompanionAppInstalled ? "yes" : "NO") · reachable \(s.isReachable ? "yes" : "no")"
    }

    func send(sessionDir: URL, sessionId: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            WCSession.default.transferFile(url, metadata: [
                "sessionId": sessionId,
                "filename": url.lastPathComponent,
            ])
        }
        refreshOutstanding()
    }

    /// Re-queue every session directory still on disk. Recovery path for
    /// failed transfers — transferFile never deletes sources, so the data is
    /// always still here.
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
}

extension WatchTransfer: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

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
