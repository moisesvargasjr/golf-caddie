import SwiftUI

/// The open Duo held tall (Scorecard-Portrait mockup): the front nine on the
/// top page and the back nine below the hinge, each page half the window so
/// nothing straddles the fold.
struct ScorecardSplitView: View {
    let content: ScorecardContent
    @Binding var selectedHole: Int?

    /// Content keeps this far from the hinge line (same as the round screens).
    private static let hingeGutter = SafeChrome.hingeGutter
    private static let edge: CGFloat = 24

    var body: some View {
        // Insets from a reader that respects the safe area (one that ignores
        // it reports zero, and the header ran under the status bar).
        GeometryReader { safe in
            GeometryReader { proxy in
                let insets = safe.safeAreaInsets
                let half = proxy.size.height / 2
                let side = max(Self.edge, insets.leading, insets.trailing)
                VStack(spacing: 0) {
                    frontPage
                        .padding(.top, max(Self.edge, insets.top))
                        .padding(.bottom, Self.hingeGutter)
                        .padding(.horizontal, side)
                        .frame(height: half, alignment: .top)
                        .overlay(alignment: .bottom) { hingeRule }
                    backPage
                        .padding(.top, Self.hingeGutter + 4)
                        .padding(.bottom, max(Self.edge, insets.bottom))
                        .padding(.horizontal, side)
                        .frame(height: half, alignment: .top)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Pages

    private var frontPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            nineTitle(.front)
            ScorecardNineTable(nine: .front, content: content, metrics: .portrait, selectedHole: $selectedHole)
            HStack(alignment: .center, spacing: 12) {
                if let note = ScorecardText.needsEntryNote(content.model.holesNeedingEntry) {
                    Text(note)
                        .font(.custom(AppFont.serifName, size: 13).italic())
                        .foregroundStyle(CardInk.palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let pick = selectedHole.map(content.pick), content.hasActions(pick) {
                    ScorecardPickButtons(content: content, pick: pick, fontSize: 15)
                }
            }
            if let error = content.loadError {
                Text(error).font(CardInk.mono(9)).foregroundStyle(CardInk.palette.red)
            }
        }
    }

    private var backPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            nineTitle(.back)
            ScorecardNineTable(nine: .back, content: content, metrics: .portrait, selectedHole: $selectedHole)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ScorecardStatBox(title: "TOTAL", value: ScorecardText.number(content.model.total.score))
                    .accessibilityIdentifier("scorecard.stat.total")
                ScorecardStatBox(title: "TO PAR", value: ScorecardText.toPar(content.model.grossToPar))
                ScorecardStatBox(title: "PUTTS", value: ScorecardText.number(content.model.total.putts))
                ScorecardStatBox(title: "SCORED", value: "\(content.model.scoredCount)/18")
            }
            .frame(height: 76)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ScorecardTitleBlock(title: content.courseName, subtitle: content.shortSubtitle,
                                titleSize: 26, subtitleSize: 10)
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

    private func nineTitle(_ nine: ScorecardNine) -> some View {
        Text(nine.title)
            .font(.custom(AppFont.serifName, size: 18).italic().weight(.bold))
            .foregroundStyle(CardInk.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// The dashed rule along the hinge between the two pages.
    private var hingeRule: some View {
        Line()
            .stroke(CardInk.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(height: 1.5)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// iPhone landscape (iPhone-Scorecard-Landscape mockup): a front-over-back
/// paper card with the totals — or the picked hole's action — in the header.
struct ScorecardLandscapeCard: View {
    let content: ScorecardContent
    @Binding var selectedHole: Int?

    var body: some View {
        // Inside the safe area: iPhone landscape insets clear the sensor
        // housing and the home indicator; the card adds a small margin. It
        // scrolls only if it can't fit (large text).
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                header
                ScorecardNineTable(nine: .front, content: content, metrics: .landscape,
                                   selectedHole: $selectedHole)
                ScorecardNineTable(nine: .back, content: content, metrics: .landscape,
                                   selectedHole: $selectedHole)
                if let error = content.loadError {
                    Text(error).font(CardInk.mono(9)).foregroundStyle(CardInk.palette.red)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(content.courseName)
                    .font(CardInk.serif(22)).foregroundStyle(CardInk.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(content.shortSubtitle)
                    .font(CardInk.mono(9)).tracking(0.8).foregroundStyle(CardInk.ink2)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let pick = selectedHole.map(content.pick), content.hasActions(pick) {
                ScorecardPickButtons(content: content, pick: pick)
            } else {
                stats
            }
            if let openMap = content.onOpenCourseMap {
                ScorecardCourseMapButton(action: openMap)
            }
            if let menu = content.roundMenu {
                menu
            }
            ScorecardOutlinedButton(title: content.dismissTitle, action: content.onDismiss)
                .accessibilityIdentifier("scorecard.dismiss")
        }
        .frame(minHeight: 44)
    }

    private var stats: some View {
        HStack(spacing: 14) {
            stat("TOTAL", ScorecardText.number(content.model.total.score))
            stat("TO PAR", ScorecardText.toPar(content.model.grossToPar))
            stat("PUTTS", ScorecardText.number(content.model.total.putts))
            if let stamp = ScorecardText.needsEntryStamp(content.model.holesNeedingEntry) {
                Text(stamp).font(CardInk.mono(11)).foregroundStyle(CardInk.palette.red)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(CardInk.ink2)
            Text(value).foregroundStyle(CardInk.ink)
        }
        .font(CardInk.mono(11))
        .accessibilityElement(children: .combine)
    }
}
