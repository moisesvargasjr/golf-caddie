import CoreLocation
import MapKit
import SwiftUI

/// Satellite map for the previous-hole editor. Deliberately a SEPARATE
/// representable from `ActiveRoundMap` (the field-tested live-capture map):
/// no user tracking, explicit per-hole camera framing, and DRAGGABLE shot
/// pins. It only reports a drop upward via `onShotMoved` — persistence lives
/// in `HoleDetailView` (same "report up" discipline as `ActiveRoundMap`'s
/// follow-mode callback).
struct EditableHoleMap: View {
    /// Shots for the currently-displayed hole, ordered by sequence.
    let shots: [Shot]
    /// Drives reframing: the camera refits only when this changes.
    let holeID: UUID
    /// Called on drop with the shot and its new coordinate.
    let onShotMoved: (Shot, CLLocationCoordinate2D) -> Void

    var body: some View {
        EditableHoleMapKit(shots: shots, holeID: holeID, onShotMoved: onShotMoved)
    }
}

private struct EditableHoleMapKit: UIViewRepresentable {
    let shots: [Shot]
    let holeID: UUID
    let onShotMoved: (Shot, CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShotMoved: onShotMoved)
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
        syncAnnotations(in: map, coordinator: context.coordinator)

        // Reframe only when the hole changes and no drag is in progress
        // (re-setting the region mid-drag would fight the user's gesture).
        if context.coordinator.lastFramedHoleID != holeID,
           context.coordinator.draggingShotID == nil {
            let coords = shots.compactMap { shot -> CLLocationCoordinate2D? in
                guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            if let region = Self.regionFitting(coords) {
                map.setRegion(region, animated: true)
            }
            // No GPS shots → leave the existing region; HoleDetailView shows
            // a "no GPS shots to place" caption in that case.
            context.coordinator.lastFramedHoleID = holeID
        }
    }

    /// Bounding region of the hole's shots, padded, with a floor span so a
    /// single-shot hole isn't zoomed to street level (~0.0015° ≈ 165 m).
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

    private func syncAnnotations(in map: MKMapView, coordinator: Coordinator) {
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
                // Never churn the pin the user is actively dragging.
                if existing.shot.id == coordinator.draggingShotID { continue }
                if existing.shot.sequenceNumber != shot.sequenceNumber {
                    map.removeAnnotation(existing)
                    map.addAnnotation(EditableShotAnnotation(shot: shot, coordinate: coord))
                } else if existing.coordinate.latitude != lat
                    || existing.coordinate.longitude != lng {
                    // Coordinate changed (e.g. just persisted a drag): move
                    // the pin in place via KVO rather than remove/re-add.
                    existing.coordinate = coord
                }
            } else {
                map.addAnnotation(EditableShotAnnotation(shot: shot, coordinate: coord))
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onShotMoved: (Shot, CLLocationCoordinate2D) -> Void
        var draggingShotID: UUID?
        var lastFramedHoleID: UUID?

        init(onShotMoved: @escaping (Shot, CLLocationCoordinate2D) -> Void) {
            self.onShotMoved = onShotMoved
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let shotAnn = annotation as? EditableShotAnnotation else { return nil }
            let identifier = "EditableShotMarker"
            let view: MKMarkerAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView {
                view = dequeued
                view.annotation = annotation
            } else {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            view.glyphText = "\(shotAnn.shot.sequenceNumber)"
            view.markerTintColor = Self.markerColor(for: shotAnn.shot)
            view.canShowCallout = true
            // Tap-to-select then drag (the standard mitigation for the
            // drag-vs-pan gesture conflict on a marker).
            view.isDraggable = true
            return view
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            guard let ann = view.annotation as? EditableShotAnnotation else { return }
            switch newState {
            case .starting:
                draggingShotID = ann.shot.id
                view.dragState = .dragging
            case .ending:
                onShotMoved(ann.shot, ann.coordinate)
                draggingShotID = nil
                view.dragState = .none
            case .canceling:
                draggingShotID = nil
                view.dragState = .none
            default:
                break
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
