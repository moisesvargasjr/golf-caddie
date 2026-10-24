import SwiftUI

/// The course pose's controls over the full-bleed map (`RoundMapScreen` with
/// a `RoundMapCourse` showing). Window coordinates, from `insets` (24 pt
/// edges, 36 pt corners — SafeChrome), and every box reports its frame so
/// the map fits the course into what is left.
///
/// - Open Duo (board Course-Open): ‹ CARD and the course title top-left,
///   the legend + "TAP A HOLE TO REVIEW IT" bottom-right. Both corners keep
///   off the hinge in open portrait and book pose.
/// - Folded / iPhone (not designed yet — fallback): a title bar across the
///   top and a strip of hole chips along the bottom (portrait) or down the
///   right edge (landscape), so a hole can be picked without hunting for its
///   badge on a small map.
struct CourseMapChrome: View {
    let content: CourseMapContent
    let style: CourseMapChromeStyle
    let insets: EdgeInsets
    let onOpenHole: (Int) -> Void
    let onCard: () -> Void

    static let sideStripWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch style {
            case .openDuo:
                HStack(spacing: 8) {
                    CourseCardButton(frame: .box, action: onCard)
                    CourseTitleBox(content: content, compact: false)
                }
                .fixedSize()
                .reportsChromeFrame("courseTitle")
                .pinned(.topLeading, insets: insets)

                CourseMapLegend(content: content)
                    .fixedSize()
                    .reportsChromeFrame("courseLegend")
                    .pinned(.bottomTrailing, insets: insets)
            case .bottomStrip:
                compactTitle
                    .padding(.top, insets.top)
                    .padding(.horizontal, insets.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                CourseHoleStrip(content: content, axis: .horizontal, onOpenHole: onOpenHole)
                    .reportsChromeFrame("courseStrip")
                    .padding(.bottom, insets.bottom)
                    .padding(.horizontal, insets.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            case .sideStrip:
                compactTitle
                    .fixedSize()
                    .pinned(.topLeading, insets: insets)

                CourseHoleStrip(content: content, axis: .vertical, onOpenHole: onOpenHole)
                    .frame(width: Self.sideStripWidth)
                    .reportsChromeFrame("courseStrip")
                    .padding(insets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CourseMapAccessibilityID.chrome)
    }

    /// ‹ CARD + the course name in one bar (folded / iPhone).
    private var compactTitle: some View {
        HStack(spacing: 0) {
            CourseCardButton(frame: .plain, action: onCard)
            CourseTitleBox(content: content, compact: true)
            Spacer(minLength: 0)
        }
        .chromeBox()
        .reportsChromeFrame("courseTitle")
    }
}

/// ‹ CARD — back to the round's card.
struct CourseCardButton: View {
    var frame: ChromeFrame = .box
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text("‹ CARD")
                .font(RoundFont.mono(10))
                .tracking(0.8)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 12)
                .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
                .chromeFrame(frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to the scorecard")
        .accessibilityIdentifier(CourseMapAccessibilityID.backToCard)
    }
}

/// "Native Oaks" over "OCT 18 · 82 (+10) · YOUR SHOTS ON EVERY HOLE".
struct CourseTitleBox: View {
    let content: CourseMapContent
    let compact: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(content.title)
                .font(RoundFont.serifItalic(compact ? 16 : 18).weight(.bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            StampLabel(text: content.caption, size: compact ? 8 : 9)
        }
        .padding(.horizontal, compact ? 6 : 12)
        .padding(.vertical, 4)
        .frame(minHeight: RoundChromeMetrics.minTap)
        .modifier(BoxedIf(boxed: !compact))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(CourseMapAccessibilityID.title)
    }
}

private struct BoxedIf: ViewModifier {
    let boxed: Bool

    func body(content: Content) -> some View {
        if boxed { content.chromeBox(shadow: 0) } else { content }
    }
}

/// PAR OR BETTER · BOGEY+ · TAP A HOLE TO REVIEW IT (Course-Open, bottom-right).
struct CourseMapLegend: View {
    let content: CourseMapContent
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            if content.hasContent {
                swatch(Color(uiColor: HoleMapColors.cream), CourseMapText.parOrBetter)
                swatch(Color(uiColor: HoleMapColors.amber), CourseMapText.bogeyPlus)
                if !content.hasCourseAnchors { StampLabel(text: CourseMapText.shotsOnlyHint, color: palette.ink) }
                StampLabel(text: CourseMapText.tapHint, color: palette.ink)
            } else {
                StampLabel(text: CourseMapText.emptyHint, color: palette.ink)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: RoundChromeMetrics.minTap)
        .chromeBox(shadow: 0)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(CourseMapAccessibilityID.legend)
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 18, height: 3)
                .overlay(Rectangle().stroke(palette.ink, lineWidth: 1))
            StampLabel(text: text, color: palette.ink)
        }
    }
}

/// Folded / iPhone fallback: every drawn hole as a 44 pt chip (number +
/// score, over-par in red), scrolling sideways or down. A tap glides in.
struct CourseHoleStrip: View {
    let content: CourseMapContent
    let axis: Axis
    let onOpenHole: (Int) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StampLabel(text: hint, size: 8)
                .padding(.horizontal, 6)
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                if axis == .horizontal {
                    HStack(spacing: 4) { chips }
                } else {
                    VStack(spacing: 4) { chips }
                }
            }
        }
        .padding(6)
        .chromeBox()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CourseMapAccessibilityID.strip)
    }

    private var hint: String {
        guard content.hasContent else { return CourseMapText.emptyHint }
        return axis == .horizontal ? CourseMapText.tapHint : "HOLES"
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(content.outlines) { outline in
            Button { onOpenHole(outline.number) } label: { chip(outline) }
                .buttonStyle(.plain)
                .accessibilityLabel(HoleMapAccessibility.holeBadgeLabel(number: outline.number,
                                                                        score: outline.score))
                .accessibilityIdentifier(CourseMapAccessibilityID.stripHole(outline.number))
        }
    }

    private func chip(_ outline: CourseHoleOutline) -> some View {
        HStack(spacing: 3) {
            Text("\(outline.number)")
                .font(RoundFont.mono(11))
                .foregroundStyle(palette.ink)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
            if let score = outline.score {
                Text("\(score)")
                    .font(RoundFont.serif(14))
                    .foregroundStyle(outline.isOverPar ? palette.red : palette.ink)
                    .tabularNumerals()
            }
        }
        .padding(.horizontal, 6)
        .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
