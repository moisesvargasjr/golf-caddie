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

    /// The time window of the round's track belonging to `hole`: from when the
    /// golfer arrived (the previously-PLAYED hole's confirm) up to this hole's own
    /// confirm time — or `now` while it's still the active, unconfirmed hole. The
    /// first hole played starts at `roundStart`. Returns nil if the bounds are
    /// degenerate.
    ///
    /// "Previously played" is keyed off confirm time, not hole number: the latest
    /// confirm strictly before this hole's own confirm. That stays correct when
    /// play order ≠ hole order — a back-nine start (18→1) or an out-of-order
    /// confirm (H8 confirmed after H9) — which the old holeNumber-based bound got
    /// wrong (it would borrow a later-played hole's confirm and yield an empty or
    /// garbled window). This is the B5 segmentation fix B6 depends on.
    static func timeWindow(forHole hole: Hole, roundStart: Date, holes: [Hole],
                           now: Date) -> ClosedRange<Date>? {
        let end = hole.confirmedAt ?? now
        let previousConfirm = holes
            .filter { $0.id != hole.id }
            .compactMap(\.confirmedAt)
            .filter { $0 < end }
            .max()
        let start = previousConfirm ?? roundStart
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
        let window = timeWindow(forHole: hole, roundStart: round.startedAt, holes: holes, now: now)
        return detectStops(in: points(all, in: window), config: config)
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
