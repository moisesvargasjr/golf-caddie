import CoreLocation
import SwiftUI

/// B7.3 — on-demand pin corrector for the hole-review sheet. Presents the
/// hole's shots on the satellite map (reusing `EditableHoleMap`'s draggable,
/// sequence-numbered pins); dropping a pin reports the new coordinate up so
/// the host can persist it and re-reconstruct — a hand-placed pin reads as
/// fully confident, which clears the amber "check" cue. Full-bleed map under
/// a paper top bar.
struct HolePinMapSheet: View {
    let shots: [Shot]
    let holeID: UUID
    let holeNumber: Int
    /// Called on drop with the shot and its new coordinate (host persists).
    let onShotMoved: (Shot, CLLocationCoordinate2D) -> Void
    let onDone: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            EditableHoleMap(
                shots: shots,
                holeID: holeID,
                onShotMoved: onShotMoved
            )
            .ignoresSafeArea()

            topBar
        }
        .themedRoot()
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { onDone() } label: {
                paperPill("✓ Done")
            }
            .buttonStyle(.plain)

            Spacer()

            paperPill("Hole \(holeNumber) · drag a pin")
        }
        .padding(16)
    }

    private func paperPill(_ text: String) -> some View {
        PaperCard(padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) {
            Text(text.uppercased())
                .font(AppFont.stamp)
                .tracking(1.2)
                .foregroundStyle(palette.ink)
        }
    }
}
