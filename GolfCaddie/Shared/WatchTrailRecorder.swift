import CoreLocation
import Foundation

/// Buffers and thins the watch's GPS fixes into queued trail batches (B38).
/// Pure value type so the policy is unit-tested on the phone target; the watch
/// owns one instance and flushes it with `transferUserInfo`.
///
/// Thinning keeps the payload (and watch radio time) small: a fix is kept only if
/// 2 s have passed since the last kept fix or it moved 3 m or more. Fixes with
/// hAcc <= 0 or > 20 m are never recorded (a bad trail is worse than a gap: the
/// phone falls back to its own breadcrumbs across gaps).
struct WatchTrailRecorder {
    static let maxAccuracy: Double = 20
    static let minInterval: TimeInterval = 2
    static let minMoveMeters: Double = 3
    /// Upper bound per batch, so one payload stays around 3 KB.
    static let maxFixesPerBatch = 60

    private(set) var buffer: [WatchFix] = []
    private var lastKept: WatchFix?

    var count: Int { buffer.count }

    /// Returns whether the fix was kept.
    @discardableResult
    mutating func record(_ fix: WatchFix) -> Bool {
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= Self.maxAccuracy else { return false }
        if let last = lastKept {
            let elapsed = fix.timestamp - last.timestamp
            let moved = Distance.meters(
                from: .init(latitude: last.latitude, longitude: last.longitude),
                to: .init(latitude: fix.latitude, longitude: fix.longitude))
            guard elapsed >= Self.minInterval || moved >= Self.minMoveMeters else { return false }
        }
        buffer.append(fix)
        lastKept = fix
        return true
    }

    /// Everything buffered, split into bounded batches with fresh ids. Empties
    /// the buffer; the thinning anchor is kept so the next flush continues smoothly.
    mutating func drain() -> [WatchTrailBatch] {
        defer { buffer = [] }
        return stride(from: 0, to: buffer.count, by: Self.maxFixesPerBatch).map {
            WatchTrailBatch(batchId: UUID(),
                            fixes: Array(buffer[$0..<min($0 + Self.maxFixesPerBatch, buffer.count)]))
        }
    }
}
