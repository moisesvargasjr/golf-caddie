import SwiftUI

// The folded Duo (canvas Folded / Folded-Clear) and the iPhone (iPhone-Round,
// iPhone-Clear, iPhone-PastHole, iPhone-Landscape). Window coordinates, from
// `insets`. Questions and the score entry open as a sheet across the bottom
// on folded and iPhone portrait.

/// Duo folded: title across the top; yardage card bottom-left; two stacked
/// boxes on the right — Finish / + SHOT + PENALTY / ··· CARD hide on top,
/// the club list below. + PENALTY moves into ··· when the row isn't shown.
struct FoldedLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    static let boxWidth: CGFloat = 164
    static let actionBoxHeight: CGFloat = 190
    static let cardWidth: CGFloat = 244

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 16) {
                HoleTitleBar(model: model, actions: actions, style: .trailingCaption(size: 24))
                    .reportsChromeFrame("title")
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        CompassChromeButton(model: model, actions: actions)
                            .reportsChromeFrame("compass")
                        if model.state == .entry, !model.viewingLive {
                            NotTrackedTag(text: model.notTrackedText).padding(.top, 10)
                        }
                        Spacer(minLength: 0)
                        if !showsSheet { bottomLeftCard }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !showsSheet, model.state != .entry {
                        VStack(spacing: 10) {
                            actionBox.frame(height: Self.actionBoxHeight).reportsChromeFrame("actions")
                            if model.showsClubList {
                                ClubList(model: model, actions: actions, axis: .vertical(width: nil, rowStyle: true))
                                    .chromeBox()
                                    .reportsChromeFrame("clubs")
                            } else {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(width: Self.boxWidth)
                    }
                }
            }
            .padding(insets)
            if showsSheet {
                BottomQuestionSheet(model: model, actions: actions, bottomInset: insets.bottom)
                    .reportsChromeFrame("sheet")
            }
        }
    }

    private var showsSheet: Bool { model.question != nil || model.state == .entry }

    @ViewBuilder
    private var bottomLeftCard: some View {
        if model.hasSelection {
            SelectedShotCard(model: model, actions: actions, compact: true, floating: true)
                .frame(maxWidth: Self.cardWidth)
                .reportsChromeFrame("card")
        } else {
            ResultOrYardageCard(model: model, style: .inline(hero: 50), floating: true,
                                linkCourse: actions.linkCourse)
                .frame(maxWidth: Self.cardWidth)
                .reportsChromeFrame("card")
        }
    }

    private var actionBox: some View {
        VStack(spacing: 6) {
            if model.isLiveHole {
                PrimaryActionButton(title: "Finish hole", fontSize: 17, minHeight: 44, action: actions.finishHole)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier(InRoundAccessibilityID.finishHole)
                if model.mode.tracksShots {
                    HStack(spacing: 5) {
                        OutlineActionButton(title: InRoundLabels.shot, isBusy: model.isMarking,
                                            action: actions.addShot)
                            .disabled(model.isMarking)
                            .accessibilityLabel("Log a shot here")
                            .accessibilityIdentifier(InRoundAccessibilityID.addShot)
                        OutlineActionButton(title: InRoundLabels.penalty, isAlert: true, action: actions.askPenalty)
                            .accessibilityLabel("Add a penalty")
                            .accessibilityIdentifier(InRoundAccessibilityID.addPenalty)
                    }
                }
            } else {
                PrimaryActionButton(title: model.backToLiveTitle, fontSize: 15, minHeight: 44,
                                    action: actions.backToLive)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier(InRoundAccessibilityID.backToLive)
            }
            HStack(spacing: 5) {
                RoundOverflowMenu(model: model, actions: actions, frame: .outline,
                                  includesPenalty: !(model.isLiveHole && model.mode.tracksShots))
                    .frame(maxWidth: .infinity)
                CardButton(actions: actions, frame: .outline, fontSize: 9)
                    .frame(maxWidth: .infinity)
                HideControlsButton(actions: actions, frame: .outline)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .chromeBox()
    }
}

/// iPhone portrait: title bar (with CARD and ···) across the top; one bottom
/// panel — yardage + hide, clubs scrolling sideways, + SHOT · + PEN · Finish.
struct PhonePortraitLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 10) {
                HoleTitleBar(model: model, actions: actions, style: .stacked(size: 20),
                             caption: model.compactCaption,
                             trailing: AnyView(HStack(spacing: 0) {
                                 CardButton(actions: actions, frame: .plain)
                                 RoundOverflowMenu(model: model, actions: actions, frame: .plain)
                             }))
                    .reportsChromeFrame("title")
                HStack(spacing: 8) {
                    CompassChromeButton(model: model, actions: actions)
                        .reportsChromeFrame("compass")
                    if model.state == .entry, !model.viewingLive {
                        NotTrackedTag(text: model.notTrackedText)
                    } else if model.mode.allowsHoldToAdd {
                        MapHintTag(text: "DRAG PINS · HOLD TO ADD")
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                if !showsSheet {
                    if model.hasSelection {
                        SelectedShotCard(model: model, actions: actions, compact: true, floating: true)
                            .reportsChromeFrame("selection")
                    }
                    panel.reportsChromeFrame("panel")
                }
            }
            .padding(insets)
            if showsSheet {
                BottomQuestionSheet(model: model, actions: actions, bottomInset: insets.bottom)
                    .reportsChromeFrame("sheet")
            }
        }
    }

    private var showsSheet: Bool { model.question != nil || model.state == .entry }

    private var panel: some View {
        VStack(spacing: 8) {
            ResultOrYardageCard(model: model, style: .inline(hero: 52), linkCourse: actions.linkCourse) {
                HideControlsButton(actions: actions, frame: .outline)
            }
            if model.showsClubList {
                ClubList(model: model, actions: actions, axis: .horizontal)
            }
            ActionRow(model: model, actions: actions, style: .singleRow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .chromeBox(opacity: RoundChromeMetrics.panelOpacity, shadow: RoundChromeMetrics.panelShadow)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.panel)
    }
}

/// iPhone landscape: title top-left; compass · hide · CARD · ··· bottom-left;
/// the 300 pt panel on the right with a 68 pt club list.
struct PhoneLandscapeLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    static let panelWidth: CGFloat = 300
    static let railWidth: CGFloat = 68

    var body: some View {
        ZStack(alignment: .topLeading) {
            HoleTitleBar(model: model, actions: actions, style: .inline(size: 20), caption: model.compactCaption)
                .fixedSize()
                .reportsChromeFrame("title")
                .pinned(.topLeading, insets: insets)

            HStack(spacing: 6) {
                CompassChromeButton(model: model, actions: actions)
                HideControlsButton(actions: actions)
                CardButton(actions: actions)
                RoundOverflowMenu(model: model, actions: actions)
            }
            .fixedSize()
            .reportsChromeFrame("cluster")
            .pinned(.bottomLeading, insets: insets)

            CommandPanel(model: model, actions: actions,
                         columnStyle: PanelColumn.Style(card: .inline(hero: 48), spacing: 8, padding: 10,
                                                        primaryHeight: 52, primaryFont: 18,
                                                        showsHint: false, showsListTitle: false),
                         railWidth: Self.railWidth)
                .frame(width: Self.panelWidth)
                .frame(maxHeight: .infinity)
                .reportsChromeFrame("panel")
                .padding(insets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// Folded / iPhone portrait with the controls hidden: "H8 · P4 · TAP MAP FOR
/// CONTROLS" top-left and "148 SHOW" bottom-left.
struct CompactHiddenChrome: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    var body: some View {
        ZStack {
            MapHintTag(text: "\(model.shortCaption) · TAP MAP FOR CONTROLS", size: 11)
                .fixedSize()
                .reportsChromeFrame("hiddenCaption")
                .pinned(.topLeading, insets: insets)
            ShowControlsPill(model: model, actions: actions)
                .fixedSize()
                .reportsChromeFrame("hiddenPill")
                .pinned(.bottomLeading, insets: insets)
        }
    }
}

/// "NOT TRACKED · YOU STARTED ON HOLE 7" on the map (iPhone-PastHole).
struct NotTrackedTag: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        StampLabel(text: text, size: 10, color: palette.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(palette.paper.opacity(0.9))
    }
}

/// A hint stamped on the map on a paper tag, so it reads over satellite
/// imagery (canvas iPhone-Round: "DRAG PINS · HOLD TO ADD").
struct MapHintTag: View {
    let text: String
    var size: CGFloat = 9
    @Environment(\.palette) private var palette

    var body: some View {
        StampLabel(text: text, size: size, color: palette.ink2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(palette.paper.opacity(0.9))
    }
}

/// Paper sheet across the bottom: putts, penalty, or the score entry.
struct BottomQuestionSheet: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let bottomInset: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if model.question == .putts {
                PuttsQuestion(model: model, actions: actions, presentation: .sheet)
            } else if model.question == .penalty {
                PenaltyQuestion(model: model, actions: actions, presentation: .sheet)
            } else {
                HandScoreEntry(model: model, actions: actions, presentation: .sheet)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, SafeChrome.edgeInset)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .background(palette.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(model.question == .penalty ? palette.red : palette.ink)
                .frame(height: RoundChromeMetrics.rule)
        }
        .compositingGroup()
        .shadow(color: palette.cardShadow.color.opacity(0.7), radius: 0, x: 0, y: -4)
    }
}
