import SwiftUI

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
    @AppStorage("glassesServerEnabled") private var glassesEnabled = false

    @Binding var bag: [ClubID]

    @State private var showBagEditor = false

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
        }
        .themedRoot()
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

#Preview {
    SettingsView(bag: .constant(ClubConfiguration.recommendedDefault.bag))
}
