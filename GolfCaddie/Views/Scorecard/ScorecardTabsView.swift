import SwiftUI

/// The folded Duo and iPhone portrait (Scorecard-Folded / iPhone-Scorecard
/// mockups): FRONT 9 / BACK 9 tabs over a hole-per-row table. Pick a row to
/// get its action in thumb reach; otherwise the round's totals sit there.
struct ScorecardTabsView: View {
    let content: ScorecardContent
    @Binding var selectedHole: Int?
    let windowHeight: CGFloat

    @State private var nine: ScorecardNine?

    private static let edge: CGFloat = 24
    /// HOLE · PAR · YDS · SCORE · PUTTS.
    private static let fractions: [CGFloat] = [1.1, 0.8, 1, 1.2, 0.9]
    private let ink = CardInk.ink

    private var shownNine: ScorecardNine { nine ?? .initial(currentHole: content.currentHole) }
    private var rowHeight: CGFloat { ScorecardTabsMetrics.rowHeight(windowHeight: windowHeight) }
    private var subtotalHeight: CGFloat { ScorecardTabsMetrics.subtotalHeight(windowHeight: windowHeight) }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            VStack(alignment: .leading, spacing: 10) {
                header
                tabs
                table
                if let error = content.loadError {
                    Text(error).font(CardInk.mono(9)).foregroundStyle(CardInk.palette.red)
                }
                Spacer(minLength: 8)
                bottom
            }
            .padding(.top, max(Self.edge, insets.top))
            .padding(.bottom, max(Self.edge, insets.bottom))
            .padding(.leading, max(Self.edge, insets.leading))
            .padding(.trailing, max(Self.edge, insets.trailing))
        }
        .ignoresSafeArea()
    }

    // MARK: Header and tabs

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ScorecardTitleBlock(title: content.courseName, subtitle: content.shortSubtitle)
            Spacer(minLength: 8)
            if let openMap = content.onOpenCourseMap {
                ScorecardCourseMapButton(action: openMap)
            }
            if let menu = content.roundMenu {
                menu
            }
            ScorecardOutlinedButton(title: content.dismissTitle, action: content.onDismiss)
                .accessibilityIdentifier("scorecard.dismiss")
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(ScorecardNine.allCases, id: \.self) { tab in
                let isOn = tab == shownNine
                Button {
                    nine = tab
                    selectedHole = nil
                } label: {
                    Text("\(tab.name) 9 · \(ScorecardText.number(content.model.totals(tab).score))")
                        .font(CardInk.mono(11)).tracking(0.6)
                        .foregroundStyle(isOn ? CardInk.palette.paper : ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                .accessibilityIdentifier("scorecard.tab.\(tab.rawValue)")
            }
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
    }

    // MARK: Table

    private var table: some View {
        VStack(spacing: 0) {
            FractionalRow(fractions: Self.fractions) {
                headCell("HOLE", leading: true)
                headCell("PAR")
                headCell("YDS")
                headCell("SCORE")
                headCell("PUTTS")
            }
            .frame(height: 28)
            .background(ink)
            .accessibilityHidden(true)
            ForEach(Array(shownNine.holes), id: \.self) { n in
                row(n)
            }
            subtotal
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
    }

    private func row(_ n: Int) -> some View {
        let column = content.column(n)
        let isSelected = selectedHole == n
        return Button {
            ScorecardContent.toggle(n, in: $selectedHole)
        } label: {
            FractionalRow(fractions: Self.fractions) {
                Text("\(n)").font(CardInk.serif(17)).foregroundStyle(ink)
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                mono(column.par.map(String.init), size: 12, color: ink)
                mono(column.yards.map(String.init), size: 10, color: CardInk.ink2)
                ScorecardScoreGlyph(cell: content.cell(n), font: CardInk.serif(18), size: 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                mono(column.putts.map(String.init), size: 12, color: CardInk.ink2)
            }
            .frame(height: rowHeight)
            .background(ScorecardColumnWash(isSelected: false, isLive: content.currentHole == n && !isSelected))
            .overlay { if isSelected { ScorecardColumnWash(isSelected: true, isLive: false) } }
            .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.15)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(content.accessibilityLabel(n))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("scorecard.hole.\(n)")
    }

    private var subtotal: some View {
        let totals = content.model.totals(shownNine)
        return FractionalRow(fractions: Self.fractions) {
            Text(shownNine.totalLabel).font(CardInk.mono(11)).foregroundStyle(ink)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            mono(totals.par.map(String.init), size: 12, color: ink)
            mono(totals.yards.map(String.init), size: 10, color: CardInk.ink2)
            Text(ScorecardText.number(totals.score)).font(CardInk.serif(18)).foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            mono(ScorecardText.number(totals.putts), size: 12, color: CardInk.ink2)
        }
        .frame(height: subtotalHeight)
        .background(ink.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(ink).frame(height: 1.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScorecardText.totalAccessibilityLabel(shownNine == .front ? "Out" : "In", totals))
        .accessibilityIdentifier("scorecard.total.\(shownNine.totalLabel.lowercased())")
    }

    private func headCell(_ text: String, leading: Bool = false) -> some View {
        Text(text)
            .font(CardInk.mono(9)).tracking(0.6)
            .foregroundStyle(CardInk.palette.paper)
            .padding(.leading, leading ? 12 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .leading : .center)
    }

    private func mono(_ text: String?, size: CGFloat, color: Color) -> some View {
        Text(text ?? "")
            .font(CardInk.mono(size))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .tabularNumerals()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottom: some View {
        if let pick = selectedHole.map(content.pick), let title = content.ctaTitle(pick) {
            ScorecardFilledButton(title: title, fontSize: 18, minHeight: 52, expands: true) {
                content.onPick(pick)
            }
            .accessibilityIdentifier("scorecard.cta")
        } else {
            HStack(spacing: 6) {
                inlineStat("TOTAL", ScorecardText.number(content.model.total.score))
                    .accessibilityIdentifier("scorecard.stat.total")
                inlineStat("PAR", ScorecardText.toPar(content.model.grossToPar))
                inlineStat("PUTTS", ScorecardText.number(content.model.total.putts))
            }
        }
    }

    private func inlineStat(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(CardInk.mono(9)).foregroundStyle(CardInk.ink2)
            Spacer(minLength: 4)
            Text(value).font(CardInk.serif(22)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}
