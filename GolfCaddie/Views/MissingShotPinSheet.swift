import CoreLocation
import MapKit
import SwiftUI

/// In-round recovery for "I forgot to tap Log Shot." Presents a satellite
/// map; the user pans/zooms until the crosshair sits where the missed
/// shot actually landed, picks a club, taps ADD. The shot is appended to
/// the end of the active hole's shots via
/// `RoundController.insertMissingShot(at:club:)`.
///
/// Crosshair-at-center (rather than draggable pin) for a deliberate
/// reason: SwiftUI Map can't directly draggable annotations in iOS 17
/// without dropping to UIViewRepresentable. Center-pin-drop is the same
/// pattern Apple Maps' "drop pin" uses; the user understands the pin
/// goes where the map is looking, so they pan the MAP instead of the
/// PIN. Fewer moving parts; no fighting with MapKit gesture priorities.
struct MissingShotPinSheet: View {
    let bag: [ClubID]
    /// Initial map center — the active round passes either the latest
    /// live GPS fix or the last logged shot's coordinate so the user
    /// doesn't have to scroll across the country to find their hole.
    let initialCenter: CLLocationCoordinate2D
    let onAdd: (CLLocationCoordinate2D, ClubID?) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette

    @State private var cameraPosition: MapCameraPosition
    @State private var currentCenter: CLLocationCoordinate2D
    @State private var club: ClubID?

    init(
        bag: [ClubID],
        initialCenter: CLLocationCoordinate2D,
        onAdd: @escaping (CLLocationCoordinate2D, ClubID?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.bag = bag
        self.initialCenter = initialCenter
        self.onAdd = onAdd
        self.onCancel = onCancel
        // Span chosen to frame ~one hole — tight enough that "pan a little
        // to fix the placement" is the natural gesture, not "zoom in from
        // the city."
        let region = MKCoordinateRegion(
            center: initialCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        )
        _cameraPosition = State(initialValue: .region(region))
        _currentCenter = State(initialValue: initialCenter)
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                navRow
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                mapPane
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                clubPicker
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                Text("Pan the map until the crosshair sits where the missed shot landed, then tap ADD.")
                    .font(AppFont.micro)
                    .tracking(0.8)
                    .foregroundStyle(palette.ink3)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Spacer(minLength: 24)
            }
        }
        .presentationBackground(palette.paper)
        .themedRoot()
    }

    private var navRow: some View {
        HStack {
            Button { onCancel() } label: {
                Text("‹ CANCEL")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            Button {
                onAdd(currentCenter, club)
            } label: {
                Text("ADD ›")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.flag)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: "Manual entry")
            Text("Add a missed shot.")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
        }
    }

    private var mapPane: some View {
        // Crosshair pinned to the center of the map regardless of pan/zoom.
        // `onMapCameraChange` tracks the actual center for the ADD action.
        ZStack {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom])
                .mapStyle(.imagery(elevation: .flat))
                .onMapCameraChange(frequency: .continuous) { ctx in
                    currentCenter = ctx.camera.centerCoordinate
                }
            crosshair
                .allowsHitTesting(false)
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.ink, lineWidth: 1)
        )
    }

    private var crosshair: some View {
        ZStack {
            // Outer ring (flag color, high contrast on satellite imagery).
            Circle()
                .stroke(palette.flag, lineWidth: 2)
                .frame(width: 28, height: 28)
            // Small fill so it's visible against light AND dark imagery.
            Circle()
                .fill(palette.flag)
                .frame(width: 6, height: 6)
            // Cross lines extending out — helps eye align with course features.
            Rectangle()
                .fill(palette.flag)
                .frame(width: 1, height: 44)
            Rectangle()
                .fill(palette.flag)
                .frame(width: 44, height: 1)
        }
    }

    private var clubPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CLUB")
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Spacer()
                Rectangle().fill(palette.rule).frame(height: 1)
            }
            Menu {
                Button("(no club)", role: .destructive) { club = nil }
                ForEach(bag) { c in
                    Button(c.longName) { club = c }
                }
            } label: {
                HStack {
                    Text(club?.longName ?? "Tap to set club")
                        .font(AppFont.bodyLarge)
                        .italic(club == nil)
                        .foregroundStyle(club == nil ? palette.flag : palette.ink)
                    Spacer()
                    Text("›")
                        .font(AppFont.metadata)
                        .foregroundStyle(palette.ink2)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            }
            .buttonStyle(.plain)
        }
    }
}

private extension Text {
    /// Conditional italic — mirrors the helper in HoleEditComponents so the
    /// call site reads cleanly. Local copy to keep this file self-contained.
    func italic(_ on: Bool) -> Text {
        on ? self.italic() : self
    }
}
