import Foundation
import WatchConnectivity

/// The phone's single WCSession delegate. Two roles, one delegate object:
///   - live shot logging: `didReceiveUserInfo` decodes a WatchToPhoneMessage
///     (swing event / command) and hands it to LiveShotCoordinator;
///   - validation spike: `didReceive file:` lands raw recording files in
///     Documents/SpikeSessions/<sessionId>/ (UIFileSharingEnabled exposes them).
final class SpikeSessionReceiver: NSObject {
    static let shared = SpikeSessionReceiver()

    #if DEBUG
    static var sessionsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpikeSessions", isDirectory: true)
    }

    private let receiptQueue = DispatchQueue(label: "spike.receiver.receipts")
    #endif

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension SpikeSessionReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // The launch-time catalog sync can finish before activation does.
        WatchCatalogPusher.pushIfChanged()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// A retry trigger for a catalog push that failed while the watch was away.
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { WatchCatalogPusher.pushIfChanged() }
    }

    /// Catalog push outcome — only a confirmed delivery marks the hash delivered.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let metadata = fileTransfer.file.metadata
        guard metadata?[ShotContract.fileKindKey] as? String == ShotContract.courseCatalogKind else { return }
        WatchCatalogPusher.transferFinished(hash: metadata?[ShotContract.catalogHashKey] as? String, error: error)
    }

    /// Live swing events / commands from the watch (transferUserInfo, queued).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // A watch with no phone push yet (fresh install / reinstall) asks for one.
        if userInfo[ShotContract.catalogRequestKey] != nil {
            WatchCatalogPusher.pushIfChanged(force: true)
            return
        }
        guard let data = userInfo[ShotContract.payloadKey] as? Data,
              let message = try? WatchToPhoneMessage.decode(data) else { return }
        LiveShotCoordinator.shared.receive(message)
    }

    #if DEBUG
    // Validation/spike file receipt + storage — compiled out of Release (B20).
    // The production live-shot path (didReceiveUserInfo, above) stays in Release.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The temp file is deleted when this callback returns — move it now.
        let sessionId = (file.metadata?["sessionId"] as? String) ?? "unknown-session"
        let filename = (file.metadata?["filename"] as? String) ?? file.fileURL.lastPathComponent
        let dir = Self.sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: file.fileURL, to: dest)
            appendReceipt(sessionId: sessionId, filename: filename, dir: dir)
        } catch {
            NSLog("SpikeSessionReceiver: failed to store \(filename) for \(sessionId): \(error)")
        }
    }

    /// Phone-side receipt log — wall-clock per file, kept so watch↔phone clock
    /// drift can be estimated later (phase-2 fusion concern, not the spike's).
    private func appendReceipt(sessionId: String, filename: String, dir: URL) {
        receiptQueue.async {
            let url = dir.appendingPathComponent("received.json")
            var entries: [[String: Any]] = []
            if let data = try? Data(contentsOf: url),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                entries = existing
            }
            entries.append([
                "filename": filename,
                "receivedAtWallClock": Date().timeIntervalSince1970,
            ])
            if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted]) {
                try? data.write(to: url)
            }
        }
    }
    #endif
}
