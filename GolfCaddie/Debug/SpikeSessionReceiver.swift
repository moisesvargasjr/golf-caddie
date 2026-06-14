import Foundation
import WatchConnectivity

/// The phone's single WCSession delegate. Two roles, one delegate object:
///   - live shot logging: `didReceiveUserInfo` decodes a WatchToPhoneMessage
///     (swing event / command) and hands it to LiveShotCoordinator;
///   - validation spike: `didReceive file:` lands raw recording files in
///     Documents/SpikeSessions/<sessionId>/ (UIFileSharingEnabled exposes them).
final class SpikeSessionReceiver: NSObject {
    static let shared = SpikeSessionReceiver()

    static var sessionsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpikeSessions", isDirectory: true)
    }

    private let receiptQueue = DispatchQueue(label: "spike.receiver.receipts")

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension SpikeSessionReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Live swing events / commands from the watch (transferUserInfo, queued).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[ShotContract.payloadKey] as? Data,
              let message = try? WatchToPhoneMessage.decode(data) else { return }
        LiveShotCoordinator.shared.receive(message)
    }

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
}
