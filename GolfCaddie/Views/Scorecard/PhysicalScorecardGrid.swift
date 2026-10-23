import SwiftUI

/// Ink & graphite for the printed card — always the light "paper" look,
/// whatever the app theme.
enum CardInk {
    static let palette = PaletteValues.light
    static let graphite = Color(hex: 0x2B2B2B)
    static let innerCard = Color(hex: 0xF3EBD8)
    static let border: CGFloat = 1.5
    /// System handwriting faces only (no bundled web fonts).
    static func hand(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
}

/// 22-column grid: label · 1–9 · OUT · 10–18 · IN · TOT.
struct PhysicalScorecardGrid: View {
    let model: ScorecardModel
    let highlightedHole: Int?
    @Binding var selectedHole: Int?

    static let labelWidth: CGFloat = 92
    static let scoreRowHeight: CGFloat = 46
    static let rowHeight: CGFloat = 26
    static let headerHeight: CGFloat = 44

    private enum Slot: Hashable {
        case hole(Int), out, inn, tot
    }

    private var slots: [Slot] {
        (1...9).map(Slot.hole) + [.out] + (10...18).map(Slot.hole) + [.inn, .tot]
    }

    private let ink = CardInk.palette.ink

    var body: some View {
        VStack(spacing: 0) {
            holeRow
            textRow("YARDS", height: Self.rowHeight) { col in col.yards.map(String.init) } total: { $0.yards.map(String.init) }
            textRow("PAR", height: Self.rowHeight) { col in col.par.map(String.init) } total: { $0.par.map(String.init) ?? "—" }
            if model.hasStrokeIndex {
                textRow("HCP", height: Self.rowHeight) { col in col.strokeIndex.map(String.init) } total: { _ in nil }
            }
            scoreRow
            textRow("PUTTS", height: Self.rowHeight, hand: true) { col in col.putts.map(String.init) } total: { $0.putts.map(String.init) }
            textRow("GIR", height: Self.rowHeight) { col in col.gir == true ? "●" : nil } total: { _ in nil }
            textRow("PEN", height: Self.rowHeight, color: CardInk.palette.red) { col in
                col.penalties.flatMap { $0 > 0 ? "\($0)" : nil }
            } total: { $0.penalties.flatMap { $0 > 0 ? "\($0)" : nil } }
        }
        .overlay(Rectangle().stroke(ink, lineWidth: CardInk.border))
    }

    // MARK: Rows

    private var holeRow: some View {
        HStack(spacing: 0) {
            label("HOLE", color: CardInk.palette.paper)
            ForEach(slots, id: \.self) { slot in
                switch slot {
                case .hole(let n):
                    Button { selectedHole = n } label: {
                        Text("\(n)")
                            .font(AppFont.monoNumeral)
                            .foregroundStyle(CardInk.palette.paper)
                            .frame(maxWidth: .infinity, minHeight: Self.headerHeight)
                            .background(n == selectedHole || n == highlightedHole
                                        ? CardInk.palette.flag.opacity(0.55) : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select hole \(n)")
                default:
                    Text(totalLabel(slot))
                        .font(AppFont.stamp).tracking(1)
                        .foregroundStyle(CardInk.palette.paper)
                        .frame(maxWidth: .infinity, minHeight: Self.headerHeight)
                }
            }
        }
        .background(ink)
    }

    private var scoreRow: some View {
        HStack(spacing: 0) {
            label("SCORE")
            ForEach(slots, id: \.self) { slot in
                Group {
                    switch slot {
                    case .hole(let n):
                        let col = model.columns[n - 1]
                        if let score = col.score {
                            ScoreMarkView(score: score, mark: .mark(toPar: col.toPar))
                        } else {
                            Color.clear
                        }
                    default:
                        handText(totals(slot).score.map(String.init), size: 18)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.scoreRowHeight, maxHeight: Self.scoreRowHeight)
                .background(tint(for: slot))
                .overlay(alignment: .trailing) { divider }
            }
        }
        .background(Color.white.opacity(0.45))
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.35)).frame(height: 1) }
    }

    private func textRow(_ title: String, height: CGFloat, hand: Bool = false, color: Color? = nil,
                         value: @escaping (ScorecardColumn) -> String?,
                         total: @escaping (ScorecardTotals) -> String?) -> some View {
        HStack(spacing: 0) {
            label(title)
            ForEach(slots, id: \.self) { slot in
                let text: String? = {
                    if case .hole(let n) = slot { return value(model.columns[n - 1]) }
                    return total(totals(slot))
                }()
                Group {
                    if hand {
                        handText(text, size: 15)
                    } else {
                        Text(text ?? "")
                            .font(.custom(AppFont.monoName, size: 11).weight(.bold))
                            .foregroundStyle(color ?? ink)
                            .tabularNumerals()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: height)
                .background(tint(for: slot))
                .overlay(alignment: .trailing) { divider }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.35)).frame(height: 1) }
    }

    // MARK: Cells

    private func label(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(AppFont.stamp).tracking(1.2)
            .foregroundStyle(color ?? ink)
            .padding(.leading, 8)
            .frame(width: Self.labelWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) { Rectangle().fill(color ?? ink).opacity(0.6).frame(width: 1) }
    }

    private func handText(_ text: String?, size: CGFloat) -> some View {
        Text(text ?? "")
            .font(CardInk.hand(size))
            .foregroundStyle(CardInk.graphite)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var divider: some View {
        Rectangle().fill(ink.opacity(0.25)).frame(width: 1)
    }

    private func totals(_ slot: Slot) -> ScorecardTotals {
        switch slot {
        case .out: return model.out
        case .inn: return model.inn
        default: return model.total
        }
    }

    private func totalLabel(_ slot: Slot) -> String {
        switch slot {
        case .out: return "OUT"
        case .inn: return "IN"
        case .tot: return "TOT"
        case .hole(let n): return "\(n)"
        }
    }

    /// OUT/IN/TOT get a light ink tint; the current or selected hole a faint flag tint.
    private func tint(for slot: Slot) -> Color {
        switch slot {
        case .out, .inn, .tot:
            return ink.opacity(0.07)
        case .hole(let n):
            return (n == selectedHole || n == highlightedHole)
                ? CardInk.palette.flag.opacity(0.13) : .clear
        }
    }
}

/// Handwritten score with its birdie/bogey mark.
struct ScoreMarkView: View {
    let score: Int
    let mark: ScoreMark

    var body: some View {
        ZStack {
            switch mark {
            case .circle:
                Circle().stroke(CardInk.graphite, lineWidth: 1.2).frame(width: 28, height: 28)
            case .doubleCircle:
                Circle().stroke(CardInk.graphite, lineWidth: 1.2).frame(width: 32, height: 32)
                Circle().stroke(CardInk.graphite, lineWidth: 1.2).frame(width: 25, height: 25)
            case .square:
                Rectangle().stroke(CardInk.graphite, lineWidth: 1.2).frame(width: 26, height: 26)
            case .doubleSquare:
                Rectangle().stroke(CardInk.graphite, lineWidth: 1.2).frame(width: 31, height: 31)
                Rectangle().stroke(CardInk.graphite, lineWidth: 1.2).frame(width: 24, height: 24)
            case .none:
                EmptyView()
            }
            Text("\(score)")
                .font(CardInk.hand(19))
                .foregroundStyle(CardInk.graphite)
        }
        .accessibilityLabel("\(score)")
    }
}
