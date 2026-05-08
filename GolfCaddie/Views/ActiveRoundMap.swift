import CoreLocation
import MapKit
import SwiftUI

struct ActiveRoundMap: View {
    let location: LocationManager
    let shots: [Shot]
    let lastMarkResult: RoundController.ShotMarkResult?
    let battery: BatteryMonitor
    let batteryDropSinceStart: Int?

    @State private var followMode: Bool = true

    var body: some View {
        ZStack {
            ActiveRoundMapKit(
                shots: shots,
                isFollowing: followMode,
                onFollowModeChange: { newValue in
                    if followMode != newValue {
                        followMode = newValue
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack {
                HStack {
                    heading
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    if !followMode {
                        Button {
                            followMode = true
                        } label: {
                            Label("Follow", systemImage: "location.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Shots: \(shots.count)")
                .font(.caption.weight(.semibold))
            if let last = lastMarkResult {
                Text(lastResultText(last))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let percent = battery.percent {
                HStack(spacing: 4) {
                    Image(systemName: battery.iconName)
                        .foregroundStyle(batteryColor(percent: percent))
                    Text("\(percent)%")
                    if let drop = batteryDropSinceStart {
                        Text("(-\(drop)%)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func lastResultText(_ result: RoundController.ShotMarkResult) -> String {
        switch result {
        case let .success(_, accuracy):
            if let accuracy {
                return String(format: "Last ±%.1fm", accuracy)
            }
            return "Last: no GPS"
        case let .failed(reason):
            return "Failed: \(reason)"
        }
    }

    private func batteryColor(percent: Int) -> Color {
        if percent <= 15 { return .red }
        if percent <= 25 { return .orange }
        return .primary
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
