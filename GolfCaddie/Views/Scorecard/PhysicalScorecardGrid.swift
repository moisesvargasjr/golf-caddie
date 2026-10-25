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

/// The traditional card's 22-column grid (Scorecard-Open / Round-Open
/// mockups): label · 1–9 · OUT · 10–18 · IN · TOT. Tapping anywhere in a
/// hole's column selects it; the SCORE cell is the hole's VoiceOver element.
struct PhysicalScorecardGrid: View {
    let model: ScorecardModel
    let currentHole: Int?
    let selectedHole: Int?
    let onSelect: (Int) -> Void

    static let labelWidth: CGFloat = 92

    private enum Slot: Hashable {
        case hole(Int), out, inn, tot
    }

    private enum RowRule { case none, hair, strong }

    private var slots: [Slot] {
        (1...9).map(Slot.hole) + [.out] + (10...18).map(Slot.hole) + [.inn, .tot]
    }

    private let ink = CardInk.ink

    var body: some View {
        VStack(spacing: 0) {
            holeRow
            textRow("YARDS", height: 26, font: CardInk.mono(10), color: CardInk.ink2,
                    value: { $0.yards.map(String.init) }, total: { totals($0).yards.map(String.init) })
            textRow("PAR", height: 28, rowRule: .strong, font: CardInk.serif(14),
                    value: { $0.par.map(String.init) }, total: { totals($0).par.map(String.init) ?? "—" })
            if model.hasStrokeIndex {
                textRow("HCP", height: 26, font: CardInk.mono(10), color: CardInk.ink2,
                        value: { $0.strokeIndex.map(String.init) }, total: { _ in nil })
            }
            scoreRow
            puttsRow
            // ● fairway hit; a miss shows its arrow; par 3s stay blank. The
            // total is hits / holes answered ("7/10"), blank before any.
            textRow("FIR", height: 26, font: .system(size: 12),
                    value: { $0.teeShot?.glyph }, total: firTotal)
            textRow("GIR", height: 26, font: .system(size: 12),
                    value: { $0.gir == true ? "●" : nil }, total: { "\(girTotal($0))" })
            textRow("PEN", height: 26, rowRule: .none, font: CardInk.mono(11), color: CardInk.palette.red,
                    value: { $0.penalties.flatMap { $0 > 0 ? "\($0)" : nil } },
                    total: { totals($0).penalties.flatMap { $0 > 0 ? "\($0)" : nil } })
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: CardInk.border))
    }

    // MARK: Rows

    private var holeRow: some View {
        HStack(spacing: 0) {
            label("HOLE", color: CardInk.palette.paper)
            ForEach(slots, id: \.self) { slot in
                cell(slot, height: 30, ruleColor: CardInk.palette.paper.opacity(0.25)) {
                    Text(slotTitle(slot))
                        .font(CardInk.serif(15))
                        .foregroundStyle(CardInk.palette.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .background(ink, ignoresSafeAreaEdges: [])
        .accessibilityHidden(true)
    }

    private var scoreRow: some View {
        HStack(spacing: 0) {
            label("SCORE", size: 11)
            ForEach(slots, id: \.self) { slot in
                scoreCell(slot)
            }
        }
        .background(CardInk.scoreRow, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { rule(.hair) }
    }

    @ViewBuilder
    private func scoreCell(_ slot: Slot) -> some View {
        if case let .hole(n) = slot {
            let column = model.columns[n - 1]
            cell(slot, height: 46) {
                ScorecardScoreGlyph(cell: .resolve(column, currentHole: currentHole),
                                    font: CardInk.hand(24), size: 28,
                                    nowColor: CardInk.palette.flag)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ScorecardText.accessibilityLabel(column, currentHole: currentHole))
            .accessibilityAddTraits(n == selectedHole ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { onSelect(n) }
            .accessibilityIdentifier("scorecard.hole.\(n)")
        } else {
            cell(slot, height: 46) {
                Text(totals(slot).score.map(String.init) ?? "")
                    .font(CardInk.serif(16)).foregroundStyle(ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ScorecardText.totalAccessibilityLabel(totalName(slot), totals(slot)))
            .accessibilityIdentifier("scorecard.total.\(slotTitle(slot).lowercased())")
        }
    }

    private var puttsRow: some View {
        HStack(spacing: 0) {
            label("PUTTS")
            ForEach(slots, id: \.self) { slot in
                cell(slot, height: 30) {
                    if case let .hole(n) = slot {
                        Text(model.columns[n - 1].putts.map(String.init) ?? "")
                            .font(CardInk.hand(20)).foregroundStyle(CardInk.graphite)
                    } else {
                        Text(totals(slot).putts.map(String.init) ?? "")
                            .font(CardInk.serif(14)).foregroundStyle(ink)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { rule(.hair) }
        .accessibilityHidden(true)
    }

    private func textRow(_ title: String, height: CGFloat, rowRule: RowRule = .hair, font: Font,
                         color: Color = CardInk.ink,
                         value: @escaping (ScorecardColumn) -> String?,
                         total: @escaping (Slot) -> String?) -> some View {
        HStack(spacing: 0) {
            label(title)
            ForEach(slots, id: \.self) { slot in
                cell(slot, height: height) {
                    Text(text(for: slot, value: value, total: total))
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .tabularNumerals()
                }
            }
        }
        .overlay(alignment: .bottom) { rule(rowRule) }
        .accessibilityHidden(true)
    }

    private func text(for slot: Slot, value: (ScorecardColumn) -> String?, total: (Slot) -> String?) -> String {
        if case let .hole(n) = slot { return value(model.columns[n - 1]) ?? "" }
        return total(slot) ?? ""
    }

    // MARK: Cells

    private func cell<Content: View>(_ slot: Slot, height: CGFloat,
                                     ruleColor: Color = CardInk.ink.opacity(0.2),
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(wash(slot), ignoresSafeAreaEdges: [])
            .overlay(alignment: .leading) { Rectangle().fill(ruleColor).frame(width: 1) }
            .contentShape(Rectangle())
            .onTapGesture { if case let .hole(n) = slot { onSelect(n) } }
    }

    private func label(_ text: String, size: CGFloat = 10, color: Color = CardInk.ink) -> some View {
        Text(text)
            .font(CardInk.mono(size)).tracking(0.8)
            .foregroundStyle(color)
            .padding(.leading, 8)
            .frame(width: Self.labelWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) { Rectangle().fill(color).frame(width: 1.5) }
    }

    @ViewBuilder
    private func rule(_ rowRule: RowRule) -> some View {
        switch rowRule {
        case .none: EmptyView()
        case .hair: Rectangle().fill(ink.opacity(0.2)).frame(height: 1)
        case .strong: Rectangle().fill(ink).frame(height: 1.5)
        }
    }

    /// OUT/IN/TOT get a light ink tint; the selected hole a faint flag tint.
    private func wash(_ slot: Slot) -> Color {
        switch slot {
        case .out, .inn, .tot: return ink.opacity(0.08)
        case let .hole(n): return n == selectedHole ? CardInk.palette.flag.opacity(0.14) : .clear
        }
    }

    private func totals(_ slot: Slot) -> ScorecardTotals {
        switch slot {
        case .out: return model.out
        case .inn: return model.inn
        default: return model.total
        }
    }

    private func girTotal(_ slot: Slot) -> Int {
        switch slot {
        case .out: return model.girCount(.front)
        case .inn: return model.girCount(.back)
        default: return model.girCount
        }
    }

    private func firTotal(_ slot: Slot) -> String? {
        let nine: ScorecardNine? = switch slot {
        case .out: .front
        case .inn: .back
        default: nil
        }
        return model.firText(nine)
    }

    private func slotTitle(_ slot: Slot) -> String {
        switch slot {
        case .out: return "OUT"
        case .inn: return "IN"
        case .tot: return "TOT"
        case let .hole(n): return "\(n)"
        }
    }

    private func totalName(_ slot: Slot) -> String {
        switch slot {
        case .out: return "Out"
        case .inn: return "In"
        default: return "Total"
        }
    }
}
