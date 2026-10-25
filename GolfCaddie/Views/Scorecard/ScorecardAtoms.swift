import SwiftUI

// Small pieces every scorecard variant shares, drawn from the Duo v2 mockups
// (always the light paper look, whatever the app theme).

extension CardInk {
    /// The SCORE row's lighter stock on the traditional card.
    static let scoreRow = Color.card(light: 0xFBF6EA, dark: 0x2E4A3A)
    static var ink: Color { palette.ink }
    static var ink2: Color { palette.ink2 }

    static func serif(_ size: CGFloat) -> Font { .custom(AppFont.serifName, size: size).weight(.bold) }
    static func mono(_ size: CGFloat) -> Font { .custom(AppFont.monoName, size: size).weight(.bold) }
}

/// Lays children out in one row: an optional fixed-width first child, then the
/// rest sharing the remaining width by `fractions` (CSS `fr` columns).
struct FractionalRow: Layout {
    var fixedLeading: CGFloat = 0
    let fractions: [CGFloat]

    /// Widths for [fixed?] + fractions; the fixed column is included only
    /// when `fixedLeading > 0`.
    static func widths(total: CGFloat, fixedLeading: CGFloat, fractions: [CGFloat]) -> [CGFloat] {
        let rest = max(0, total - fixedLeading)
        let sum = fractions.reduce(0, +)
        let shares = fractions.map { sum > 0 ? rest * $0 / sum : 0 }
        return fixedLeading > 0 ? [fixedLeading] + shares : shares
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let widths = Self.widths(total: width, fixedLeading: fixedLeading, fractions: fractions)
        let height = subviews.indices.map { i in
            subviews[i].sizeThatFits(ProposedViewSize(width: widths[safe: i] ?? 0, height: proposal.height)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.widths(total: bounds.width, fixedLeading: fixedLeading, fractions: fractions)
        var x = bounds.minX
        for (i, subview) in subviews.enumerated() {
            let w = widths[safe: i] ?? 0
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// A score with its relative-to-par mark: circle = birdie, double circle =
/// eagle or better, square = bogey, double square = double bogey or worse.
struct ScoreMarkView: View {
    let score: Int
    let mark: ScoreMark
    var font: Font = CardInk.hand(19)
    /// Side of the single circle; the other marks scale from it.
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            switch mark {
            case .circle:
                Circle().stroke(CardInk.ink, lineWidth: 1.5).frame(width: size, height: size)
            case .doubleCircle:
                Circle().stroke(CardInk.ink, lineWidth: 1.5).frame(width: size + 5, height: size + 5)
                Circle().stroke(CardInk.ink, lineWidth: 1.5).frame(width: size - 3, height: size - 3)
            case .square:
                Rectangle().stroke(CardInk.ink, lineWidth: 1.5).frame(width: size - 2, height: size - 2)
            case .doubleSquare:
                Rectangle().stroke(CardInk.ink, lineWidth: 1.5).frame(width: size + 3, height: size + 3)
                Rectangle().stroke(CardInk.ink, lineWidth: 1.5).frame(width: size - 4, height: size - 4)
            case .none:
                EmptyView()
            }
            Text("\(score)")
                .font(font)
                .foregroundStyle(CardInk.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityLabel("\(score)")
    }
}

/// One score cell's contents: the marked score, ADD, NOW, NP or nothing.
struct ScorecardScoreGlyph: View {
    let cell: ScorecardCell
    var font: Font = CardInk.serif(18)
    var size: CGFloat = 30
    /// NOW is flag-red on the traditional card, ink elsewhere.
    var nowColor: Color = CardInk.ink2

    var body: some View {
        switch cell {
        case let .score(score, mark):
            ScoreMarkView(score: score, mark: mark, font: font, size: size)
        case .add:
            tag("ADD", color: CardInk.palette.red)
        case .now:
            tag("NOW", color: nowColor)
        case .notPlayed:
            NotPlayedMark()
        case .blank:
            Color.clear
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(CardInk.mono(9)).tracking(0.6).foregroundStyle(color)
    }
}

/// Outlined mono button (‹ HOLE 8, MAP, BACK TO MAP, ‹ LOGBOOK).
struct ScorecardOutlinedButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CardInk.mono(10)).tracking(0.8)
                .foregroundStyle(CardInk.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(Rectangle().strokeBorder(CardInk.ink, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// NP struck through corner to corner: not played, distinct from ADD.
struct NotPlayedMark: View {
    var body: some View {
        Text("NP")
            .font(CardInk.mono(9)).tracking(0.6)
            .foregroundStyle(CardInk.ink2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { geo in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(CardInk.ink.opacity(0.6), lineWidth: 1.5)
                }
            }
            .accessibilityLabel("not played")
    }
}

/// A picked hole's CTA plus its outlined second choice (MARK NOT PLAYED /
/// UNDO NOT PLAYED) side by side; nothing when the pick has neither.
struct ScorecardPickButtons: View {
    let content: ScorecardContent
    let pick: ScorecardPick
    var fontSize: CGFloat = 16
    var minHeight: CGFloat = 44
    var expands = false

    var body: some View {
        let title = content.ctaTitle(pick)
        let secondary = pick.secondary
        if title != nil || secondary != nil {
            HStack(spacing: 8) {
                if let title {
                    ScorecardFilledButton(title: title, fontSize: fontSize, minHeight: minHeight,
                                          expands: expands) { content.onPick(pick) }
                        .accessibilityIdentifier("scorecard.cta")
                }
                if let secondary {
                    Button { content.onSecondary(secondary) } label: {
                        Text(secondary.title)
                            .font(CardInk.mono(10)).tracking(0.8)
                            .foregroundStyle(CardInk.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: expands ? .infinity : nil, minHeight: minHeight)
                            .overlay(Rectangle().strokeBorder(CardInk.ink, lineWidth: CardInk.border))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(secondary.accessibilityLabel)
                    .accessibilityIdentifier("scorecard.secondary")
                }
            }
        }
    }
}

/// Filled ink CTA ("Add hole 4 score ›", "Open hole 7 on the map ›").
struct ScorecardFilledButton: View {
    let title: String
    var fontSize: CGFloat = 16
    var minHeight: CGFloat = 44
    var expands = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CardInk.serif(fontSize))
                .foregroundStyle(CardInk.palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(maxWidth: expands ? .infinity : nil, minHeight: minHeight)
                .background(CardInk.ink, ignoresSafeAreaEdges: [])
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The card's MAP button for the whole-course view (PR 8); shown only when the
/// caller supplies a route.
struct ScorecardCourseMapButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "map").font(.system(size: 14, weight: .semibold))
                Text("MAP").font(CardInk.mono(10)).tracking(0.8)
            }
            .foregroundStyle(CardInk.palette.paper)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(CardInk.ink, ignoresSafeAreaEdges: [])
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See your round on the course map")
        .accessibilityIdentifier("scorecard.courseMap")
    }
}

/// Bordered stat: label over a big serif number (and an optional sub-line).
struct ScorecardStatBox: View {
    let title: String
    let value: String
    var sub: String? = nil
    var subColor: Color = CardInk.ink2
    var valueSize: CGFloat = 28
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).font(CardInk.mono(9)).foregroundStyle(CardInk.ink2)
            Text(value).font(CardInk.serif(valueSize)).foregroundStyle(CardInk.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let sub {
                Text(sub).font(CardInk.mono(11)).foregroundStyle(subColor)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: alignment == .leading ? .topLeading : .center)
        .overlay(Rectangle().strokeBorder(CardInk.ink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

/// Course name + mono status line, the header of the compact cards.
struct ScorecardTitleBlock: View {
    let title: String
    let subtitle: String
    var titleSize: CGFloat = 24
    var subtitleSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(CardInk.serif(titleSize)).foregroundStyle(CardInk.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(subtitle).font(CardInk.mono(subtitleSize)).tracking(0.8).foregroundStyle(CardInk.ink2)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The flag-in-a-ring badge on the traditional card's header.
struct ScorecardFlagBadge: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(CardInk.ink, lineWidth: 2)
            Canvas { context, size in
                let s = size.width / 24
                var pole = Path()
                pole.move(to: CGPoint(x: 8 * s, y: 21 * s))
                pole.addLine(to: CGPoint(x: 8 * s, y: 3 * s))
                context.stroke(pole, with: .color(CardInk.ink), lineWidth: 2 * s)
                var flag = Path()
                flag.move(to: CGPoint(x: 8 * s, y: 3 * s))
                flag.addLine(to: CGPoint(x: 19 * s, y: 7 * s))
                flag.addLine(to: CGPoint(x: 8 * s, y: 11 * s))
                flag.closeSubpath()
                context.fill(flag, with: .color(CardInk.palette.flag))
            }
            .frame(width: 22, height: 22)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// The selected / live column wash shared by the column-style cards.
struct ScorecardColumnWash: View {
    let isSelected: Bool
    let isLive: Bool

    var body: some View {
        if isSelected {
            CardInk.palette.flag.opacity(0.14)
                .overlay(Rectangle().strokeBorder(CardInk.palette.flag, lineWidth: 2))
        } else if isLive {
            CardInk.ink.opacity(0.08)
        } else {
            Color.clear
        }
    }
}
