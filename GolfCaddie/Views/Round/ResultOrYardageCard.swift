import SwiftUI

enum YardageCardStyle: Equatable {
    /// Hero over a FRONT / MID / BACK row (open wide, open portrait).
    case stacked(hero: CGFloat)
    /// Hero on the left, F / B on the right (book, landscape, iPhone, folded).
    case inline(hero: CGFloat)
}

/// Top of every panel: TO PIN yardage on the live hole, the result on a
/// finished hole, or "NOT TRACKED" on a hole that needs its score entered
/// (casual: the hole's current score while the grid edits it).
struct ResultOrYardageCard<Accessory: View>: View {
    typealias Style = YardageCardStyle

    let model: RoundPanelModel
    let style: Style
    /// Floating box (folded) instead of a ruled box inside a panel.
    var floating = false
    var linkCourse: () -> Void = {}
    /// Review's PUTTS stepper writes through these.
    var reviewActions = RoundPanelActions()
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.palette) private var palette

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardFrame(floating: floating,
                                border: showsNotTracked ? palette.red : palette.ink))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(InRoundAccessibilityID.yardage)
    }

    @ViewBuilder
    private var content: some View {
        if model.viewingLive {
            yardage // casual too: every casual board shows the yardage card
        } else if model.showsReviewResult {
            reviewResult
        } else if model.state == .pastTracked {
            result
        } else if model.showsRoundSoFar {
            casualEdit
        } else {
            notTracked
        }
    }

    // MARK: Live

    @ViewBuilder
    private var yardage: some View {
        let label = ["TO PIN", model.yardage?.sourceText].compactMap { $0 }.joined(separator: " · ")
        switch style {
        case let .stacked(hero):
            VStack(alignment: .leading, spacing: 4) {
                StampLabel(text: label)
                if let yardage = model.yardage {
                    heroText(yardage, size: hero)
                    HStack(spacing: 4) {
                        column("FRONT", yardage.front)
                        column("MID", yardage.middle)
                        column("BACK", yardage.back)
                    }
                    .padding(.top, 6)
                    .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
                } else {
                    unavailable
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        case let .inline(hero):
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    StampLabel(text: label)
                    if let yardage = model.yardage { heroText(yardage, size: hero) } else { unavailable }
                }
                Spacer(minLength: 4)
                if let yardage = model.yardage {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("F \(yardage.front)")
                        Text("B \(yardage.back)")
                    }
                    .font(RoundFont.mono(12))
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
                }
                accessory()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func heroText(_ yardage: RoundYardage, size: CGFloat) -> some View {
        Text("\(yardage.middle)")
            .font(RoundFont.serif(size))
            .foregroundStyle(palette.ink)
            .tabularNumerals()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel("\(yardage.middle) \(yardage.unit) to the pin")
    }

    private func column(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(RoundFont.mono(9)).foregroundStyle(palette.ink2)
            Text("\(value)").font(RoundFont.mono(16)).foregroundStyle(palette.ink).tabularNumerals()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var unavailable: some View {
        if model.needsCourseLink {
            Button(action: linkCourse) {
                Text("Link course ›")
                    .font(RoundFont.serifItalic(17))
                    .foregroundStyle(palette.flag)
                    .frame(minHeight: RoundChromeMetrics.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text("No green anchor")
                .font(RoundFont.serifItalic(15))
                .foregroundStyle(palette.ink3)
                .padding(.vertical, 6)
        }
    }

    private var showsNotTracked: Bool {
        !model.viewingLive && model.state == .entry && !model.showsRoundSoFar && !model.showsReviewResult
    }

    private var isStacked: Bool {
        if case .stacked = style { return true }
        return false
    }

    // MARK: Review (a finished round)

    @ViewBuilder
    private var reviewResult: some View {
        switch style {
        case let .stacked(hero):
            ReviewResultBlock(model: model, actions: reviewActions, stacked: true, hero: hero)
        case let .inline(hero):
            HStack(alignment: .center, spacing: 6) {
                // Folded keeps its PUTTS stepper in the action box.
                ReviewResultBlock(model: model, actions: reviewActions, stacked: false, hero: hero,
                                  showsStepper: model.layout != .folded)
                accessory()
            }
        }
    }

    // MARK: Past hole

    private var result: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                StampLabel(text: "FINISHED · EDITING")
                Text(model.resultText)
                    .font(RoundFont.serif(isStacked ? 30 : 26))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if model.mode.tracksShots {
                    Text("Tap a shot to move it or change its club.")
                        .font(RoundFont.serifItalic(13))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(10)
    }

    // MARK: Casual hole being edited

    private var casualEdit: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                StampLabel(text: "HOLE \(model.holeNumber) · EDITING")
                Text(model.resultText)
                    .font(RoundFont.serif(isStacked ? 30 : 26))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(10)
    }

    // MARK: Not tracked

    private var notTracked: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                StampLabel(text: model.notTrackedText, color: palette.red)
                Text("Add this hole's score by hand.")
                    .font(RoundFont.serifItalic(13))
                    .foregroundStyle(palette.ink)
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(10)
    }
}

extension ResultOrYardageCard where Accessory == EmptyView {
    init(model: RoundPanelModel, style: YardageCardStyle, floating: Bool = false,
         linkCourse: @escaping () -> Void = {}, reviewActions: RoundPanelActions = RoundPanelActions()) {
        self.init(model: model, style: style, floating: floating, linkCourse: linkCourse,
                  reviewActions: reviewActions) { EmptyView() }
    }
}

private struct CardFrame: ViewModifier {
    let floating: Bool
    let border: Color

    func body(content: Content) -> some View {
        if floating {
            content.chromeBox(border: border)
        } else {
            content.overlay(Rectangle().strokeBorder(border, lineWidth: RoundChromeMetrics.rule))
        }
    }
}
