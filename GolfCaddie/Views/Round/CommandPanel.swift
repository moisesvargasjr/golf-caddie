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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment)
    }

    @ViewBuilder
    private var middle: some View {
        if model.question == .putts {
            if parts.contains(.ask) {
                Spacer(minLength: 0)
                PuttsQuestion(model: model, actions: actions)
            }
        } else if model.showsScoreGrid {
            if parts.contains(.ask) {
                Spacer(minLength: 0)
                ScoreGrid(model: model, actions: actions, metrics: style.scoreGrid)
            }
        } else if model.state == .entry {
            if parts.contains(.ask) {
                Spacer(minLength: 0)
                HandScoreEntry(model: model, actions: actions)
            }
        } else if parts.contains(.list) {
            if model.showsRoundSoFar {
                RoundScoresList(roundSoFar: model.roundSoFar, variant: .list, onPick: actions.openRoundHole,
                                rowHeight: style.shotRowHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ShotList(model: model, actions: actions, showsTitle: style.showsListTitle,
                         rowHeight: style.shotRowHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
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

/// The paper panel: left column + the club rail down its right edge.
struct CommandPanel<Header: View>: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var columnStyle = PanelColumn.Style()
    var parts: PanelColumn.Parts = .all
    var railWidth: CGFloat = 84
    var showsRail = true
    @ViewBuilder var header: () -> Header
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            header()
            HStack(spacing: 0) {
                PanelColumn(model: model, actions: actions, style: columnStyle, parts: parts)
                if showsRail, model.showsClubList {
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
         parts: PanelColumn.Parts = .all, railWidth: CGFloat = 84, showsRail: Bool = true) {
        self.init(model: model, actions: actions, columnStyle: columnStyle, parts: parts,
                  railWidth: railWidth, showsRail: showsRail) { EmptyView() }
    }
}
