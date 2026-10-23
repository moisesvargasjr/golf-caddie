import CoreLocation
import Foundation

/// B38: the one "preferred trail" every consumer reads. Over any time span the
/// WATCH covered, the watch's points win; the phone's points fill only where the
/// watch has none, and then only where they could plausibly be the same walk.
/// (A phone left in the cart records a perfectly confident trail of the cart.)
/// Pure.
enum TrailMerge {
    /// Consecutive watch points up to this far apart count as one continuous
    /// span of watch coverage. The watch records about every 2 s, so a bigger
    /// gap means it really wasn't recording and the phone should fill in.
    static let maxWatchGapSeconds: TimeInterval = 15
    /// A watch gap longer than this is filled from the phone whatever it says (the
    /// watch was off or out of GPS for minutes).
    static let longGapSeconds: TimeInterval = 120
    /// Walking-speed bound for a phone point to count as "near the watch's path":
    /// within `walkingMetersPerSecond * dt + slackMeters` of the watch point on
    /// each side of the gap.
    static let walkingMetersPerSecond: Double = 2.5
    static let slackMeters: Double = 30

    private struct Span {
        var first: TracePoint
        var last: TracePoint
    }

    static func preferred(_ points: [TracePoint]) -> [TracePoint] {
        let watch = points.filter(\.isWatch).sorted { $0.timestamp < $1.timestamp }
        guard !watch.isEmpty else { return points.sorted { $0.timestamp < $1.timestamp } }
        let spans = coverage(of: watch)
        let phone = points.filter { !$0.isWatch }.sorted { $0.timestamp < $1.timestamp }
        return (watch + usable(phone, around: spans)).sorted { $0.timestamp < $1.timestamp }
    }

    private static func coverage(of watch: [TracePoint]) -> [Span] {
        var spans: [Span] = []
        var current = Span(first: watch[0], last: watch[0])
        for point in watch.dropFirst() {
            if point.timestamp.timeIntervalSince(current.last.timestamp) <= maxWatchGapSeconds {
                current.last = point
            } else {
                spans.append(current)
                current = Span(first: point, last: point)
            }
        }
        spans.append(current)
        return spans
    }

    /// Phone points to keep: none inside a watch span; in a gap BETWEEN spans only
    /// the plausible ones (or all, for a long gap); before the first / after the
    /// last span, all (the watch had not started / had stopped). Both inputs are
    /// time-sorted: one sweep.
    private static func usable(_ phone: [TracePoint], around spans: [Span]) -> [TracePoint] {
        var result: [TracePoint] = []
        var i = 0
        for point in phone {
            while i < spans.count, spans[i].last.timestamp < point.timestamp { i += 1 }
            if i < spans.count, spans[i].first.timestamp <= point.timestamp { continue } // inside a span
            if i > 0, i < spans.count,
               !plausible(point, between: spans[i - 1].last, and: spans[i].first) { continue }
            result.append(point)
        }
        return result
    }

    private static func plausible(_ point: TracePoint, between before: TracePoint, and after: TracePoint) -> Bool {
        if after.timestamp.timeIntervalSince(before.timestamp) > longGapSeconds { return true }
        func near(_ other: TracePoint) -> Bool {
            let dt = abs(point.timestamp.timeIntervalSince(other.timestamp))
            let meters = Distance.meters(
                from: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                to: CLLocationCoordinate2D(latitude: other.latitude, longitude: other.longitude))
            return meters <= walkingMetersPerSecond * dt + slackMeters
        }
        return near(before) && near(after)
    }
}

/// Pins snap to the golfer's actual path (B37-lite): within `radiusMeters` of a
/// trail point, a tapped pin lands on that point; further away it stays put.
/// Snapping only refines WHERE the pin is; it does not change who placed it.
enum TrailSnap {
    static let radiusMeters: Double = 8

    /// Snaps only to WATCH points when the trail has any (a phone point may be the
    /// cart); the phone trail is the fallback only for a hole with no watch data.
    static func snap(_ tap: CLLocationCoordinate2D, to trail: [TracePoint])
        -> (coordinate: CLLocationCoordinate2D, snapped: Bool) {
        let watch = trail.filter(\.isWatch)
        var best: (point: TracePoint, meters: Double)?
        for point in watch.isEmpty ? trail : watch {
            let meters = Distance.meters(
                from: tap, to: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            if meters <= radiusMeters, meters < (best?.meters ?? .infinity) { best = (point, meters) }
        }
        guard let best else { return (tap, false) }
        return (CLLocationCoordinate2D(latitude: best.point.latitude, longitude: best.point.longitude), true)
    }
}

/// Hand placement of a shot's pin (hole review, hole detail, missing-shot sheet).
enum ShotPlacement {
    /// `shot` moved to `tap`, snapped to the hole's preferred trail when close
    /// enough. Always `manual`: this is a user decision either way, and tagging a
    /// snapped pin `track` would let the late-trail re-lay mistake it for a system
    /// placement and move the user's correction.
    static func pinned(_ shot: Shot, at tap: CLLocationCoordinate2D) -> Shot {
        let trail = trail(forHole: shot.holeID)
        return pinned(shot, at: tap, trail: trail)
    }

    static func pinned(_ shot: Shot, at tap: CLLocationCoordinate2D, trail: [TracePoint]) -> Shot {
        let result = TrailSnap.snap(tap, to: trail)
        var updated = shot
        updated.latitude = result.coordinate.latitude
        updated.longitude = result.coordinate.longitude
        updated.hadGPS = true
        updated.gpsAccuracy = nil
        updated.locationSource = .manual
        updated.locationDisagreementMeters = nil
        return updated
    }

    /// The preferred trail inside the hole's time window; empty when it can't be
    /// worked out (never blocks placing a pin).
    static func trail(forHole holeID: UUID) -> [TracePoint] {
        guard let hole = try? HoleRepository.hole(byID: holeID),
              let round = (try? RoundRepository.allRounds())?.first(where: { $0.id == hole.roundID }) else { return [] }
        return (try? TrackSegmenter.trail(forHole: hole, in: round)) ?? []
    }
}
