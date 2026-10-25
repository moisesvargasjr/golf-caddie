import SwiftUI

/// ‹ Hole N › with the par / length caption. The number opens the hole grid;
/// its accessibility value is the hole on screen (UI tests read it).
struct HoleTitleBar: View {
    enum Style: Equatable {
        /// "Hole 8" + caption beside it (open wide).
        case inline(size: CGFloat)
        /// Caption under the title (open portrait, book, iPhone).
        case stacked(size: CGFloat)
        /// Title only; caption at the trailing edge (folded, full width).
        case trailingCaption(size: CGFloat)
    }

    let model: RoundPanelModel
    let actions: RoundPanelActions
    var style: Style = .stacked(size: 24)
    var caption: String?
    /// Extra controls at the trailing edge (iPhone: CARD, ···).
    var trailing: AnyView?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            chevron("‹", label: "Previous hole", enabled: model.canGoPrevious,
                    id: InRoundAccessibilityID.previousHole, action: actions.previousHole)
            Button(action: actions.openHoleGrid) { title }
                .buttonStyle(.plain)
                .accessibilityLabel("Hole \(model.holeNumber), show all holes")
                .accessibilityValue("\(model.holeNumber)")
                .accessibilityIdentifier(InRoundAccessibilityID.holeNumber)
            chevron("›", label: model.isLiveHole ? "Skip to the next hole" : "Next hole",
                    enabled: model.canGoNext, id: InRoundAccessibilityID.nextHole, action: actions.nextHole)
            if showsTrailingCaption {
                Spacer(minLength: 4)
                StampLabel(text: caption ?? model.compactCaption, size: 10)
                    .padding(.trailing, 12)
            }
            if let trailing {
                Spacer(minLength: 4)
                trailing
            }
        }
        .chromeBox()
    }

    private var showsTrailingCaption: Bool {
        if case .trailingCaption = style { return true }
        return false
    }

    @ViewBuilder
    private var title: some View {
        let text = Text("Hole \(model.holeNumber)").foregroundStyle(palette.ink).lineLimit(1)
        switch style {
        case let .inline(size):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                text.font(RoundFont.serif(size))
                StampLabel(text: caption ?? model.holeCaption, size: 10)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        case let .stacked(size):
            VStack(alignment: .leading, spacing: 0) {
                text.font(RoundFont.serif(size))
                StampLabel(text: caption ?? model.holeCaption)
            }
            .padding(.horizontal, 2)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        case let .trailingCaption(size):
            text.font(RoundFont.serif(size))
                .frame(minHeight: 52)
                .contentShape(Rectangle())
        }
    }

    private func chevron(_ glyph: String, label: String, enabled: Bool, id: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(RoundFont.serif(24))
                .foregroundStyle(palette.ink)
                .frame(width: RoundChromeMetrics.minTap, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Compass needle that resets to hole-up (rule 10).
struct CompassChromeButton: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions

    var body: some View {
        CompassResetButton(rotationFromHoleUp: model.compassRotation, action: actions.resetCompass)
            .accessibilityIdentifier(InRoundAccessibilityID.compass)
    }
}

/// Hides the controls now (every layout offers it; auto-hide also uses it).
struct HideControlsButton: View {
    let actions: RoundPanelActions
    var frame: ChromeFrame = .box

    var body: some View {
        ChromeSquareButton(accessibilityLabel: "Hide controls", frame: frame, action: actions.hideControls) {
            Image(systemName: "eye.slash").font(.system(size: 15, weight: .semibold))
        }
        .accessibilityIdentifier(InRoundAccessibilityID.hideControls)
    }
}

/// CARD — the round's scorecard; "‹ CARD" in review goes back to it.
struct CardButton: View {
    let actions: RoundPanelActions
    var title = "CARD"
    var frame: ChromeFrame = .box
    var fontSize: CGFloat = 10
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: actions.openCard) {
            Text(title)
                .font(RoundFont.mono(fontSize))
                .tracking(0.8)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(palette.ink)
                .padding(.horizontal, fontSize < 10 ? 6 : 12)
                .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
                .chromeFrame(frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "CARD" ? "Open scorecard" : "Back to the scorecard")
        .accessibilityIdentifier(InRoundAccessibilityID.card)
    }
}

/// ··· — the live round: penalty (folded), clubs in play, course link,
/// tracking ⇄ casual, end round. A finished round (review): the round
/// actions — share, resume, course, delete (`RoundActionsMenu`).
struct RoundOverflowMenu: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var frame: ChromeFrame = .box
    var includesPenalty = false
    @Environment(\.palette) private var palette

    var body: some View {
        Menu {
            if let availability = model.roundActions {
                RoundActionsMenu(availability: availability, title: model.roundActionsTitle,
                                 handlers: actions.roundActions,
                                 addPenalty: offersPenalty ? actions.askPenalty : nil)
            } else {
                liveItems
            }
        } label: {
            Text("···")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.ink)
                .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
                .chromeFrame(frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(InRoundAccessibilityID.more)
        .simultaneousGesture(TapGesture().onEnded { actions.noteInteraction() })
    }

    private var offersPenalty: Bool {
        includesPenalty && model.state != .entry && model.mode.tracksShots
    }

    private var accessibilityText: String {
        if model.roundActions != nil { return "Round options: share, resume, course, delete" }
        return includesPenalty ? "More: penalty, end round, settings" : "More: end round, settings"
    }

    @ViewBuilder
    private var liveItems: some View {
        if offersPenalty {
            Button("Add a penalty…", action: actions.askPenalty)
        }
        Button("Clubs in play…", action: actions.openBag)
        if model.needsCourseLink {
            Button("Link course…", action: actions.linkCourse)
        } else {
            Section(model.courseName ?? "Course linked") {
                Button("Change course…", action: actions.linkCourse)
                Button("Unlink course", role: .destructive, action: actions.unlinkCourse)
            }
        }
        Button(model.mode == .casual ? "Switch to tracking" : "Switch to casual", action: actions.toggleCasual)
        Button("End round", role: .destructive, action: actions.endRound)
    }
}

/// "+1 · 2 SCORED" chip (open wide's bottom cluster).
struct RoundScoreChip: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(RoundFont.mono(11))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: RoundChromeMetrics.minTap)
            .background(palette.paper.opacity(RoundChromeMetrics.boxOpacity), ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(palette.ruleStrong, lineWidth: 1))
            .accessibilityLabel("Round score \(text)")
    }
}

/// After auto-hide: "148 SHOW" brings the controls back.
struct ShowControlsPill: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    var label = "SHOW"
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: actions.showControls) {
            HStack(spacing: 10) {
                if let yardage = model.yardage, model.isLiveHole {
                    Text("\(yardage.middle)").font(RoundFont.serif(26)).tabularNumerals()
                } else if model.reviewNext != nil, model.reviewScore != nil {
                    Text(model.reviewScoreText).font(RoundFont.serif(26)).tabularNumerals()
                }
                Text(label).font(RoundFont.mono(10)).tracking(0.8)
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(palette.paper.opacity(0.9), ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show controls")
        .accessibilityIdentifier(InRoundAccessibilityID.showControls)
    }
}

/// Toast / one-time tip / error line under the hole title.
struct RoundToastView: View {
    let toast: RoundToast
    @Environment(\.palette) private var palette

    var body: some View {
        Text(toast.text)
            .font(RoundFont.mono(toast.kind == .tip ? 11 : 12))
            .foregroundStyle(palette.paper)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(toast.kind == .error ? palette.red : palette.ink, ignoresSafeAreaEdges: [])
            .frame(maxWidth: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

