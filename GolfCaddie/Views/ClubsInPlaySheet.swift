import SwiftUI

/// Paper-styled pick of the clubs carried today. Tap a row to leave that club
/// home; the pick applies as it's made and is remembered for the next round.
struct ClubsInPlaySheet: View {
    let bag: [Club]
    @Binding var leftOut: [String]
    let onDone: () -> Void

    @Environment(\.palette) private var palette

    private var inPlayCount: Int { ClubsInPlay.resolve(bag: bag, leftOut: leftOut).count }

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
                    VStack(spacing: 0) {
                        ForEach(bag) { club in
                            row(club)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                }

                Text("The watch and glasses only offer the clubs in play. Your bag isn't changed.")
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
                onDone()
            } label: {
                Text("‹ DONE")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
            Button {
                leftOut = []
            } label: {
                Text("ALL IN")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(leftOut.isEmpty ? palette.ink3 : palette.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(leftOut.isEmpty)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: "Today · \(inPlayCount) of \(bag.count) clubs")
            Text("Clubs in play.")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
        }
    }

    private func row(_ club: Club) -> some View {
        let isOut = leftOut.contains(club.id)
        // The last putter and the last full-shot club stay in.
        let locked = !isOut && !ClubsInPlay.canLeaveOut(club, bag: bag, leftOut: leftOut)
        return Button {
            if isOut {
                leftOut.removeAll { $0 == club.id }
            } else {
                leftOut.append(club.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOut ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(isOut || locked ? palette.ink3 : palette.ink)
                Text(club.shortName)
                    .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                    .foregroundStyle(isOut ? palette.ink3 : palette.ink2)
                    .frame(width: 36, alignment: .leading)
                Text(club.name)
                    .font(AppFont.bodyLarge)
                    .foregroundStyle(isOut ? palette.ink3 : palette.ink)
                    .strikethrough(isOut, color: palette.ink3)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }
}

#Preview {
    ClubsInPlaySheet(
        bag: Club.seedCatalog,
        leftOut: .constant(["threeIron", "fourIron"]),
        onDone: {}
    )
}
