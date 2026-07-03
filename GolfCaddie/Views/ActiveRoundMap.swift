import CoreLocation
import MapKit
import SwiftUI

/// Full-bleed satellite map used during an active round. Renders shot pins as
/// custom circular annotations (white background for prior shots, flag-orange
/// for the latest), connected by a dashed white polyline; the green anchor
/// gets a flag marker and a dashed you → green target line (B9).
struct ActiveRoundMap: View {
    let shots: [Shot]
    /// Bearing in degrees from tee → green for the current hole, or nil when
    /// the hole has no curated/captured anchors (map falls back to north up).
    let holeHeading: Double?
    /// Green anchor for the current hole; drawn as a flag marker and framed.
    let green: CLLocationCoordinate2D?
    /// Tee anchor for the current hole; framing only, no marker (B9).
    let tee: CLLocationCoordinate2D?
    /// "Auto-frame the hole" — true keeps the map fit to ball → green as you
    /// walk; a manual pan/zoom flips it off, and the recenter control flips it on.
    @Binding var followMode: Bool

    var body: some View {
        ActiveRoundMapKit(
            shots: shots,
            holeHeading: holeHeading,
            green: green,
            tee: tee,
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
    let tee: CLLocationCoordinate2D?
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
        coord.tee = tee
        coord.holeHeading = holeHeading
        coord.shotCoords = shots.compactMap { shot in
            guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        syncAnnotations(in: map)
        syncGreenAnnotation(in: map)
        syncPolyline(in: map)
        coord.syncTargetLine(map)

        // Re-frame ball → green when auto-frame is on AND something that changes
        // the framing changed (hole/green/tee/heading, or the shot set). Walking
        // is handled separately in didUpdate userLocation (throttled by distance).
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
        let t = tee.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let h = holeHeading.map { String(Int($0)) } ?? "-"
        return "\(g)|\(t)|\(h)|\(shots.count)"
    }

    /// Add/move/remove the single green-flag marker to track the `green` input.
    private func syncGreenAnnotation(in map: MKMapView) {
        let existing = map.annotations.compactMap { $0 as? GreenAnnotation }.first
        switch (existing, green) {
        case let (ann?, g?):
            if ann.coordinate.latitude != g.latitude || ann.coordinate.longitude != g.longitude {
                ann.coordinate = g
            }
        case let (nil, g?):
            map.addAnnotation(GreenAnnotation(coordinate: g))
        case let (ann?, nil):
            map.removeAnnotation(ann)
        case (nil, nil):
            break
        }
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
        // Remove existing — but only the shot trail; the you → green target
        // line is owned by syncTargetLine and must survive shot-set changes.
        let oldLines = map.overlays.compactMap { $0 as? MKPolyline }.filter { !($0 is TargetLinePolyline) }
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
        var tee: CLLocationCoordinate2D?
        var holeHeading: Double?
        var shotCoords: [CLLocationCoordinate2D] = []

        var lastFrameKey: String?
        var wasFollowing = false
        private var lastFrameUserCoord: CLLocationCoordinate2D?
        private var lastTargetLineUserCoord: CLLocationCoordinate2D?
        private var programmaticChange = false

        init(onFollowModeChange: @escaping (Bool) -> Void) {
            self.onFollowModeChange = onFollowModeChange
        }

        /// Fit the camera to tee → ball (user) → green (+ shots), green-up.
        func reframe(_ map: MKMapView, animated: Bool) {
            var coords = shotCoords
            if let green { coords.append(green) }
            if let tee { coords.append(tee) }
            let user = map.userLocation.location?.coordinate
            if let user, CLLocationCoordinate2DIsValid(user) { coords.append(user) }
            guard let camera = Self.cameraFitting(coords, heading: holeHeading ?? 0) else { return }
            lastFrameUserCoord = user
            programmaticChange = true
            map.setCamera(camera, animated: animated)
        }

        /// Rebuild the dashed you → green target line. Runs on hole/green
        /// changes (updateUIView) and as the user walks (didUpdate, gated to
        /// ≥12 m like the walking reframe so overlay churn stays bounded).
        /// Unlike the reframe this ignores follow mode — the line should track
        /// the player even on a manually panned map.
        func syncTargetLine(_ map: MKMapView, movementGated: Bool = false) {
            let user = map.userLocation.location?.coordinate
            guard let green, let user, CLLocationCoordinate2DIsValid(user) else {
                let old = map.overlays.compactMap { $0 as? TargetLinePolyline }
                if !old.isEmpty { map.removeOverlays(old) }
                lastTargetLineUserCoord = nil
                return
            }
            if movementGated, let last = lastTargetLineUserCoord {
                let moved = CLLocation(latitude: user.latitude, longitude: user.longitude)
                    .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
                guard moved >= 12 else { return }
            }
            let old = map.overlays.compactMap { $0 as? TargetLinePolyline }
            map.removeOverlays(old)
            let line = TargetLinePolyline(coordinates: [user, green], count: 2)
            map.addOverlay(line)
            lastTargetLineUserCoord = user
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

        // Keep the target line tracking the walk (regardless of follow mode),
        // and re-fit as the user walks (only while auto-framing) — both
        // throttled by distance.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            syncTargetLine(mapView, movementGated: true)
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

            if annotation is GreenAnnotation {
                let identifier = "GreenFlagView"
                let view: MKMarkerAnnotationView
                if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
                    view = dequeued
                    view.annotation = annotation
                } else {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                }
                view.glyphImage = UIImage(systemName: "flag.fill")
                // Flag orange #C24A2D — same as the latest-shot pin.
                view.markerTintColor = UIColor(red: 194 / 255.0, green: 74 / 255.0, blue: 45 / 255.0, alpha: 1.0)
                view.displayPriority = .required
                view.animatesWhenAdded = false
                view.isDraggable = false
                view.canShowCallout = false
                return view
            }

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
            // Target line first — it's an MKPolyline subclass, so the general
            // branch below would otherwise claim it.
            if let target = overlay as? TargetLinePolyline {
                let r = MKPolylineRenderer(polyline: target)
                r.strokeColor = UIColor.white.withAlphaComponent(0.45)
                r.lineWidth = 1.5
                r.lineDashPattern = [2, 5]
                return r
            }
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

// MARK: - Overlays & annotations

/// Marker subclass so the renderer can tell the you → green target line apart
/// from the shot-trail polyline (both are MKPolylines on the same map).
private final class TargetLinePolyline: MKPolyline {}

/// The green-flag marker at the hole's green anchor (B9). `dynamic` so a
/// coordinate move (local anchor recapture mid-round) animates in place
/// instead of needing remove/re-add.
private final class GreenAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

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
