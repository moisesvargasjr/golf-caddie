import CoreLocation
import Foundation

/// Optional tee/green coordinates for a hole. They extend the shot path at both
/// ends so a shot held near the tee (or the green) orders correctly even when
/// the logged shots don't reach that far.
struct HolePathAnchors {
    var tee: CLLocationCoordinate2D?
    var green: CLLocationCoordinate2D?

    static let none = HolePathAnchors(tee: nil, green: nil)

    /// Local capture wins over curated, the same as live yardage.
    static func resolve(courseId: String?, holeNumber: Int) -> HolePathAnchors {
        HolePathAnchors(
            tee: GlassesStateMapper.teeCoordinate(courseId: courseId, holeNumber: holeNumber),
            green: GlassesStateMapper.greenCoordinate(courseId: courseId, holeNumber: holeNumber))
    }
}

/// Where a shot held onto the map belongs in the hole's sequence.
///
/// **Rule: nearest segment along the existing shot sequence.** The located
/// shots, in sequence order, form the path the golfer played (each shot sits
/// where it was hit from). The new point joins the slot whose piece of that
/// path it is closest to:
/// - slot k (between located shots k and k+1): distance to that segment;
/// - before the first located shot: distance to tee→first when a tee anchor is
///   known, else the perpendicular distance to the path extended backwards
///   (only when the point lies behind the first shot);
/// - after the last located shot: last→green with a green anchor, else the
///   path extended forwards (only beyond the last shot).
///
/// Chosen over projecting onto tee→green because it needs no course data, and
/// it follows doglegs. Ties (within `tieToleranceMeters`) go to the LATER slot:
/// a point dropped exactly on shot k is numbered after it, so earlier shots
/// keep their numbers. Unlocated shots don't shape the path; the new shot goes
/// immediately after the located shot before it (or immediately before the
/// first located shot). With no located shots at all it's appended.
enum ShotInsertOrdering {
    static let tieToleranceMeters = 0.5

    /// The sequence number the new shot takes (existing shots at or after it
    /// shift up — see `ShotRepository.insertShot(_:at:)`).
    static func position(for point: CLLocationCoordinate2D, among shots: [Shot],
                         anchors: HolePathAnchors = .none) -> Int {
        let ordered = shots.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let located: [(seq: Int, coord: CLLocationCoordinate2D)] = ordered.compactMap { shot in
            guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
            return (shot.sequenceNumber, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        guard let first = located.first else { return (ordered.last?.sequenceNumber ?? 0) + 1 }
        let slot = bestSlot(for: point, path: located.map(\.coord), anchors: anchors)
        return slot == 0 ? first.seq : located[slot - 1].seq + 1
    }

    /// A timestamp that keeps the hole time-ordered: midway between the
    /// neighbours, just before the next shot, or just after the previous one
    /// (`now` when given and later — the live hole).
    static func timestamp(forPosition position: Int, among shots: [Shot], now: Date?) -> Date {
        let ordered = shots.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let previous = ordered.last { $0.sequenceNumber < position }
        let next = ordered.first { $0.sequenceNumber >= position }
        switch (previous, next) {
        case let (p?, n?):
            return Date(timeIntervalSince1970: (p.timestamp.timeIntervalSince1970 + n.timestamp.timeIntervalSince1970) / 2)
        case let (nil, n?):
            return n.timestamp.addingTimeInterval(-1)
        case let (p?, nil):
            let after = p.timestamp.addingTimeInterval(1)
            return now.map { max($0, after) } ?? after
        case (nil, nil):
            return now ?? Date()
        }
    }

    /// Index 0…n of the slot the point joins (n = located shot count).
    static func bestSlot(for point: CLLocationCoordinate2D, path: [CLLocationCoordinate2D],
                         anchors: HolePathAnchors) -> Int {
        let p = Planar.zero
        let pts = path.map { Planar($0, origin: point) }
        let n = pts.count
        var costs = Array(repeating: Double.infinity, count: n + 1)
        for k in stride(from: 1, to: n, by: 1) {
            costs[k] = p.distance(toSegment: pts[k - 1], pts[k])
        }
        if let tee = anchors.tee {
            costs[0] = p.distance(toSegment: Planar(tee, origin: point), pts[0])
        } else if n >= 2 {
            costs[0] = p.distance(toRayFrom: pts[0], awayFrom: pts[1])
        }
        if let green = anchors.green {
            costs[n] = p.distance(toSegment: pts[n - 1], Planar(green, origin: point))
        } else if n >= 2 {
            costs[n] = p.distance(toRayFrom: pts[n - 1], awayFrom: pts[n - 2])
        } else {
            costs[n] = p.distance(to: pts[0])
        }
        let best = costs.min() ?? .infinity
        return costs.lastIndex { $0 <= best + tieToleranceMeters } ?? n
    }
}

/// Local east/north metres around an origin — plenty for one golf hole.
private struct Planar {
    let x: Double
    let y: Double

    static let zero = Planar(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ c: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) {
        let metersPerDegreeLat = 110_540.0
        let metersPerDegreeLng = 111_320.0 * cos(origin.latitude * .pi / 180)
        self.init(x: (c.longitude - origin.longitude) * metersPerDegreeLng,
                  y: (c.latitude - origin.latitude) * metersPerDegreeLat)
    }

    func distance(to o: Planar) -> Double { hypot(x - o.x, y - o.y) }

    /// Distance to segment a→b (clamped projection).
    func distance(toSegment a: Planar, _ b: Planar) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2))
        return distance(to: Planar(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Perpendicular distance to the ray that starts at `a` and points away
    /// from `b`; infinite when the point isn't past `a` along that ray.
    func distance(toRayFrom a: Planar, awayFrom b: Planar) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return .infinity }
        let t = ((x - a.x) * dx + (y - a.y) * dy) / len2
        guard t > 0 else { return .infinity }
        return distance(to: Planar(x: a.x + t * dx, y: a.y + t * dy))
    }
}
