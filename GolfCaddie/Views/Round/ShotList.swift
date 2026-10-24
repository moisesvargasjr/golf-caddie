import SwiftUI

/// "This hole": one row per shot (tap to select it — then drag its pin or
/// pick a club), penalty rows with REMOVE, and the next shot on the live hole.
struct ShotList: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var showsTitle = true
    var rowHeight: CGFloat = 44
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                // Review-Open titles the list "Shots"; play keeps "This hole".
                Text(model.mode == .review ? "Shots" : "This hole")
                    .font(.custom(AppFont.serifName, size: 16).weight(.bold).italic())
                    .foregroundStyle(palette.ink)
                    .padding(.bottom, 2)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.shotRows) { row in shotRow(row) }
                    ForEach(model.penaltyRows) { row in penaltyRow(row) }
                    if let next = model.nextShotText {
                        Text(next)
                            .font(RoundFont.mono(11))
                            .foregroundStyle(palette.ink2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 12)
                    } else if model.shotRows.isEmpty, model.penaltyRows.isEmpty {
                        Text("No shots yet.")
                            .font(RoundFont.serifItalic(15))
                            .foregroundStyle(palette.ink3)
                            .padding(.vertical, 8)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.shotList)
    }

    private func shotRow(_ row: ShotRowModel) -> some View {
        let color = row.isSelected ? palette.flag : palette.ink
        return Button { actions.selectShot(row.id) } label: {
            HStack {
                Text(row.leftText)
                Spacer(minLength: 8)
                if let distance = row.distanceText { Text(distance).tabularNumerals() }
            }
            .font(RoundFont.mono(12))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: max(rowHeight, RoundChromeMetrics.minTap))
            .background(row.isSelected ? palette.flag.opacity(0.14) : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HoleMapAccessibility.shotLabel(number: row.number,
                                                           club: row.needsClub ? nil : row.clubText,
                                                           selected: row.isSelected))
        .accessibilityHint(row.isSelected ? "Double-tap to deselect." : "Double-tap to select, then pick its club.")
    }

    private func penaltyRow(_ row: PenaltyRowModel) -> some View {
        HStack {
            Text("PEN · \(row.title)")
            Spacer(minLength: 8)
            Button { actions.removePenalty(row.id) } label: {
                Text("+\(row.strokes) · REMOVE")
                    .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap,
                           alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(row.title.lowercased()) penalty, \(row.strokes) stroke\(row.strokes == 1 ? "" : "s")")
        }
        .font(RoundFont.mono(11))
        .foregroundStyle(palette.red)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: max(rowHeight, RoundChromeMetrics.minTap))
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }
}
