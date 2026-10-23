import Foundation

/// The watch's most recent streamed GPS fix (B35), for phone-originated actions
/// (phone MARK, glasses, yardage) that need to know where the golfer is.
/// In-memory only: a fix is only meaningful for a few seconds, so persisting or
/// replaying one after a relaunch would be wrong. Freshness is judged by the
/// reader (`LocationPreference`), not here.
@MainActor
final class WatchFixStore {
    static let shared = WatchFixStore()

    private(set) var latest: WatchFix?

    /// Keep the newest fix by its own timestamp, so a delayed or reordered
    /// message can't move the watch backwards. nil is ignored.
    func update(_ fix: WatchFix?) {
        guard let fix else { return }
        if let current = latest, fix.timestamp < current.timestamp { return }
        latest = fix
    }

    func reset() { latest = nil }
}
