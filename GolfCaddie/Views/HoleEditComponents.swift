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

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    Stepper(
                        "Insert as Shot \(position)",
                        value: $position,
                        in: 1 ... max(1, currentShotCount + 1)
                    )
                    Text(positionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Club") {
                    Picker("Club", selection: $club) {
                        Text("(no club)").tag(ClubID?.none)
                        ForEach(bag) { c in
                            Text(c.longName).tag(ClubID?.some(c))
                        }
                    }
                }
                Section {
                    Text("Manual shots have no GPS, so distances won't be shown for adjacent shots.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Missing Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onAdd(club, position)
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            position = currentShotCount + 1
        }
    }

    private var positionHint: String {
        if position <= currentShotCount {
            return "Existing shots from #\(position) onward will shift up by 1."
        }
        return "Will be appended at the end."
    }
}
