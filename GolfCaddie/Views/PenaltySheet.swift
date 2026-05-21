import SwiftUI

/// Paper-styled penalty picker. Each row is a paper card; tap → add +1 stroke.
struct PenaltySheet: View {
    let onPick: (PenaltyType) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                navRow
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(PenaltyType.allCases) { type in
                            Button {
                                onPick(type)
                            } label: {
                                PaperCard(padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                                    HStack {
                                        Text(type.displayName)
                                            .font(AppFont.bodyLarge)
                                            .italic()
                                            .foregroundStyle(palette.ink)
                                        Spacer()
                                        Stamp(text: "+1 stroke", color: palette.flag)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                }

                Text("Each penalty adds 1 stroke. Edit later in hole review if needed.")
                    .font(AppFont.micro)
                    .tracking(0.8)
                    .foregroundStyle(palette.ink3)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .presentationBackground(palette.paper)
        .themedRoot()
    }

    private var navRow: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Text("‹ CANCEL")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: "Penalty", color: palette.flag)
            Text("Add a stroke.")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
        }
    }
}

#Preview {
    PenaltySheet(onPick: { _ in }, onCancel: {})
}
