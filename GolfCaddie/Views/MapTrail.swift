import CoreLocation
import MapKit
import SwiftUI

/// Where every hole map's dotted walked trail comes from. One seam so the
/// trail follows Track B's watch-first source with a one-line change.
enum HoleTrailSource {
    // B38: switch to TracePointRepository.preferredTrail (watch-first trail).
    static func coordinates(roundID: UUID, since: Date, until: Date? = nil) -> [CLLocationCoordinate2D] {
        let points = (try? TracePointRepository.pointsForRound(roundID)) ?? []
        return points
            .filter { point in point.timestamp >= since && (until.map { point.timestamp <= $0 } ?? true) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The trail walked during one hole: from the previous confirmation (or
    /// the round start) to this hole's confirmation (or now).
    static func coordinates(forHoleID holeID: UUID) -> [CLLocationCoordinate2D] {
        guard let hole = try? HoleRepository.hole(byID: holeID),
              let holes = try? HoleRepository.holesForRound(hole.roundID) else { return [] }
        let end = hole.confirmedAt
        let start = holes.compactMap(\.confirmedAt)
            .filter { $0 < (end ?? .distantFuture) && $0 != end }
            .max()
            ?? (try? RoundRepository.allRounds())?.first { $0.id == hole.roundID }?.startedAt
            ?? .distantPast
        return downsampled(coordinates(roundID: hole.roundID, since: start, until: end))
    }

    static let maxPoints = 400

    static func downsampled(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let stride = max(1, coords.count / maxPoints)
        return coords.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
}

/// Walked GPS breadcrumbs, drawn the same dotted way on every map.
final class TrailPolyline: MKPolyline {}

enum MapTrailStyle {
    static let uiColor = UIColor.white.withAlphaComponent(0.85)
    static let lineWidth: CGFloat = 2.5
    static let dash: [CGFloat] = [0.5, 6]

    static func renderer(for trail: TrailPolyline) -> MKPolylineRenderer {
        let r = MKPolylineRenderer(polyline: trail)
        r.strokeColor = uiColor
        r.lineWidth = lineWidth
        r.lineCap = .round
        r.lineDashPattern = dash.map { NSNumber(value: Double($0)) }
        return r
    }

    /// SwiftUI `Map` equivalent (`MapPolyline(...).stroke(color, style:)`).
    static let color = Color.white.opacity(0.85)
    static let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)

    /// Replace the trail overlay on an MKMapView when `coords` changed.
    static func sync(_ coords: [CLLocationCoordinate2D], in map: MKMapView, lastKey: inout String?) {
        let last = coords.last.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let key = "\(coords.count)|\(last)"
        guard lastKey != key else { return }
        lastKey = key
        map.removeOverlays(map.overlays.filter { $0 is TrailPolyline })
        guard coords.count >= 2 else { return }
        map.addOverlay(TrailPolyline(coordinates: coords, count: coords.count))
    }
}
