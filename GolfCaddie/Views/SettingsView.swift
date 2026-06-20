import SwiftUI
import UIKit

/// Lightweight settings screen exposing the two user-facing tweaks from the
/// redesign: theme mode and distance units. The other prototype tweaks
/// (ink hue, accent, Roman/Arabic numerals) are intentionally not surfaced —
/// defaults are hardcoded per the design.
///
/// Bag editor and Glasses server are reached via NavigationLinks.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @AppStorage("themeMode") private var themeRaw: String = ThemeMode.auto.rawValue
    @AppStorage("units") private var unitsRaw: String = Units.yards.rawValue
    // Default mode new rounds start in (toggleable mid-round on the round screen).
    @AppStorage("roundModeDefaultCasual") private var defaultCasual = false
    @AppStorage("glassesServerEnabled") private var glassesEnabled = false
    // Output-only by default (the watch is the input device). Flip on to make
    // the glasses an input surface too — the fallback when the watch dies
    // mid-round, so you're not stuck taking the phone out every stroke.
    @AppStorage("glassesInputEnabled") private var glassesInputEnabled = false

    @Binding var bag: [ClubID]

    @State private var showBagEditor = false
    @State private var pendingExport: PendingExport?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    masthead

                    section(label: "Theme") {
                        themePicker
                    }

                    section(label: "Distance") {
                        unitsPicker
                    }

                    section(label: "Round mode") {
                        Toggle(isOn: $defaultCasual) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Casual by default")
                                    .font(AppFont.bodyLarge)
                                    .foregroundStyle(palette.ink)
                                Text("GPS + MAP + SIMPLE SCORE, NO SHOT TRACKING")
                                    .font(AppFont.micro)
                                    .tracking(1.2)
                                    .foregroundStyle(palette.ink3)
                            }
                        }
                        .tint(palette.flag)
                    }

                    section(label: "Equipment") {
                        Button {
                            showBagEditor = true
                        } label: {
                            HStack {
                                Text("The Bag")
                                    .font(AppFont.bodyLarge)
                                    .italic()
                                    .foregroundStyle(palette.ink)
                                Spacer()
                                Stamp(text: "\(bag.count) clubs")
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    section(label: "Glasses") {
                        Toggle(isOn: $glassesEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Even Realities G2")
                                    .font(AppFont.bodyLarge)
                                    .foregroundStyle(palette.ink)
                                Text("127.0.0.1:\(GlassesServer.port) · device-only")
                                    .font(AppFont.micro)
                                    .tracking(1.2)
                                    .foregroundStyle(palette.ink3)
                            }
                        }
                        .tint(palette.flag)

                        if glassesEnabled {
                            Toggle(isOn: $glassesInputEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Glasses input")
                                        .font(AppFont.bodyLarge)
                                        .foregroundStyle(palette.ink)
                                    Text("USE WHEN THE WATCH IS OFF/DEAD")
                                        .font(AppFont.micro)
                                        .tracking(1.2)
                                        .foregroundStyle(palette.ink3)
                                }
                            }
                            .tint(palette.flag)
                        }
                    }

                    section(label: "Backup") {
                        exportRoundsButton
                    }

                    section(label: "Watch Spike") {
                        NavigationLink {
                            SpikeSessionsView()
                        } label: {
                            HStack {
                                Text("Recorded Sessions")
                                    .font(AppFont.bodyLarge)
                                    .italic()
                                    .foregroundStyle(palette.ink)
                                Spacer()
                                Image(systemName: "applewatch")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(palette.ink3)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(PaperBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("‹ DONE")
                            .font(AppFont.metadata)
                            .tracking(1.4)
                            .foregroundStyle(palette.ink)
                    }
                }
            }
            .sheet(isPresented: $showBagEditor) {
                BagSetupView(
                    initialBag: bag,
                    onCancel: { showBagEditor = false }
                ) { newBag in
                    bag = newBag
                    showBagEditor = false
                }
            }
            .sheet(item: $pendingExport) { export in
                ShareActivityView(activityItems: [export.url])
            }
            .alert(
                "Export failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                ),
                actions: {
                    Button("OK") { exportError = nil }
                },
                message: {
                    Text(exportError ?? "")
                }
            )
        }
        .themedRoot()
    }

    // MARK: - Export

    private var exportRoundsButton: some View {
        Button {
            runExport()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Rounds")
                        .font(AppFont.bodyLarge)
                        .italic()
                        .foregroundStyle(palette.ink)
                    Text("Share a .sqlite snapshot of every round, hole, shot, and penalty. Save it to Files or AirDrop for backup.")
                        .font(AppFont.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.ink3)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.ink3)
                    .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func runExport() {
        do {
            let url = try Database.makeExport()
            pendingExport = PendingExport(url: url)
        } catch {
            exportError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Subviews

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Stamp(text: "Caddie")
            ItalicHeadline(
                lines: ["The", "Settings."],
                font: AppFont.masthead,
                color: palette.ink,
                tracking: -2,
                lineSpacing: -6
            )
            .padding(.top, 12)
        }
    }

    private func section(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label.uppercased())
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Spacer()
                Rectangle()
                    .fill(palette.rule)
                    .frame(height: 1)
            }
            content()
        }
    }

    private var themePicker: some View {
        HStack(spacing: 0) {
            ForEach(ThemeMode.allCases) { mode in
                let isSelected = mode.rawValue == themeRaw
                Button {
                    themeRaw = mode.rawValue
                } label: {
                    Text(mode.label.uppercased())
                        .font(AppFont.stamp)
                        .tracking(1.2)
                        .foregroundStyle(isSelected ? palette.paper : palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelected ? palette.ink : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var unitsPicker: some View {
        HStack(spacing: 0) {
            ForEach(Units.allCases) { unit in
                let isSelected = unit.rawValue == unitsRaw
                Button {
                    unitsRaw = unit.rawValue
                } label: {
                    Text(unit.label.uppercased())
                        .font(AppFont.stamp)
                        .tracking(1.2)
                        .foregroundStyle(isSelected ? palette.paper : palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelected ? palette.ink : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Helpers

private struct PendingExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin SwiftUI wrapper around UIActivityViewController for the share sheet.
/// Lives here since Settings is the only consumer today; promote to its own
/// file if a second screen needs to share files.
private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView(bag: .constant(ClubConfiguration.recommendedDefault.bag))
}
