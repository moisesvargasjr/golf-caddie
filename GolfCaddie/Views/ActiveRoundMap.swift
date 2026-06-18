import CoreLocation
import MapKit
import SwiftUI

/// Full-bleed satellite map used during an active round. Renders shot pins as
/// custom circular annotations (white background for prior shots, flag-orange
/// for the latest), connected by a dashed white polyline.
struct ActiveRoundMap: View {
    let shots: [Shot]
    /// Bearing in degrees from tee → green for the current hole, or nil when
    /// the hole has no curated/captured anchors (map falls back to north up).
    let holeHeading: Double?
    /// Green anchor for the current hole; the map frames ball → green around it.
    let green: CLLocationCoordinate2D?
    /// "Auto-frame the hole" — true keeps the map fit to ball → green as you
    /// walk; a manual pan/zoom flips it off, and the recenter control flips it on.
    @Binding var followMode: Bool

    var body: some View {
        ActiveRoundMapKit(
            shots: shots,
            holeHeading: holeHeading,
            green: green,
            isFollowing: followMode,
            onFollowModeChange: { newValue in
                if followMode != newValue {
                    followMode = newValue
                }
            }
        )
    }
}

private struct ActiveRoundMapKit: UIViewRepresentable {
    let shots: [Shot]
    let holeHeading: Double?
    let green: CLLocationCoordinate2D?
    let isFollowing: Bool
    let onFollowModeChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFollowModeChange: onFollowModeChange)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKImageryMapConfiguration()
        map.showsUserLocation = true
        map.showsCompass = false  // design has its own corner stamp
        map.showsScale = false
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.onFollowModeChange = onFollowModeChange
        coord.green = green
        coord.holeHeading = holeHeading
        coord.shotCoords = shots.compactMap { shot in
            guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        syncAnnotations(in: map)
        syncPolyline(in: map)

        // Re-frame ball → green when auto-frame is on AND something that changes
        // the framing changed (hole/green/heading, or the shot set). Walking is
        // handled separately in didUpdate userLocation (throttled by distance).
        let key = frameKey()
        if isFollowing, coord.lastFrameKey != key {
            coord.lastFrameKey = key
            coord.reframe(map, animated: true)
        }
        // Returning to auto-frame after a manual pan: force a reframe.
        if isFollowing, !coord.wasFollowing {
            coord.reframe(map, animated: true)
        }
        coord.wasFollowing = isFollowing
    }

    /// Identity of the current framing inputs; a change triggers a re-fit.
    private func frameKey() -> String {
        let g = green.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let h = holeHeading.map { String(Int($0)) } ?? "-"
        return "\(g)|\(h)|\(shots.count)"
    }

    private func syncAnnotations(in map: MKMapView) {
        let existing = map.annotations.compactMap { $0 as? ShotAnnotation }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.shot.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, $0) })

        // Remove dropped shots.
        for (id, ann) in existingByID where currentByID[id] == nil {
            map.removeAnnotation(ann)
        }

        let total = shots.count
        for (idx, shot) in shots.enumerated() {
            guard let lat = shot.latitude, let lng = shot.longitude else { continue }
            let isLatest = idx == total - 1
            if let existing = existingByID[shot.id] {
                let needsReplace = existing.shot.sequenceNumber != shot.sequenceNumber
                    || existing.isLatest != isLatest
                if needsReplace {
                    map.removeAnnotation(existing)
                    let updated = ShotAnnotation(shot: shot, isLatest: isLatest)
                    updated.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    map.addAnnotation(updated)
                }
            } else {
                let ann = ShotAnnotation(shot: shot, isLatest: isLatest)
                ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                map.addAnnotation(ann)
            }
        }
    }

    /// Rebuilds the dashed connecting polyline whenever the shot set changes.
    /// One overlay is cheaper to fully replace than to mutate.
    private func syncPolyline(in map: MKMapView) {
        // Remove existing.
        let oldLines = map.overlays.compactMap { $0 as? MKPolyline }
        map.removeOverlays(oldLines)

        let coords = shots.compactMap { shot -> CLLocationCoordinate2D? in
            guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard coords.count >= 2 else { return }
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(polyline)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onFollowModeChange: (Bool) -> Void

        // Framing inputs, kept fresh by updateUIView so the location-driven
        // reframe (didUpdate) can read them.
        var green: CLLocationCoordinate2D?
        var holeHeading: Double?
        var shotCoords: [CLLocationCoordinate2D] = []

        var lastFrameKey: String?
        var wasFollowing = false
        private var lastFrameUserCoord: CLLocationCoordinate2D?
        private var programmaticChange = false

        init(onFollowModeChange: @escaping (Bool) -> Void) {
            self.onFollowModeChange = onFollowModeChange
        }

        /// Fit the camera to ball (user) → green (+ shots), oriented green-up.
        func reframe(_ map: MKMapView, animated: Bool) {
            var coords = shotCoords
            if let green { coords.append(green) }
            let user = map.userLocation.location?.coordinate
            if let user, CLLocationCoordinate2DIsValid(user) { coords.append(user) }
            guard let camera = Self.cameraFitting(coords, heading: holeHeading ?? 0) else { return }
            lastFrameUserCoord = user
            programmaticChange = true
            map.setCamera(camera, animated: animated)
        }

        /// Camera that frames `coords` with a tight margin, green-up. Distance is
        /// driven by the span of ball → green, so it zooms in as you walk up; a
        /// floor keeps a single point from zooming to the street.
        static func cameraFitting(_ coords: [CLLocationCoordinate2D], heading: CLLocationDirection) -> MKMapCamera? {
            guard !coords.isEmpty else { return nil }
            let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
            let diagonal = CLLocation(latitude: maxLat, longitude: minLng)
                .distance(from: CLLocation(latitude: minLat, longitude: maxLng))
            let distance = max(diagonal * 1.45, 160)
            return MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: heading)
        }

        // Re-fit as the user walks (only while auto-framing, throttled by distance).
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard wasFollowing, let here = userLocation.location else { return }
            if let last = lastFrameUserCoord {
                let moved = here.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
                guard moved >= 12 else { return }
            }
            reframe(mapView, animated: true)
        }

        // A manual pan/zoom while auto-framing turns auto-frame off.
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if programmaticChange { return }
            let userGesture = (mapView.subviews.first?.gestureRecognizers ?? []).contains {
                $0.state == .began || $0.state == .changed
            }
            if userGesture { onFollowModeChange(false) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            programmaticChange = false
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let shotAnn = annotation as? ShotAnnotation else { return nil }

            let identifier = "ShotPinView"
            let view: ShotPinView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? ShotPinView {
                view = dequeued
                view.annotation = annotation
            } else {
                view = ShotPinView(annotation: annotation, reuseIdentifier: identifier)
            }
            view.configure(shot: shotAnn.shot, isLatest: shotAnn.isLatest)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.white.withAlphaComponent(0.7)
                r.lineWidth = 1.5
                r.lineDashPattern = [3, 3]
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Annotation

private final class ShotAnnotation: NSObject, MKAnnotation {
    var shot: Shot
    var coordinate: CLLocationCoordinate2D
    let isLatest: Bool

    init(shot: Shot, isLatest: Bool) {
        self.shot = shot
        self.coordinate = CLLocationCoordinate2D(
            latitude: shot.latitude ?? 0,
            longitude: shot.longitude ?? 0
        )
        self.isLatest = isLatest
        super.init()
    }
}

/// Circular pin view: white-paper background with a 2pt inner ring + drop
/// shadow for prior shots; flag-orange `#C24A2D` for the latest shot. Number
/// label centered in SF Pro 700.
private final class ShotPinView: MKAnnotationView {
    private let label = UILabel()
    private let dot = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.topAnchor.constraint(equalTo: topAnchor),
            dot.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        dot.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
        ])

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(shot: Shot, isLatest: Bool) {
        let size: CGFloat = isLatest ? 32 : 28
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        dot.layer.cornerRadius = size / 2
        dot.layer.borderWidth = 2
        dot.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor

        if isLatest {
            dot.backgroundColor = UIColor(red: 194 / 255.0, green: 74 / 255.0, blue: 45 / 255.0, alpha: 1.0)
            label.textColor = .white
        } else {
            dot.backgroundColor = UIColor.white
            label.textColor = UIColor.black
        }

        label.font = .systemFont(ofSize: size * 0.46, weight: .heavy)
        label.text = "\(shot.sequenceNumber)"
    }
}
