import CoreLocation
import SwiftUI
import UIKit

/// Identifiable URL wrapper so a generated export file can drive `.sheet(item:)`.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Minimal share-sheet bridge — used to hand the anchor-export JSON file to
/// AirDrop/Files so the coursedata tooling can `import-anchors` it. The app
/// never pushes to git itself (human/agent is the transport, by design).
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// Shared hole-editing UI, used by both `HoleReviewSheet` (active-round hole
// confirm) and `HoleDetailView` (previous-hole editor). Extracted verbatim
// from HoleReviewSheet so the two screens cannot drift apart.

struct ShotReviewRow: View {
    let shot: Shot
    let bag: [ClubID]
    let distanceMeters: Double?
    let onClubChange: (ClubID?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Shot \(shot.sequenceNumber)")
                .font(.callout.weight(.medium))
                .frame(width: 64, alignment: .leading)

            Menu {
                ForEach(bag) { club in
                    Button(club.longName) { onClubChange(club) }
                }
                Divider()
                Button("(no club)", role: .destructive) { onClubChange(nil) }
            } label: {
                clubLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            distanceLabel
        }
    }

    @ViewBuilder
    private var clubLabel: some View {
        if let club = shot.club {
            Text(club.longName)
                .foregroundStyle(.primary)
        } else {
            Text("tap to set club")
                .foregroundStyle(.orange)
                .italic()
        }
    }

    @ViewBuilder
    private var distanceLabel: some View {
        if let meters = distanceMeters {
            let yards = Int(Distance.yards(fromMeters: meters).rounded())
            Text("\(yards) yds")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if !shot.hadGPS {
            Text("manual")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("—")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}

struct AddMissingShotSheet: View {
    let bag: [ClubID]
    let currentShotCount: Int
    let onAdd: (ClubID?, Int) -> Void
    let onCancel: () -> Void

    @State private var club: ClubID?
    @State private var position: Int = 1
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { onCancel() } label: {
                        Text("‹ CANCEL")
                            .font(AppFont.metadata)
                            .tracking(1.4)
                            .foregroundStyle(palette.ink)
                    }
                    Spacer()
                    Button { onAdd(club, position) } label: {
                        Text("ADD ›")
                            .font(AppFont.metadata)
                            .tracking(1.4)
                            .foregroundStyle(palette.flag)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Stamp(text: "Manual entry")
                    Text("Add a shot.")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(palette.ink)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Position")
                            HStack {
                                Stepper(value: $position, in: 1 ... max(1, currentShotCount + 1)) {
                                    Text("Insert as shot \(position)")
                                        .font(AppFont.bodyLarge)
                                        .foregroundStyle(palette.ink)
                                }
                            }
                            Text(positionHint)
                                .font(AppFont.micro)
                                .tracking(0.8)
                                .foregroundStyle(palette.ink3)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Club")
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
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Manual shots have no GPS, so distances won't be shown for adjacent shots.")
                            .font(AppFont.micro)
                            .tracking(0.8)
                            .foregroundStyle(palette.ink3)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                }
            }
        }
        .presentationBackground(palette.paper)
        .themedRoot()
        .onAppear {
            position = currentShotCount + 1
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
            Spacer()
            Rectangle().fill(palette.rule).frame(height: 1)
        }
    }

    private var positionHint: String {
        if position <= currentShotCount {
            return "Existing shots from #\(position) onward will shift up by 1."
        }
        return "Will be appended at the end."
    }
}

// Local italic-conditional helper.
private extension Text {
    func italic(_ on: Bool) -> Text { on ? self.italic() : self }
}
