import SwiftUI

/// Panel (inside a side panel) or sheet (across the bottom: folded, iPhone).
enum QuestionPresentation: Equatable {
    case panel
    case sheet

    var isSheet: Bool { self == .sheet }
}

/// Finish hole asks only for putts (0–4+), the same as the watch, then
/// confirms the score and moves to the next hole. Replaces PUTT +1.
struct PuttsQuestion: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var presentation: QuestionPresentation = .panel
    @Environment(\.palette) private var palette

    var body: some View {
        let sheet = presentation.isSheet
        VStack(alignment: .leading, spacing: sheet ? 12 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Putts on hole \(model.holeNumber)?")
                    .font(RoundFont.serif(sheet ? 24 : 20))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if sheet {
                    Spacer(minLength: 4)
                    StampLabel(text: "SAME AS THE WATCH", size: 10)
                }
            }
            HStack(spacing: sheet ? 8 : 4) {
                ForEach(PuttsQuestionModel.options, id: \.self) { putts in
                    option(putts, sheet: sheet)
                }
            }
            StampLabel(text: model.puttsSummary, size: sheet ? 12 : 10)
            HStack(spacing: sheet ? 8 : 6) {
                OutlineActionButton(title: "NOT YET", fontSize: sheet ? 11 : 10, minHeight: sheet ? 56 : 52,
                                    action: actions.cancelQuestion)
                    .frame(width: sheet ? 110 : 76)
                PrimaryActionButton(title: model.finishConfirmTitle, fontSize: sheet ? 20 : 17,
                                    minHeight: sheet ? 56 : 52, action: actions.confirmFinish)
                    .accessibilityIdentifier(InRoundAccessibilityID.confirmFinish)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.puttsQuestion)
    }

    private func option(_ putts: Int, sheet: Bool) -> some View {
        let selected = model.puttsChoice == putts
        return Button { actions.pickPutts(putts) } label: {
            Text(PuttsQuestionModel.label(putts))
                .font(RoundFont.mono(sheet ? 24 : 17))
                .foregroundStyle(selected ? palette.paper : palette.ink)
                .frame(maxWidth: .infinity, minHeight: sheet ? 64 : 48)
                .background(selected ? palette.ink : Color.clear, ignoresSafeAreaEdges: [])
                .overlay { if !selected { Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(putts >= (PuttsQuestionModel.options.last ?? 4) ? "Four or more putts" : "\(putts) putts")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(InRoundAccessibilityID.puttsOption(putts))
    }
}

/// + PENALTY: "what happened?" — OB or lost, water, unplayable, wrong ball
/// (+2), other. Replaces `PenaltySheet`.
struct PenaltyQuestion: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var presentation: QuestionPresentation = .panel
    @Environment(\.palette) private var palette

    var body: some View {
        let sheet = presentation.isSheet
        VStack(alignment: .leading, spacing: sheet ? 12 : 8) {
            Text("Penalty · what happened?")
                .font(RoundFont.serif(sheet ? 22 : 17))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: sheet ? 8 : 5),
                                GridItem(.flexible(), spacing: sheet ? 8 : 5)],
                      spacing: sheet ? 8 : 5) {
                ForEach(PenaltyOption.all) { option in
                    Button { actions.pickPenalty(option.type) } label: {
                        VStack(spacing: 1) {
                            Text(option.title).font(RoundFont.mono(sheet ? 12 : 10)).foregroundStyle(palette.ink)
                            Text(option.costText).font(RoundFont.mono(sheet ? 9 : 8)).foregroundStyle(palette.red)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(2)
                        .frame(maxWidth: .infinity, minHeight: sheet ? 52 : 44)
                        .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.type.displayName), plus \(option.strokes)")
                }
            }
            Button(action: actions.cancelQuestion) {
                Text("CANCEL")
                    .font(RoundFont.mono(sheet ? 11 : 10))
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: sheet ? nil : .infinity, minHeight: RoundChromeMetrics.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(sheet ? 0 : 10)
        .overlay { if !sheet { Rectangle().strokeBorder(palette.red, lineWidth: RoundChromeMetrics.rule) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.penaltyQuestion)
    }
}

/// Strokes + putts for a hole that wasn't tracked (late start, skipped hole)
/// in tracking mode (casual uses `ScoreGrid`).
struct HandScoreEntry: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var presentation: QuestionPresentation = .panel
    @Environment(\.palette) private var palette

    var body: some View {
        let sheet = presentation.isSheet
        VStack(alignment: .leading, spacing: sheet ? 12 : 10) {
            Text(model.entryTitle).font(RoundFont.serif(sheet ? 20 : 18)).foregroundStyle(palette.ink)
            stepper("STROKES", value: model.entry.strokes, sheet: sheet,
                    canDecrease: model.entry.canDecreaseStrokes, canIncrease: model.entry.canIncreaseStrokes,
                    noun: "stroke", step: actions.stepEntryStrokes)
            stepper("PUTTS", value: model.entry.putts, sheet: sheet,
                    canDecrease: model.entry.canDecreasePutts, canIncrease: model.entry.canIncreasePutts,
                    noun: "putt", step: actions.stepEntryPutts)
            if !model.entrySummary.isEmpty {
                StampLabel(text: model.entrySummary, size: 11)
            }
            HStack(spacing: 8) {
                if model.entryShowsBackToLive {
                    OutlineActionButton(title: model.backToLiveShortTitle, minHeight: 52, action: actions.backToLive)
                        .accessibilityIdentifier(InRoundAccessibilityID.backToLive)
                }
                PrimaryActionButton(title: model.entrySaveTitle, fontSize: 18, minHeight: 52, action: actions.saveEntry)
                    .accessibilityIdentifier(InRoundAccessibilityID.saveEntry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.handEntry)
    }

    private func stepper(_ label: String, value: Int, sheet: Bool, canDecrease: Bool, canIncrease: Bool,
                         noun: String, step: @escaping (Int) -> Void) -> some View {
        let side: CGFloat = sheet ? 52 : 44
        return HStack {
            StampLabel(text: label, size: sheet ? 11 : 10)
            Spacer(minLength: 8)
            HStack(spacing: sheet ? 10 : 6) {
                stepButton("−", label: "One fewer \(noun)", side: side, enabled: canDecrease) { step(-1) }
                Text("\(value)")
                    .font(RoundFont.serif(sheet ? 32 : 26))
                    .foregroundStyle(palette.ink)
                    .tabularNumerals()
                    .frame(width: sheet ? 40 : 32)
                    .accessibilityLabel("\(value) \(noun)s")
                stepButton("+", label: "One more \(noun)", side: side, enabled: canIncrease) { step(1) }
            }
        }
    }

    private func stepButton(_ glyph: String, label: String, side: CGFloat, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.custom(AppFont.serifName, size: 22))
                .foregroundStyle(palette.ink)
                .frame(width: side, height: side)
                .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// The selected shot: "SHOT 2 · 7i · 152 YD", how to edit it, DELETE / DONE.
struct SelectedShotCard: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var compact = false
    /// On the map (folded, iPhone) rather than inside a panel: paper behind it.
    var floating = false
    @Environment(\.palette) private var palette

    var body: some View {
        let title = model.selectedShotTitle ?? ""
        Group {
            if compact {
                // Side by side when the words fit on one line; the folded
                // bottom-left card (~180 pt) puts the buttons underneath
                // instead of squeezing the text to a letter per line.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        compactText.fixedSize()
                        Spacer(minLength: 0)
                        buttons(width: 60)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        compactText
                        HStack(spacing: 6) { buttons(width: nil) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    StampLabel(text: title, size: 11, color: palette.flag)
                    Text("Drag it on the map. Pick a club to change it.")
                        .font(RoundFont.serifItalic(13))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) { buttons(width: nil) }
                }
                .padding(10)
            }
        }
        .background(floating ? palette.paper.opacity(0.97) : Color.clear, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(palette.flag, lineWidth: RoundChromeMetrics.rule))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.selectedShot)
    }

    private var compactText: some View {
        VStack(alignment: .leading, spacing: 2) {
            StampLabel(text: model.selectedShotTitle ?? "", size: 10, color: palette.flag)
            Text("Drag it, or pick its club.").font(RoundFont.serifItalic(12)).foregroundStyle(palette.ink)
        }
    }

    @ViewBuilder
    private func buttons(width: CGFloat?) -> some View {
        OutlineActionButton(title: "DELETE", isAlert: true, fontSize: compact ? 9 : 10,
                            action: actions.deleteSelectedShot)
            .frame(width: width)
            .accessibilityLabel("Delete this shot")
        PrimaryActionButton(title: "DONE", fontSize: compact ? 9 : 10, minHeight: 44, mono: true,
                            action: actions.doneSelection)
            .frame(width: width)
    }
}
