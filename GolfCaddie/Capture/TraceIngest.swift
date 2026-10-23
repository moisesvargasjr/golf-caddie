import Foundation

/// Files watch trail batches into the right round's `tracePoint` rows (B38).
/// Batches ride `transferUserInfo`, so they can arrive minutes or hours after the
/// fixes were taken, even after the round ended or a new one started.
enum TraceIngest {
    struct Result: Equatable {
        /// Rows actually inserted (0 for a replayed batch).
        var inserted: Int
        /// Per round that received at least one new point, the time span of the batch's fixes.
        var spans: [UUID: ClosedRange<Date>]
        /// Fixes that matched no round and were discarded.
        var dropped: Int = 0

        var roundIDs: Set<UUID> { Set(spans.keys) }
    }

    /// The watch may start recording a little before the phone round, and a round
    /// is ended a little after the last fix; tolerate that much either side. (A
    /// watch workout often starts well before the phone round, hence 10 minutes.)
    static let slackBeforeStart: TimeInterval = 600
    static let slackAfterEnd: TimeInterval = 300

    /// Splits `fixes` by the round whose time window contains each one. A fix that
    /// fits no round is dropped (we can't say whose it is). Exact containment
    /// wins over slack, then the most recently started round.
    static func assign(_ fixes: [WatchFix], rounds: [Round]) -> [UUID: [WatchFix]] {
        var out: [UUID: [WatchFix]] = [:]
        for fix in fixes {
            let time = Date(timeIntervalSince1970: fix.timestamp)
            if let round = owner(of: time, in: rounds) { out[round.id, default: []].append(fix) }
        }
        return out
    }

    private static func owner(of time: Date, in rounds: [Round]) -> Round? {
        let exact = rounds.filter { time >= $0.startedAt && time <= ($0.endedAt ?? .distantFuture) }
        let tolerant = rounds.filter {
            time >= $0.startedAt.addingTimeInterval(-slackBeforeStart)
                && time <= ($0.endedAt ?? .distantFuture).addingTimeInterval(slackAfterEnd)
        }
        return (exact.isEmpty ? tolerant : exact).max { $0.startedAt < $1.startedAt }
    }

    static func ingest(_ batch: WatchTrailBatch) throws -> Result {
        let rounds = try RoundRepository.allRounds()
        var inserted = 0
        var spans: [UUID: ClosedRange<Date>] = [:]
        let assigned = assign(batch.fixes, rounds: rounds)
        let dropped = batch.fixes.count - assigned.values.reduce(0) { $0 + $1.count }
        if dropped > 0 {
            NSLog("TraceIngest: batch \(batch.batchId) dropped \(dropped) of \(batch.fixes.count) fixes (no round)")
        }
        for (roundID, fixes) in assigned {
            let points = fixes.enumerated().map { index, fix in
                TracePoint(id: pointID(batch: batch.batchId, index: index), roundID: roundID,
                           timestamp: Date(timeIntervalSince1970: fix.timestamp),
                           latitude: fix.latitude, longitude: fix.longitude,
                           accuracy: fix.horizontalAccuracy, source: .watch)
            }
            let added = try TracePointRepository.insertWatchPoints(points)
            if added > 0, let first = points.map(\.timestamp).min(), let last = points.map(\.timestamp).max() {
                spans[roundID] = first...last
            }
            inserted += added
        }
        return Result(inserted: inserted, spans: spans, dropped: dropped)
    }

    /// Deterministic per (batch, position): a redelivered batch maps to the same
    /// primary keys. (Indexes within a split batch are per-round, which is also
    /// deterministic for the same input.)
    static func pointID(batch: UUID, index: Int) -> UUID {
        var bytes = batch.uuid
        bytes.14 ^= UInt8((index >> 8) & 0xFF)
        bytes.15 ^= UInt8(index & 0xFF)
        return UUID(uuid: bytes)
    }
}
