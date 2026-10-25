import SwiftUI

/// The command panel's left column, shared by every side-panel layout (open
/// wide, open portrait, book, iPhone landscape): result/yardage card, then
/// the shot list (or a question / the score entry), then the actions.
struct PanelColumn: View {
    struct Style: Equatable {
        var card: YardageCardStyle = .stacked(hero: 60)
        var spacing: CGFloat = 10
        var padding: CGFloat = 12
        var shotRowHeight: CGFloat = 40
        var primaryHeight: CGFloat = 56
        var primaryFont: CGFloat = 20
        var showsHint = true
        var showsListTitle = true
        /// Where the column's content sits when the box is taller than it.
        var alignment: Alignment = .top
        /// Size the box to its content instead of filling the height it is
        /// offered (open portrait); the lists scroll only once they run out.
        var hugsContent = false
        /// Casual score grid sizes (iPhone landscape is tighter).
        var scoreGrid: ScoreGrid.Metrics = .panel
    }

    let model: RoundPanelModel
    let actions: RoundPanelActions
    var style = Style()
    /// Which parts to draw (open portrait splits them around the hinge).
    var parts: Parts = .all

    struct Parts: OptionSet {
        let rawValue: Int
        static let card = Parts(rawValue: 1)
        /// The shot list (tracking) or the round so far (casual).
        static let list = Parts(rawValue: 2)
        /// Putts question / score grid / score entry (they take the list's place).
        static let ask = Parts(rawValue: 4)
        /// Penalty question, selected shot, or the actions.
        static let bottom = Parts(rawValue: 8)
        static let all: Parts = [.card, .list, .ask, .bottom]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            if parts.contains(.card) {
                ResultOrYardageCard(model: model, style: style.card, linkCourse: actions.linkCourse,
                                reviewActions: actions)
            }
            middle
            if parts.contains(.bottom) { bottom }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, maxHeight: style.hugsContent ? nil : .infinity, alignment: style.alignment)
    }

    /// The gap that pushes a question down to the actions; none when hugging.
    @ViewBuilder
    private var askSpacer: some View {
        if !style.hugsContent { Spacer(minLength: 0) }
    }

    @ViewBuilder
    private var middle: some View {
        if model.question == .putts {
            if parts.contains(.ask) {
                askSpacer
                PuttsQuestion(model: model, actions: actions)
            }
        } else if model.showsScoreGrid {
            if parts.contains(.ask) {
                askSpacer
                ScoreGrid(model: model, actions: actions, metrics: style.scoreGrid)
            }
        } else if model.state == .entry {
            if parts.contains(.ask) {
                askSpacer
                HandScoreEntry(model: model, actions: actions)
            }
        } else if parts.contains(.list) {
            if model.showsRoundSoFar {
                RoundScoresList(roundSoFar: model.roundSoFar, variant: .list, onPick: actions.openRoundHole,
                                rowHeight: style.shotRowHeight, fitsContent: style.hugsContent)
                    .frame(maxHeight: style.hugsContent ? nil : .infinity, alignment: .top)
            } else {
                ShotList(model: model, actions: actions, showsTitle: style.showsListTitle,
                         rowHeight: style.shotRowHeight, fitsContent: style.hugsContent)
                    .frame(maxHeight: style.hugsContent ? nil : .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if model.isAsking {
            EmptyView()
        } else if model.question == .penalty {
            PenaltyQuestion(model: model, actions: actions)
        } else if model.hasSelection {
            SelectedShotCard(model: model, actions: actions)
        } else {
            if style.showsHint, model.showsPanelHint {
                PanelHint(text: model.hintText)
            }
            ActionRow(model: model, actions: actions,
                      style: .stacked(primaryHeight: style.primaryHeight, primaryFont: style.primaryFont))
        }
    }
}

/// "+1 · 2 SCORED" · CARD · ··· along the top of the portrait / book panel.
struct PanelHeaderRow: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(model.roundScoreText ?? "NO HOLES SCORED")
                .font(RoundFont.mono(11))
                .foregroundStyle(palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            CardButton(actions: actions, title: model.cardTitle, frame: .outline)
            RoundOverflowMenu(model: model, actions: actions, frame: .outline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }
}

/// The paper panel: left column + the club rail down its right edge (or, with
/// `clubStrip`, a sideways club row above the column).
struct CommandPanel<Header: View>: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var columnStyle = PanelColumn.Style()
    var parts: PanelColumn.Parts = .all
    var railWidth: CGFloat = 84
    var showsRail = true
    var clubStrip = false
    @ViewBuilder var header: () -> Header
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            header()
            if clubStrip, model.showsClubList {
                ClubList(model: model, actions: actions, axis: .horizontal, cellHeight: 52)
                    .padding([.horizontal, .top], columnStyle.padding)
            }
            HStack(spacing: 0) {
                PanelColumn(model: model, actions: actions, style: columnStyle, parts: parts)
                if showsRail, !clubStrip, model.showsClubList {
                    ClubList(model: model, actions: actions, axis: .vertical(width: railWidth, rowStyle: false))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(palette.ink).frame(width: RoundChromeMetrics.rule)
                        }
                }
            }
        }
        .chromeBox(opacity: RoundChromeMetrics.panelOpacity, shadow: RoundChromeMetrics.panelShadow)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.panel)
    }
}

extension CommandPanel where Header == EmptyView {
    init(model: RoundPanelModel, actions: RoundPanelActions, columnStyle: PanelColumn.Style = .init(),
         parts: PanelColumn.Parts = .all, railWidth: CGFloat = 84, showsRail: Bool = true,
         clubStrip: Bool = false) {
        self.init(model: model, actions: actions, columnStyle: columnStyle, parts: parts,
                  railWidth: railWidth, showsRail: showsRail, clubStrip: clubStrip) { EmptyView() }
    }
}
