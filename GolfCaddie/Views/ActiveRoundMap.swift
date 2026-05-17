import CoreLocation
import MapKit
import SwiftUI

struct ActiveRoundMap: View {
    let shots: [Shot]
    @Binding var followMode: Bool

    var body: some View {
        ActiveRoundMapKit(
            shots: shots,
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
        map.showsCompass = true
        map.showsScale = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onFollowModeChange = onFollowModeChange

        if isFollowing, map.userTrackingMode != .follow {
            map.setUserTrackingMode(.follow, animated: true)
        }

        syncAnnotations(in: map)
    }

    private func syncAnnotations(in map: MKMapView) {
        let existing = map.annotations.compactMap { $0 as? ShotAnnotation }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.shot.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, $0) })

        for (id, ann) in existingByID where currentByID[id] == nil {
            map.removeAnnotation(ann)
        }

        for shot in shots {
            guard let lat = shot.latitude, let lng = shot.longitude else { continue }
            if let existing = existingByID[shot.id] {
                if existing.shot.sequenceNumber != shot.sequenceNumber {
                    map.removeAnnotation(existing)
                    let updated = ShotAnnotation(shot: shot)
                    updated.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    updated.title = "Shot \(shot.sequenceNumber)"
                    map.addAnnotation(updated)
                }
            } else {
                let ann = ShotAnnotation(shot: shot)
                ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                ann.title = "Shot \(shot.sequenceNumber)"
                map.addAnnotation(ann)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onFollowModeChange: (Bool) -> Void

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

            let identifier = "ShotMarker"
            let view: MKMarkerAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
                view = dequeued
                view.annotation = annotation
            } else {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            view.glyphText = "\(shotAnn.shot.sequenceNumber)"
            view.markerTintColor = markerColor(for: shotAnn.shot)
            view.canShowCallout = true
            return view
        }

        private func markerColor(for shot: Shot) -> UIColor {
            switch shot.source {
            case .button: return .systemOrange
            case .actionButton: return .systemBlue
            case .manual: return .systemGray
            case .glasses: return .systemGreen
            }
        }
    }
}

private final class ShotAnnotation: NSObject, MKAnnotation {
    var shot: Shot
    var coordinate: CLLocationCoordinate2D
    var title: String?

    init(shot: Shot) {
        self.shot = shot
        self.coordinate = CLLocationCoordinate2D(
            latitude: shot.latitude ?? 0,
            longitude: shot.longitude ?? 0
        )
        self.title = "Shot \(shot.sequenceNumber)"
        super.init()
    }
}
