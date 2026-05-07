import CoreLocation
import MapKit
import SwiftUI

struct ActiveRoundMap: View {
    let location: LocationManager
    let shots: [Shot]
    let lastMarkResult: RoundController.ShotMarkResult?

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            ForEach(shotsWithCoordinate) { shot in
                Marker(
                    "\(shot.sequenceNumber)",
                    coordinate: CLLocationCoordinate2D(
                        latitude: shot.latitude ?? 0,
                        longitude: shot.longitude ?? 0
                    )
                )
                .tint(markerTint(for: shot))
            }
        }
        .mapStyle(.imagery)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .topLeading) {
            heading
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var shotsWithCoordinate: [Shot] {
        shots.filter { $0.latitude != nil && $0.longitude != nil }
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

    private func markerTint(for shot: Shot) -> Color {
        switch shot.source {
        case .button: return .orange
        case .actionButton: return .blue
        case .manual: return .gray
        }
    }
}
