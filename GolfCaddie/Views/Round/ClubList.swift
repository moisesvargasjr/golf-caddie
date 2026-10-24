import SwiftUI

/// The clubs in play. With a shot selected, picking a club changes that
/// shot's club; otherwise it is the club for the next shot. Vertical down the
/// panel's edge (open Duo, landscape, folded box) or a sideways row (iPhone).
struct ClubList: View {
    enum Axis: Equatable {
        /// Column `width` pt wide; `rowStyle` lays name and carry side by side
        /// (folded box) instead of stacked.
        case vertical(width: CGFloat?, rowStyle: Bool)
        case horizontal
    }

    let model: RoundPanelModel
    let actions: RoundPanelActions
    let axis: Axis
    var cellHeight: CGFloat = 48
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            switch axis {
            case let .vertical(width, rowStyle):
                VStack(spacing: 0) {
                    header(rowStyle: rowStyle)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.clubs) { chip in cell(chip, rowStyle: rowStyle) }
                        }
                        .padding(rowStyle ? 5 : 6)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: width)
            case .horizontal:
                HStack(spacing: 6) {
                    Text(model.clubListTitle)
                        .font(RoundFont.mono(9))
                        .foregroundStyle(model.clubListHighlighted ? palette.paper : palette.ink2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(model.clubListHighlighted ? palette.flag : Color.clear)
                        .fixedSize()
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 4) {
                            ForEach(model.clubs) { chip in cell(chip, rowStyle: false).frame(width: 52) }
                        }
                        .padding(.bottom, 2)
                    }
                    .scrollIndicators(.hidden)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!model.clubsEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.clubListTitle == "NEXT SHOT" ? "Club for the next shot" : model.clubListTitle)
        .accessibilityIdentifier(InRoundAccessibilityID.clubList)
    }

    @ViewBuilder
    private func header(rowStyle: Bool) -> some View {
        let highlighted = model.clubListHighlighted
        Group {
            if rowStyle {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.clubListTitle).font(RoundFont.mono(9)).tracking(0.6)
                    Spacer(minLength: 4)
                    if let active = model.clubs.first(where: \.isActive) {
                        Text(active.club.shortName).font(RoundFont.mono(11))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else {
                Text(model.clubListTitle)
                    .font(RoundFont.mono(10))
                    .tracking(0.6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
            }
        }
        .foregroundStyle(highlighted ? palette.paper : palette.ink2)
        .background(highlighted ? palette.flag : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private func cell(_ chip: ClubChipModel, rowStyle: Bool) -> some View {
        let fill = model.clubListHighlighted ? palette.flag : palette.ink
        return Button { actions.pickClub(chip.club) } label: {
            Group {
                if rowStyle {
                    HStack {
                        Text(chip.club.shortName).font(RoundFont.serif(17))
                        Spacer(minLength: 2)
                        if let carry = chip.carryText {
                            Text("\(carry) YD").font(RoundFont.mono(10)).opacity(0.8).tabularNumerals()
                        }
                    }
                    .padding(.horizontal, 10)
                } else {
                    VStack(spacing: 1) {
                        Text(chip.club.shortName).font(RoundFont.mono(15)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(chip.carryText ?? " ").font(RoundFont.mono(9)).opacity(0.8).tabularNumerals()
                    }
                }
            }
            .foregroundStyle(chip.isActive ? palette.paper : palette.ink)
            .frame(maxWidth: .infinity, minHeight: max(rowStyle ? 44 : cellHeight, RoundChromeMetrics.minTap))
            .background(chip.isActive ? fill : Color.clear)
            .overlay {
                if !chip.isActive {
                    Rectangle().strokeBorder(palette.ruleStrong, lineWidth: RoundChromeMetrics.rule)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.club.name)
        .accessibilityValue(chip.carryText.map { "\($0) average" } ?? "")
        .accessibilityAddTraits(chip.isActive ? .isSelected : [])
    }
}
