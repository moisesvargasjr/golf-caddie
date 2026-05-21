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
    @Binding var followMode: Bool

    var body: some View {
        ActiveRoundMapKit(
            shots: shots,
            holeHeading: holeHeading,
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
        map.userTrackingMode = .follow
        map.showsCompass = false  // design has its own corner stamp
        map.showsScale = false
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onFollowModeChange = onFollowModeChange

        if isFollowing, map.userTrackingMode != .follow {
            map.setUserTrackingMode(.follow, animated: true)
        }

        applyHoleHeading(in: map, context: context)
        syncAnnotations(in: map)
        syncPolyline(in: map)
    }

    /// Rotate the camera so the hitting direction (tee → green) points "up".
    /// `userTrackingMode = .follow` keeps the user centered but doesn't lock
    /// heading; we set the camera heading whenever it changes, and skip the
    /// nudge when nothing's different to avoid camera jitter.
    private func applyHoleHeading(in map: MKMapView, context: Context) {
        guard let target = holeHeading else { return }
        if let last = context.coordinator.lastAppliedHeading,
           abs(last - target) < 0.5 { return }
        let camera = map.camera.copy() as! MKMapCamera
        camera.heading = target
        map.setCamera(camera, animated: true)
        context.coordinator.lastAppliedHeading = target
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
        /// Last heading we pushed to the camera, so we don't re-issue
        /// `setCamera` every SwiftUI update tick.
        var lastAppliedHeading: Double?

        init(onFollowModeChange: @escaping (Bool) -> Void) {
            self.onFollowModeChange = onFollowModeChange
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            let isFollowing = mode == .follow || mode == .followWithHeading
            onFollowModeChange(isFollowing)
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
