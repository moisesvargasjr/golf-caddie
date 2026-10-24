import SwiftUI

/// Casual mode's "Your round": every scored hole, newest first; tap one to
/// open it and edit its score. Three variants from the casual boards:
/// - `.list`: "Your round · 31 · +4 THRU 7" over rows (open Duo, book,
///   iPhone landscape);
/// - `.chips`: a sideways row of 88 pt chips (iPhone portrait);
/// - `.squares`: "ROUND +4 THRU 7" over stacked squares (folded lower box).
struct RoundScoresList: View {
    let roundSoFar: RoundSoFar
    let variant: RoundScoresVariant
    let onPick: (Int) -> Void
    /// Row height for `.list` (landscape is tighter).
    var rowHeight: CGFloat = 44
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            switch variant {
            case .list: list
            case .chips: chips
            case .squares: squares
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your round, \(roundSoFar.shortText.lowercased())")
        .accessibilityIdentifier(InRoundAccessibilityID.roundScores)
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your round").font(RoundFont.serifItalic(16).weight(.bold)).foregroundStyle(palette.ink)
                Spacer(minLength: 6)
                Text(roundSoFar.headerText).font(RoundFont.mono(11)).foregroundStyle(palette.ink).lineLimit(1)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.ink).frame(height: RoundChromeMetrics.rule) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(roundSoFar.rows) { row in listRow(row) }
                    if roundSoFar.isEmpty { emptyText.padding(.vertical, 10) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func listRow(_ row: RoundScoreRow) -> some View {
        pickButton(row) {
            HStack(spacing: 8) {
                Text("\(row.holeNumber)")
                    .font(RoundFont.serif(16))
                    .frame(width: 34, alignment: .leading)
                Text(row.parText).font(RoundFont.mono(10)).foregroundStyle(palette.ink2)
                Spacer(minLength: 4)
                RoundScoreMark(row: row, side: 30, fontSize: 17)
                Text(row.detailText)
                    .font(RoundFont.mono(11))
                    .foregroundStyle(palette.ink2)
                    .lineLimit(1)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: max(rowHeight, RoundChromeMetrics.minTap))
            .background(row.isOnScreen ? palette.flag.opacity(0.14) : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
        }
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 4) {
                ForEach(roundSoFar.rows) { row in
                    pickButton(row) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("H\(row.holeNumber)").font(RoundFont.serif(15)).foregroundStyle(palette.ink)
                                Text(row.parText).font(RoundFont.mono(9)).foregroundStyle(palette.ink2)
                            }
                            Spacer(minLength: 2)
                            RoundScoreMark(row: row, side: 26, fontSize: 16)
                        }
                        .padding(.horizontal, 8)
                        .frame(width: 88, height: 48)
                        .modifier(ChipFrame(highlighted: row.isOnScreen))
                    }
                }
                if roundSoFar.isEmpty { emptyText.frame(minHeight: 48) }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
        .frame(height: 50)
    }

    // MARK: Squares

    private var squares: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                StampLabel(text: "ROUND", size: 9)
                Spacer(minLength: 4)
                Text(roundSoFar.shortText).font(RoundFont.mono(11)).foregroundStyle(palette.ink).lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(roundSoFar.rows) { row in squareRow(row) }
                    if roundSoFar.isEmpty { emptyText.padding(.vertical, 8) }
                }
                .padding(5)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func squareRow(_ row: RoundScoreRow) -> some View {
        pickButton(row) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hole \(row.holeNumber)").font(RoundFont.serif(16)).foregroundStyle(palette.ink)
                    Text(row.parText).font(RoundFont.mono(9)).foregroundStyle(palette.ink2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                RoundScoreMark(row: row, side: 26, fontSize: 16)
                Text(row.toParText)
                    .font(RoundFont.mono(10))
                    .foregroundStyle(palette.ink2)
                    .frame(width: 22, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .modifier(ChipFrame(highlighted: row.isOnScreen))
        }
    }

    // MARK: Shared

    private var emptyText: some View {
        Text("No holes scored yet.")
            .font(RoundFont.serifItalic(14))
            .foregroundStyle(palette.ink3)
    }

    private func pickButton<Label: View>(_ row: RoundScoreRow, @ViewBuilder label: () -> Label) -> some View {
        Button { onPick(row.holeNumber) } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint("Double-tap to open the hole and edit its score.")
            .accessibilityAddTraits(row.isOnScreen ? .isSelected : [])
            .accessibilityIdentifier(InRoundAccessibilityID.roundScoreHole(row.holeNumber))
    }
}

/// The score with its scorecard mark: circled under par, boxed over par.
struct RoundScoreMark: View {
    let row: RoundScoreRow
    let side: CGFloat
    let fontSize: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        Text("\(row.strokes)")
            .font(RoundFont.serif(fontSize))
            .foregroundStyle(palette.ink)
            .tabularNumerals()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: side, height: side)
            .overlay {
                switch row.shape {
                case .circle: Circle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule)
                case .square: Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule)
                case .plain: EmptyView()
                }
            }
            .accessibilityHidden(true)
    }
}

/// Faint outline around a chip / square; the flag colour on the hole on screen.
private struct ChipFrame: ViewModifier {
    let highlighted: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(highlighted ? palette.flag.opacity(0.14) : Color.clear)
            .overlay(Rectangle().strokeBorder(highlighted ? palette.flag : palette.ruleStrong,
                                              lineWidth: RoundChromeMetrics.rule))
    }
}

/// iPhone portrait casual: "YOUR ROUND +4 THRU 7" beside the 200 pt
/// Finish hole › (or Back to hole N › on a past hole).
struct CasualFinishRow: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                StampLabel(text: "YOUR ROUND", size: 9)
                Text(model.roundSoFar.shortText)
                    .font(RoundFont.mono(15))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Group {
                if model.isLiveHole {
                    PrimaryActionButton(title: InRoundLabels.finish, fontSize: 18, minHeight: 52,
                                        action: actions.finishHole)
                        .accessibilityIdentifier(InRoundAccessibilityID.finishHole)
                } else {
                    PrimaryActionButton(title: model.backToLiveTitle, fontSize: 16, minHeight: 52,
                                        action: actions.backToLive)
                        .accessibilityIdentifier(InRoundAccessibilityID.backToLive)
                }
            }
            .frame(width: 200)
        }
    }
}

/// Folded casual: the action box's Finish hole, filling it, with the flag.
struct FlagFinishButton: View {
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "flag.fill").font(.system(size: 22, weight: .semibold))
                Text("Finish hole").font(RoundFont.serif(17))
            }
            .foregroundStyle(palette.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: RoundChromeMetrics.minTap)
            .background(palette.ink)
            .shadow(color: palette.cardShadow.color, radius: 0, x: RoundChromeMetrics.shadow,
                    y: RoundChromeMetrics.shadow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Finish hole")
        .accessibilityIdentifier(InRoundAccessibilityID.finishHole)
    }
}
