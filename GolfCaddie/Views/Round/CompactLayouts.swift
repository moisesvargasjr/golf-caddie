import SwiftUI

// The folded Duo (canvas Folded / Folded-Clear) and the iPhone (iPhone-Round,
// iPhone-Clear, iPhone-PastHole, iPhone-Landscape). Window coordinates, from
// `insets`. Questions and the score entry open as a sheet across the bottom
// on folded and iPhone portrait.

/// Duo folded: title across the top; yardage card bottom-left; two stacked
/// boxes on the right — Finish / + SHOT + PENALTY / ··· CARD hide on top,
/// the club list below. + PENALTY moves into ··· when the row isn't shown.
/// Casual (canvas Folded-Casual): Finish fills the top box; the lower box is
/// the round's scores as squares. Review (Review-Folded-v2): one full-width
/// panel at the bottom: the result with PUTTS − n +, TEE ← ● → ↓ and GIR,
/// then ‹ CARD · + PEN · ··· · Next hole ›. No club list: a club strip slides
/// up above the panel only while a shot is selected (Review-Folded-v2-Shot).
struct FoldedLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets
    @Environment(\.palette) private var palette

    static let boxWidth: CGFloat = 164
    static let actionBoxHeight: CGFloat = 190
    static let cardWidth: CGFloat = 244

    var body: some View {
        if isReviewV2 {
            reviewBody
        } else {
            playBody
        }
    }

    /// A finished round's hole with its result (no sheet up): Review v2.
    private var isReviewV2: Bool {
        model.reviewNext != nil && !showsSheet && model.state != .entry
    }

    private var playBody: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 16) {
                HoleTitleBar(model: model, actions: actions, style: .trailingCaption(size: 24))
                    .reportsChromeFrame("title")
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        CompassChromeButton(model: model, actions: actions)
                            .reportsChromeFrame("compass")
                        if model.state == .entry, !model.viewingLive, !model.showsRoundSoFar {
                            NotTrackedTag(text: model.notTrackedText)
                                .reportsChromeFrame("hint")
                                .padding(.top, 10)
                        }
                        if showsSheet, model.reviewNext != nil {
                            reviewExits
                                .reportsChromeFrame("reviewExits")
                                .padding(.top, 10)
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
                            } else if model.showsRoundSoFar {
                                RoundScoresList(roundSoFar: model.roundSoFar, variant: model.layout.roundScoresVariant,
                                                onPick: actions.openRoundHole)
                                    .chromeBox()
                                    .reportsChromeFrame("scores")
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

    // MARK: Review v2

    private var reviewBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoleTitleBar(model: model, actions: actions, style: .trailingCaption(size: 24))
                .reportsChromeFrame("title")
            HStack(alignment: .top, spacing: 10) {
                CompassChromeButton(model: model, actions: actions)
                    .reportsChromeFrame("compass")
                if !model.hasSelection, model.showsPanelHint {
                    MapHintTag(text: "TAP A PIN FOR ITS CLUB · HOLD MAP TO ADD", size: 9)
                        .fixedSize()
                        .reportsChromeFrame("hint")
                }
            }
            Spacer(minLength: 0)
            if model.hasSelection {
                ReviewClubStrip(model: model, actions: actions)
                    .reportsChromeFrame("clubs")
            }
            reviewPanel
                .reportsChromeFrame("actions")
        }
        .padding(insets)
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    StampLabel(text: model.reviewResultLabel)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(model.reviewScoreText)
                            .font(RoundFont.serif(44))
                            .tabularNumerals()
                        if !model.reviewToParLabel.isEmpty {
                            Text(model.reviewToParLabel).font(RoundFont.mono(12))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hole \(model.holeNumber) score \(model.reviewScoreText)"
                                        + (model.reviewToParLabel.isEmpty ? "" : ", \(model.reviewToParLabel)"))
                }
                Spacer(minLength: 4)
                if model.showsPuttsStepper {
                    ReviewPuttsStepper(model: model, actions: actions, compact: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(InRoundAccessibilityID.reviewResult)
            if model.showsTeeGirRow {
                ReviewTeeGirRow(model: model, actions: actions)
                    .padding(.top, 8)
                    .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
            }
            HStack(spacing: 8) {
                if model.offersCourseMap {
                    CourseMapButton(actions: actions, frame: .outline, compact: true)
                }
                CardButton(actions: actions, title: model.cardTitle, frame: .outline, fontSize: 10)
                if model.state == .pastTracked {
                    OutlineActionButton(title: "+ PEN", isAlert: true, fontSize: 10,
                                        action: actions.askPenalty)
                        .frame(width: 72)
                        .accessibilityLabel("Add a penalty")
                        .accessibilityIdentifier(InRoundAccessibilityID.addPenalty)
                }
                RoundOverflowMenu(model: model, actions: actions, frame: .outline)
                if let next = model.reviewNext {
                    ReviewNextButton(next: next, actions: actions, fontSize: 19, minHeight: 48)
                }
            }
        }
        .padding(10)
        .chromeBox()
    }

    @ViewBuilder
    private var bottomLeftCard: some View {
        if model.hasSelection {
            SelectedShotCard(model: model, actions: actions, compact: true, floating: true)
                .frame(maxWidth: Self.cardWidth)
                .reportsChromeFrame("card")
        } else {
            ResultOrYardageCard(model: model, style: .inline(hero: 50), floating: true,
                                linkCourse: actions.linkCourse,
                                reviewActions: actions)
                .frame(maxWidth: Self.cardWidth)
                .reportsChromeFrame("card")
        }
    }

    private var actionBox: some View {
        VStack(spacing: 6) {
            if model.isLiveHole, !model.mode.tracksShots {
                FlagFinishButton(action: actions.finishHole)
            } else if model.isLiveHole {
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
            } else if let next = model.reviewNext {
                ReviewNextButton(next: next, actions: actions, fontSize: 16, minHeight: 44)
                    .frame(maxHeight: .infinity)
                if model.showsPuttsStepper {
                    ReviewPuttsStepper(model: model, actions: actions, compact: true)
                }
            } else {
                PrimaryActionButton(title: model.backToLiveTitle, fontSize: 15, minHeight: 44,
                                    action: actions.backToLive)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier(InRoundAccessibilityID.backToLive)
            }
            if model.reviewNext != nil {
                reviewRow
            } else {
                HStack(spacing: 5) {
                    RoundOverflowMenu(model: model, actions: actions, frame: .outline,
                                      includesPenalty: !(model.isLiveHole && model.mode.tracksShots))
                        .frame(maxWidth: .infinity)
                    CardButton(actions: actions, title: model.cardTitle, frame: .outline, fontSize: 9)
                        .frame(maxWidth: .infinity)
                    HideControlsButton(actions: actions, frame: .outline)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(6)
        .chromeBox()
    }

    /// Review with the score sheet up (an unscored hole): the sheet hides
    /// the boxes, so COURSE MAP, ‹ CARD and ··· stay here — otherwise the hole is a
    /// dead end on folded (‹ › only move between holes).
    private var reviewExits: some View {
        HStack(spacing: 5) {
            if model.offersCourseMap {
                CourseMapButton(actions: actions, frame: .outline, compact: true)
            }
            CardButton(actions: actions, title: model.cardTitle, frame: .outline, fontSize: 9)
            RoundOverflowMenu(model: model, actions: actions, frame: .outline)
        }
        .fixedSize()
        .padding(5)
        .chromeBox()
    }

    /// Review (Review-Folded): ‹ CARD · + PEN · ··· (round actions).
    private var reviewRow: some View {
        HStack(spacing: 5) {
            if model.offersCourseMap {
                CourseMapButton(actions: actions, frame: .outline, compact: true)
            }
            CardButton(actions: actions, title: model.cardTitle, frame: .outline, fontSize: 9)
                .frame(maxWidth: .infinity)
            if model.state == .pastTracked {
                OutlineActionButton(title: "+ PEN", isAlert: true, fontSize: 9, action: actions.askPenalty)
                    .accessibilityLabel("Add a penalty")
                    .accessibilityIdentifier(InRoundAccessibilityID.addPenalty)
            }
            RoundOverflowMenu(model: model, actions: actions, frame: .outline)
                .frame(maxWidth: .infinity)
        }
    }
}

/// iPhone portrait: title bar (with CARD and ···) across the top; one bottom
/// panel — yardage + hide, clubs scrolling sideways, + SHOT · + PEN · Finish.
/// Casual (canvas iPhone-Casual): score chips in the clubs' place, then
/// "YOUR ROUND +4 THRU 7" beside Finish; the score grid opens as the sheet.
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
                                 if model.offersCourseMap {
                                     CourseMapButton(actions: actions, frame: .plain, compact: true)
                                 }
                                 CardButton(actions: actions, title: model.cardTitle, frame: .plain)
                                 RoundOverflowMenu(model: model, actions: actions, frame: .plain)
                             }))
                    .reportsChromeFrame("title")
                HStack(spacing: 8) {
                    CompassChromeButton(model: model, actions: actions)
                        .reportsChromeFrame("compass")
                    if model.state == .entry, !model.viewingLive, !model.showsRoundSoFar {
                        NotTrackedTag(text: model.notTrackedText)
                            .reportsChromeFrame("hint")
                    } else if model.mode.allowsHoldToAdd {
                        MapHintTag(text: "DRAG PINS · HOLD TO ADD")
                            .reportsChromeFrame("hint")
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
            ResultOrYardageCard(model: model, style: .inline(hero: 52), linkCourse: actions.linkCourse,
                                reviewActions: actions) {
                HideControlsButton(actions: actions, frame: .outline)
            }
            if model.showsClubList {
                ClubList(model: model, actions: actions, axis: .horizontal)
            }
            if model.showsRoundSoFar {
                RoundScoresList(roundSoFar: model.roundSoFar, variant: model.layout.roundScoresVariant,
                                onPick: actions.openRoundHole)
                CasualFinishRow(model: model, actions: actions)
            } else {
                ActionRow(model: model, actions: actions, style: .singleRow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .chromeBox(opacity: RoundChromeMetrics.panelOpacity, shadow: RoundChromeMetrics.panelShadow)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.panel)
    }
}

/// iPhone landscape: title top-left; compass · hide · CARD · ··· bottom-left;
/// the 300 pt panel on the right with a 68 pt club list. Casual (canvas
/// iPhone-Casual-Landscape): a 312 pt panel, the round so far, no club list.
struct PhoneLandscapeLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    static let panelWidth: CGFloat = 300
    static let casualPanelWidth: CGFloat = 312
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
                if model.offersCourseMap {
                    CourseMapButton(actions: actions, compact: true)
                }
                CardButton(actions: actions, title: model.cardTitle)
                RoundOverflowMenu(model: model, actions: actions)
            }
            .fixedSize()
            .reportsChromeFrame("cluster")
            .pinned(.bottomLeading, insets: insets)

            CommandPanel(model: model, actions: actions,
                         columnStyle: PanelColumn.Style(card: .inline(hero: 48), spacing: 8, padding: 10,
                                                        primaryHeight: 52, primaryFont: 18,
                                                        showsHint: false, showsListTitle: false,
                                                        scoreGrid: .tight),
                         railWidth: Self.railWidth)
                .frame(width: model.showsRoundSoFar ? Self.casualPanelWidth : Self.panelWidth)
                .frame(maxHeight: .infinity)
                .reportsChromeFrame("panel")
                .padding(insets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// The club strip over the review panel while a shot is picked: SHOT n · CLUB,
/// DELETE SHOT and DONE in a flag-red header, then the clubs sideways.
struct ReviewClubStrip: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(model.selectedShotTitle ?? "")
                    .font(RoundFont.mono(10)).tracking(0.8)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button(action: actions.deleteSelectedShot) {
                    Text("DELETE SHOT").font(RoundFont.mono(10))
                        .padding(.horizontal, 10)
                        .frame(minHeight: RoundChromeMetrics.minTap)
                        .overlay(Rectangle().strokeBorder(palette.paper, lineWidth: RoundChromeMetrics.rule))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete this shot")
                Button(action: actions.doneSelection) {
                    Text("DONE").font(RoundFont.mono(10))
                        .foregroundStyle(palette.flag)
                        .padding(.horizontal, 14)
                        .frame(minHeight: RoundChromeMetrics.minTap)
                        .background(palette.paper, ignoresSafeAreaEdges: [])
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(palette.paper)
            .padding(.leading, 10)
            .padding(4)
            .background(palette.flag, ignoresSafeAreaEdges: [])
            ClubList(model: model, actions: actions, axis: .horizontal, cellHeight: 52)
                .padding(8)
        }
        .background(palette.paper.opacity(0.97), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(palette.flag, lineWidth: RoundChromeMetrics.rule))
        .compositingGroup()
        .shadow(color: palette.flag.opacity(0.22), radius: 0, x: 3, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.selectedShot)
    }
}

/// Folded / iPhone portrait with the controls hidden: "H8 · P4 · TAP MAP FOR
/// CONTROLS" top-left and "148 SHOW" bottom-left (the score in review).
struct CompactHiddenChrome: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    var body: some View {
        ZStack {
            MapHintTag(text: hiddenCaption, size: 11)
                .fixedSize()
                .reportsChromeFrame("hiddenCaption")
                .pinned(.topLeading, insets: insets)
            ShowControlsPill(model: model, actions: actions)
                .fixedSize()
                .reportsChromeFrame("hiddenPill")
                .pinned(.bottomLeading, insets: insets)
        }
    }

    /// "H8 · P4 · 5 (+1) · TAP MAP FOR CONTROLS" in review.
    private var hiddenCaption: String {
        var parts = [model.shortCaption]
        if model.reviewNext != nil, let score = model.reviewScore {
            let toPar = model.par.map { " (\(RoundMapFormat.toPar(score - $0)))" } ?? ""
            parts.append("\(score)\(toPar)")
        }
        return (parts + ["TAP MAP FOR CONTROLS"]).joined(separator: " · ")
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
            .background(palette.paper.opacity(0.9), ignoresSafeAreaEdges: [])
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
            .background(palette.paper.opacity(0.9), ignoresSafeAreaEdges: [])
    }
}

/// Paper sheet across the bottom: putts, penalty, the casual score grid, or
/// the score entry.
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
            } else if model.showsScoreGrid {
                ScoreGrid(model: model, actions: actions, metrics: .sheet)
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
