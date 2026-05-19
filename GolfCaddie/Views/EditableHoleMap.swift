import CoreLocation
import MapKit
import SwiftUI

/// Satellite map for the previous-hole editor. Deliberately a SEPARATE
/// representable from `ActiveRoundMap` (the field-tested live-capture map):
/// no user tracking, explicit per-hole camera framing, and DRAGGABLE pins —
/// both shot pins and (in anchor mode) the Tee/Green anchors. It only reports
/// drops upward; persistence lives in `HoleDetailView`.
struct EditableHoleMap: View {
    /// Shots for the currently-displayed hole, ordered by sequence.
    let shots: [Shot]
    /// Drives reframing: the camera refits when the hole — or anchor
    /// presence — changes.
    let holeID: UUID
    /// Called on drop with the shot and its new coordinate.
    let onShotMoved: (Shot, CLLocationCoordinate2D) -> Void
    /// Tee/green anchors to show as draggable pins (nil = don't show that
    /// pin). Set only in anchor-capture mode.
    var tee: GeoPoint? = nil
    var green: GeoPoint? = nil
    /// Called on anchor drop. nil = anchor capture disabled.
    var onAnchorMoved: ((LocalAnchorRepository.AnchorKind, CLLocationCoordinate2D) -> Void)? = nil

    var body: some View {
        EditableHoleMapKit(
            shots: shots,
            holeID: holeID,
            onShotMoved: onShotMoved,
            tee: tee,
            green: green,
            onAnchorMoved: onAnchorMoved
        )
    }
}

private struct EditableHoleMapKit: UIViewRepresentable {
    let shots: [Shot]
    let holeID: UUID
    let onShotMoved: (Shot, CLLocationCoordinate2D) -> Void
    let tee: GeoPoint?
    let green: GeoPoint?
    let onAnchorMoved: ((LocalAnchorRepository.AnchorKind, CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onShotMoved: onShotMoved, onAnchorMoved: onAnchorMoved)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKImageryMapConfiguration()
        map.showsUserLocation = false
        map.showsCompass = true
        map.showsScale = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onShotMoved = onShotMoved
        context.coordinator.onAnchorMoved = onAnchorMoved
        syncShots(in: map, coordinator: context.coordinator)
        syncAnchors(in: map, coordinator: context.coordinator)

        // Reframe when the hole changes OR anchors first appear/disappear
        // (entering anchor mode should pull tee/green into view). Never
        // mid-drag — that would fight the gesture.
        let key = "\(holeID.uuidString)|\(tee != nil)|\(green != nil)"
        if context.coordinator.lastFramedKey != key,
           context.coordinator.draggingID == nil {
            var coords = shots.compactMap { shot -> CLLocationCoordinate2D? in
                guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            if let tee { coords.append(CLLocationCoordinate2D(latitude: tee.lat, longitude: tee.lng)) }
            if let green {
                coords.append(CLLocationCoordinate2D(latitude: green.lat, longitude: green.lng))
            }
            if let region = Self.regionFitting(coords) {
                map.setRegion(region, animated: true)
            }
            context.coordinator.lastFramedKey = key
        }
    }

    /// Bounding region of the supplied coords, padded, with a floor span so a
    /// single point isn't zoomed to street level (~0.0015° ≈ 165 m).
    private static func regionFitting(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.0015),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.0015)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func syncShots(in map: MKMapView, coordinator: Coordinator) {
        let existing = map.annotations.compactMap { $0 as? EditableShotAnnotation }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.shot.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, $0) })

        for (id, ann) in existingByID where currentByID[id] == nil {
            map.removeAnnotation(ann)
        }

        for shot in shots {
            guard let lat = shot.latitude, let lng = shot.longitude else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            if let existing = existingByID[shot.id] {
                if existing.shot.id.uuidString == coordinator.draggingID { continue }
                if existing.shot.sequenceNumber != shot.sequenceNumber {
                    map.removeAnnotation(existing)
                    map.addAnnotation(EditableShotAnnotation(shot: shot, coordinate: coord))
                } else if existing.coordinate.latitude != lat
                    || existing.coordinate.longitude != lng {
                    existing.coordinate = coord
                }
            } else {
                map.addAnnotation(EditableShotAnnotation(shot: shot, coordinate: coord))
            }
        }
    }

    private func syncAnchors(in map: MKMapView, coordinator: Coordinator) {
        let existing = map.annotations.compactMap { $0 as? AnchorAnnotation }
        func reconcile(_ kind: LocalAnchorRepository.AnchorKind, _ point: GeoPoint?) {
            let current = existing.first { $0.kind == kind }
            // Don't churn the anchor the user is dragging.
            if coordinator.draggingID == kind.dragToken { return }
            guard let point else {
                if let current { map.removeAnnotation(current) }
                return
            }
            let coord = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
            if let current {
                if current.coordinate.latitude != point.lat
                    || current.coordinate.longitude != point.lng {
                    current.coordinate = coord
                }
            } else {
                map.addAnnotation(AnchorAnnotation(kind: kind, coordinate: coord))
            }
        }
        reconcile(.tee, tee)
        reconcile(.green, green)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onShotMoved: (Shot, CLLocationCoordinate2D) -> Void
        var onAnchorMoved: ((LocalAnchorRepository.AnchorKind, CLLocationCoordinate2D) -> Void)?
        /// Stable token of whatever pin is mid-drag (shot UUID string or
        /// `tee`/`green`), so sync never churns it.
        var draggingID: String?
        var lastFramedKey: String?

        init(
            onShotMoved: @escaping (Shot, CLLocationCoordinate2D) -> Void,
            onAnchorMoved: ((LocalAnchorRepository.AnchorKind, CLLocationCoordinate2D) -> Void)?
        ) {
            self.onShotMoved = onShotMoved
            self.onAnchorMoved = onAnchorMoved
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let shotAnn = annotation as? EditableShotAnnotation {
                let view = Self.marker(mapView, annotation, "EditableShotMarker")
                view.glyphText = "\(shotAnn.shot.sequenceNumber)"
                view.markerTintColor = Self.markerColor(for: shotAnn.shot)
                view.canShowCallout = true
                view.isDraggable = true
                return view
            }
            if let anchorAnn = annotation as? AnchorAnnotation {
                let view = Self.marker(mapView, annotation, "AnchorMarker")
                view.glyphText = anchorAnn.kind == .tee ? "T" : "G"
                view.markerTintColor = anchorAnn.kind == .tee ? .systemPurple : .systemTeal
                view.canShowCallout = true
                view.isDraggable = true
                return view
            }
            return nil
        }

        private static func marker(
            _ mapView: MKMapView,
            _ annotation: MKAnnotation,
            _ id: String
        ) -> MKMarkerAnnotationView {
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                as? MKMarkerAnnotationView {
                dequeued.annotation = annotation
                return dequeued
            }
            return MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            if let ann = view.annotation as? EditableShotAnnotation {
                switch newState {
                case .starting:
                    draggingID = ann.shot.id.uuidString
                    view.dragState = .dragging
                case .ending:
                    onShotMoved(ann.shot, ann.coordinate)
                    draggingID = nil
                    view.dragState = .none
                case .canceling:
                    draggingID = nil
                    view.dragState = .none
                default:
                    break
                }
            } else if let ann = view.annotation as? AnchorAnnotation {
                switch newState {
                case .starting:
                    draggingID = ann.kind.dragToken
                    view.dragState = .dragging
                case .ending:
                    onAnchorMoved?(ann.kind, ann.coordinate)
                    draggingID = nil
                    view.dragState = .none
                case .canceling:
                    draggingID = nil
                    view.dragState = .none
                default:
                    break
                }
            }
        }

        private static func markerColor(for shot: Shot) -> UIColor {
            switch shot.source {
            case .button: return .systemOrange
            case .actionButton: return .systemBlue
            case .manual: return .systemGray
            case .glasses: return .systemGreen
            }
        }
    }
}

private extension LocalAnchorRepository.AnchorKind {
    var dragToken: String { self == .tee ? "tee" : "green" }
}

/// KVO-compliant (`@objc dynamic coordinate`) so MapKit's drag machinery can
/// update the position during a drag.
private final class EditableShotAnnotation: NSObject, MKAnnotation {
    let shot: Shot
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(shot: Shot, coordinate: CLLocationCoordinate2D) {
        self.shot = shot
        self.coordinate = coordinate
        self.title = "Shot \(shot.sequenceNumber)"
        super.init()
    }
}

private final class AnchorAnnotation: NSObject, MKAnnotation {
    let kind: LocalAnchorRepository.AnchorKind
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(kind: LocalAnchorRepository.AnchorKind, coordinate: CLLocationCoordinate2D) {
        self.kind = kind
        self.coordinate = coordinate
        self.title = kind == .tee ? "Tee" : "Green"
        super.init()
    }
}
