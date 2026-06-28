import CoreLocation
import Foundation

/// Tunable parameters for stop/dwell detection (B5). The two field-test knobs —
/// dwell time `T` and radius `R` — are surfaced so they can be adjusted **without
/// recompiling** shipped logic: `.default` reads optional `UserDefaults`
/// overrides and falls back to the baked-in starting values. Tests pass an
/// explicit config so they stay deterministic regardless of any installed override.
struct StopDetectionConfig: Equatable {
    /// Minimum time (s) the golfer must dwell within `radiusMeters` for the
    /// cluster to count as a candidate shot location. Start ≈ 8 s.
    var minDwellSeconds: TimeInterval
    /// Spatial radius (m) that defines "stayed in one place" — wide enough to
    /// absorb GPS jitter at address, tight enough to break on a walk. Start ≈ 5 m.
    var radiusMeters: Double

    init(minDwellSeconds: TimeInterval = 8, radiusMeters: Double = 5) {
        self.minDwellSeconds = minDwellSeconds
        self.radiusMeters = radiusMeters
    }

    static let minDwellDefaultsKey = "stopDetect.minDwellSeconds"
    static let radiusDefaultsKey = "stopDetect.radiusMeters"

    /// Baked defaults, overridable at runtime via `UserDefaults` (field-test knobs).
    static var `default`: StopDetectionConfig {
        let d = UserDefaults.standard
        return StopDetectionConfig(
            minDwellSeconds: (d.object(forKey: minDwellDefaultsKey) as? Double) ?? 8,
            radiusMeters: (d.object(forKey: radiusDefaultsKey) as? Double) ?? 5
        )
    }
}

/// A place the golfer dwelled on the track — a candidate shot location for
/// end-of-hole reconstruction (B6/B7). Returned in **track (time) order** so a
/// caller can lay pins tee→green; each carries a `prominence` so reconstruction
/// can pick the N most prominent when the stop count disagrees with the score.
struct TrackStop: Equatable {
    var latitude: Double
    var longitude: Double
    /// First / last breadcrumb timestamp inside the dwell.
    var arrival: Date
    var departure: Date
    var sampleCount: Int
    /// 0…1, monotonic in dwell time (a longer stand = a stronger candidate).
    /// Saturates at `prominenceSaturationSeconds`.
    var prominence: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var dwellSeconds: TimeInterval { departure.timeIntervalSince(arrival) }
}

/// Per-hole track segmentation + stop detection (B5). All core logic is pure and
/// data-in/data-out so it's unit-testable without a database; `stops(forHole:in:)`
/// is the DB-backed convenience reconstruction will call.
enum TrackSegmenter {
    /// A dwell standing this long is maximally prominent (1.0).
    static let prominenceSaturationSeconds: TimeInterval = 60

    // MARK: - Per-hole windowing (pure)

    /// A little past the holed putt — the golfer lingers, then walks on. Keeps a
    /// hole's window covering its last stroke without bleeding far into the next.
    static let departureBufferSeconds: TimeInterval = 15

    /// The time window of the round's track belonging to `hole`: from when the
    /// golfer arrived (the previously-PLAYED hole's departure) up to when they
    /// left this hole — or `now` while it's still the active, unplayed hole. The
    /// first hole played starts at `roundStart`. Returns nil if degenerate.
    ///
    /// "Departure" is keyed off the hole's LAST STROKE time (+ a small buffer)
    /// when `lastShotTimes` supplies it, falling back to the hole's confirm time.
    /// Last-stroke time tracks actual PLAY order, so it stays correct even when
    /// confirm times invert play order — a back-nine start (18→1) or an
    /// out-of-order confirm (H8 confirmed after H9, as in the Emerald Isle round,
    /// where confirm-time windowing handed H9 a 21-minute window). Callers without
    /// shot times (older call sites, pure tests) get the confirm-time behavior.
    /// This is the B5/B6 segmentation foundation.
    static func timeWindow(forHole hole: Hole, roundStart: Date, holes: [Hole],
                           now: Date, lastShotTimes: [UUID: Date] = [:]) -> ClosedRange<Date>? {
        func departure(_ h: Hole) -> Date? {
            if let last = lastShotTimes[h.id] { return last.addingTimeInterval(departureBufferSeconds) }
            return h.confirmedAt
        }
        let end = departure(hole) ?? now
        let previousDeparture = holes
            .filter { $0.id != hole.id }
            .compactMap(departure)
            .filter { $0 < end }
            .max()
        let start = previousDeparture ?? roundStart
        guard end >= start else { return nil }
        return start...end
    }

    /// The trace points falling inside `window` (time-ordered). Empty if no window.
    static func points(_ all: [TracePoint], in window: ClosedRange<Date>?) -> [TracePoint] {
        guard let window else { return [] }
        return all.filter { window.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Stop detection (pure)

    /// Stay-point detection: walk the time-ordered track and, anchored at each
    /// point, extend a cluster while every later point stays within `radiusMeters`
    /// of the anchor. A cluster spanning ≥ `minDwellSeconds` is emitted as a stop
    /// (centroid location); otherwise the anchor slides forward one point. Returns
    /// stops in arrival order.
    static func detectStops(in points: [TracePoint],
                            config: StopDetectionConfig = .default) -> [TrackStop] {
        let pts = points.sorted { $0.timestamp < $1.timestamp }
        let n = pts.count
        guard n >= 2 else { return [] }
        var stops: [TrackStop] = []
        var i = 0
        while i < n {
            var j = i + 1
            while j < n, meters(pts[i], pts[j]) <= config.radiusMeters {
                j += 1
            }
            let cluster = pts[i..<j]
            let dwell = cluster.last!.timestamp.timeIntervalSince(cluster.first!.timestamp)
            if cluster.count >= 2, dwell >= config.minDwellSeconds {
                stops.append(makeStop(cluster))
                i = j // jump past the whole dwell
            } else {
                i += 1 // not a stop start; slide forward
            }
        }
        return stops
    }

    // MARK: - DB-backed convenience

    /// Candidate shot locations for `hole`: slice the round's persisted track to
    /// the hole's time window, then detect stops. Bounded by hole confirm times
    /// (always available, unlike tee anchors — Emerald Isle has none).
    static func stops(forHole hole: Hole, in round: Round,
                      config: StopDetectionConfig = .default, now: Date = Date()) throws -> [TrackStop] {
        let holes = try HoleRepository.holesForRound(round.id)
        let all = try TracePointRepository.pointsForRound(round.id)
        let lastShotTimes = try lastShotTimesByHole(holes)
        let window = timeWindow(forHole: hole, roundStart: round.startedAt, holes: holes,
                                now: now, lastShotTimes: lastShotTimes)
        return detectStops(in: points(all, in: window), config: config)
    }

    /// Latest stroke timestamp per hole — the play-order boundary that makes
    /// windowing robust to confirm inversions (see `timeWindow`).
    private static func lastShotTimesByHole(_ holes: [Hole]) throws -> [UUID: Date] {
        var out: [UUID: Date] = [:]
        for h in holes {
            if let last = try ShotRepository.shotsForHole(h.id).map(\.timestamp).max() {
                out[h.id] = last
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func meters(_ a: TracePoint, _ b: TracePoint) -> Double {
        Distance.meters(
            from: CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude),
            to: CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)
        )
    }

    private static func makeStop(_ cluster: ArraySlice<TracePoint>) -> TrackStop {
        let count = cluster.count
        let lat = cluster.reduce(0.0) { $0 + $1.latitude } / Double(count)
        let lng = cluster.reduce(0.0) { $0 + $1.longitude } / Double(count)
        let arrival = cluster.first!.timestamp
        let departure = cluster.last!.timestamp
        let dwell = departure.timeIntervalSince(arrival)
        return TrackStop(
            latitude: lat, longitude: lng, arrival: arrival, departure: departure,
            sampleCount: count, prominence: min(1.0, dwell / prominenceSaturationSeconds)
        )
    }
}
