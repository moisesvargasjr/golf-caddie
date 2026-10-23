import CoreLocation
import Foundation

/// B38: the one "preferred trail" every consumer reads. Over any time span the
/// WATCH covered, the watch's points win; the phone's points fill only where the
/// watch has none. (A phone left in the cart records a perfectly confident trail
/// of the cart.) Pure.
enum TrailMerge {
    /// Consecutive watch points up to this far apart count as one continuous
    /// span of watch coverage. The watch records about every 2 s, so a bigger
    /// gap means it really wasn't recording and the phone should fill in.
    static let maxWatchGapSeconds: TimeInterval = 15

    static func preferred(_ points: [TracePoint]) -> [TracePoint] {
        let watch = points.filter(\.isWatch).sorted { $0.timestamp < $1.timestamp }
        guard !watch.isEmpty else { return points.sorted { $0.timestamp < $1.timestamp } }
        let spans = coverage(of: watch)
        let phone = points.filter { !$0.isWatch }.sorted { $0.timestamp < $1.timestamp }
        return (watch + uncovered(phone, by: spans)).sorted { $0.timestamp < $1.timestamp }
    }

    private static func coverage(of watch: [TracePoint]) -> [ClosedRange<Date>] {
        var spans: [ClosedRange<Date>] = []
        var start = watch[0].timestamp
        var end = start
        for point in watch.dropFirst() {
            if point.timestamp.timeIntervalSince(end) <= maxWatchGapSeconds {
                end = point.timestamp
            } else {
                spans.append(start...end)
                start = point.timestamp
                end = start
            }
        }
        spans.append(start...end)
        return spans
    }

    /// Phone points outside every span. Both inputs are time-sorted: one sweep.
    private static func uncovered(_ phone: [TracePoint], by spans: [ClosedRange<Date>]) -> [TracePoint] {
        var result: [TracePoint] = []
        var i = 0
        for point in phone {
            while i < spans.count, spans[i].upperBound < point.timestamp { i += 1 }
            if i < spans.count, spans[i].contains(point.timestamp) { continue }
            result.append(point)
        }
        return result
    }
}

/// Pins snap to the golfer's actual path (B37-lite): within `radiusMeters` of a
/// trail point, a tapped pin lands on that point; further away it stays put.
enum TrailSnap {
    static let radiusMeters: Double = 15

    static func snap(_ tap: CLLocationCoordinate2D, to trail: [TracePoint])
        -> (coordinate: CLLocationCoordinate2D, snapped: Bool) {
        var best: (point: TracePoint, meters: Double)?
        for point in trail {
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
    /// enough. `track` = snapped to the golfer's path, `manual` = placed freehand.
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
        updated.locationSource = result.snapped ? .track : .manual
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
