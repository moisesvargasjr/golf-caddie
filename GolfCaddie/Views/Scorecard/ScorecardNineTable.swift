import SwiftUI

/// One nine as columns (Scorecard-Portrait / iPhone-Scorecard-Landscape
/// mockups): a label column, nine hole columns and the OUT / IN column. Each
/// hole column is one button — tap to pick the hole, tap again to clear.
struct ScorecardNineTable: View {
    let nine: ScorecardNine
    let content: ScorecardContent
    let metrics: Metrics
    @Binding var selectedHole: Int?

    struct Metrics {
        let labelWidth: CGFloat
        let labelFontSize: CGFloat
        let headHeight: CGFloat
        /// nil = no YDS row (the landscape card drops it).
        let yardsHeight: CGFloat?
        let parHeight: CGFloat
        let scoreHeight: CGFloat
        let puttsHeight: CGFloat
        /// The head of the label column reads FRONT / BACK instead of HOLE.
        let headUsesNineName: Bool
        let holeFontSize: CGFloat
        let numberFontSize: CGFloat
        let scoreFontSize: CGFloat
        let markSize: CGFloat
        let totalScoreFontSize: CGFloat
        /// The OUT / IN column's share relative to a hole column.
        let totalFraction: CGFloat

        /// Open Duo held tall.
        static let portrait = Metrics(
            labelWidth: 62, labelFontSize: 10, headHeight: 36, yardsHeight: 30, parHeight: 30,
            scoreHeight: 52, puttsHeight: 36, headUsesNineName: false, holeFontSize: 16,
            numberFontSize: 12, scoreFontSize: 22, markSize: 36, totalScoreFontSize: 20, totalFraction: 1)

        /// iPhone landscape.
        static let landscape = Metrics(
            labelWidth: 60, labelFontSize: 9, headHeight: 26, yardsHeight: nil, parHeight: 24,
            scoreHeight: 48, puttsHeight: 24, headUsesNineName: true, holeFontSize: 14,
            numberFontSize: 11, scoreFontSize: 19, markSize: 32, totalScoreFontSize: 19, totalFraction: 1.2)
    }

    private let ink = CardInk.ink

    var body: some View {
        FractionalRow(fixedLeading: metrics.labelWidth,
                      fractions: Array(repeating: 1, count: 9) + [metrics.totalFraction]) {
            labelColumn
            ForEach(Array(nine.holes), id: \.self) { n in
                holeColumn(n)
            }
            totalColumn
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
    }

    // MARK: Columns

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelCell(metrics.headUsesNineName ? nine.name : "HOLE", height: metrics.headHeight, isHead: true)
            if let yards = metrics.yardsHeight { labelCell("YDS", height: yards) }
            labelCell("PAR", height: metrics.parHeight)
            labelCell("SCORE", height: metrics.scoreHeight)
            labelCell("PUTTS", height: metrics.puttsHeight, divided: false)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(ink).frame(width: 1.5) }
        .accessibilityHidden(true)
    }

    private func holeColumn(_ n: Int) -> some View {
        let column = content.column(n)
        let isSelected = selectedHole == n
        let isLive = content.currentHole == n
        return Button {
            ScorecardContent.toggle(n, in: $selectedHole)
        } label: {
            VStack(spacing: 0) {
                Text("\(n)")
                    .font(CardInk.serif(metrics.holeFontSize))
                    .foregroundStyle(CardInk.palette.paper)
                    .frame(maxWidth: .infinity, minHeight: metrics.headHeight, maxHeight: metrics.headHeight)
                    .background(ink)
                if let yards = metrics.yardsHeight {
                    numberCell(column.yards.map(String.init), height: yards, size: 10, color: CardInk.ink2)
                }
                numberCell(column.par.map(String.init), height: metrics.parHeight,
                           size: metrics.numberFontSize, color: ink)
                ScorecardScoreGlyph(cell: content.cell(n), font: CardInk.serif(metrics.scoreFontSize),
                                    size: metrics.markSize)
                    .frame(maxWidth: .infinity, minHeight: metrics.scoreHeight, maxHeight: metrics.scoreHeight)
                    .overlay(alignment: .bottom) { divider }
                numberCell(column.putts.map(String.init), height: metrics.puttsHeight,
                           size: metrics.numberFontSize, color: CardInk.ink2, divided: false)
            }
            .background(ScorecardColumnWash(isSelected: false, isLive: isLive && !isSelected))
            .overlay {
                if isSelected { ScorecardColumnWash(isSelected: true, isLive: false) }
            }
            .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.15)).frame(width: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(content.accessibilityLabel(n))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("scorecard.hole.\(n)")
    }

    private var totalColumn: some View {
        let totals = content.model.totals(nine)
        return VStack(spacing: 0) {
            Text(nine.totalLabel)
                .font(CardInk.mono(10))
                .foregroundStyle(CardInk.palette.paper)
                .frame(maxWidth: .infinity, minHeight: metrics.headHeight, maxHeight: metrics.headHeight)
                .background(ink)
            if let yards = metrics.yardsHeight {
                numberCell(totals.yards.map(String.init), height: yards, size: 10, color: CardInk.ink2)
            }
            numberCell(totals.par.map(String.init) ?? "—", height: metrics.parHeight,
                       size: metrics.numberFontSize, color: ink)
            Text(ScorecardText.number(totals.score))
                .font(CardInk.serif(metrics.totalScoreFontSize))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: metrics.scoreHeight, maxHeight: metrics.scoreHeight)
                .overlay(alignment: .bottom) { divider }
            numberCell(ScorecardText.number(totals.putts), height: metrics.puttsHeight,
                       size: metrics.numberFontSize, color: CardInk.ink2, divided: false)
        }
        .background(ink.opacity(0.06))
        .overlay(alignment: .leading) { Rectangle().fill(ink).frame(width: 1.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScorecardText.totalAccessibilityLabel(nine == .front ? "Out" : "In", totals))
        .accessibilityIdentifier("scorecard.total.\(nine.totalLabel.lowercased())")
    }

    // MARK: Cells

    private func labelCell(_ text: String, height: CGFloat, isHead: Bool = false,
                           divided: Bool = true) -> some View {
        Text(text)
            .font(CardInk.mono(metrics.labelFontSize))
            .foregroundStyle(isHead ? CardInk.palette.paper : CardInk.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .background(isHead ? ink : Color.clear)
            .overlay(alignment: .bottom) { if divided && !isHead { divider } }
    }

    private func numberCell(_ text: String?, height: CGFloat, size: CGFloat, color: Color,
                            divided: Bool = true) -> some View {
        Text(text ?? "")
            .font(CardInk.mono(size))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .tabularNumerals()
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .overlay(alignment: .bottom) { if divided { divider } }
    }

    private var divider: some View {
        Rectangle().fill(ink.opacity(0.15)).frame(height: 1)
    }
}
