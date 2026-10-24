import SwiftUI

/// + SHOT (small: the watch logs most shots), + PENALTY, and the primary
/// Finish hole ›. On a finished hole: + PENALTY and Back to hole N ›; in a
/// finished round's review: + PENALTY and Next hole › (Back to card ›).
struct ActionRow: View {
    enum Style: Equatable {
        /// Small buttons over a full-width primary (side panels).
        case stacked(primaryHeight: CGFloat, primaryFont: CGFloat)
        /// One row: two 76 pt buttons and the primary (iPhone bottom panel).
        case singleRow
    }

    let model: RoundPanelModel
    let actions: RoundPanelActions
    var style: Style = .stacked(primaryHeight: 56, primaryFont: 20)
    /// + PENALTY in this row (false on folded, where it lives in ···).
    var showsPenalty = true

    var body: some View {
        switch style {
        case let .stacked(height, font):
            VStack(spacing: 8) {
                if !smallButtons.isEmpty {
                    HStack(spacing: 5) { ForEach(smallButtons, id: \.self) { kind in smallButton(kind) } }
                }
                primary(height: height, font: font)
            }
        case .singleRow:
            HStack(spacing: 6) {
                ForEach(smallButtons, id: \.self) { kind in
                    smallButton(kind).frame(width: 76)
                }
                primary(height: 52, font: 18)
            }
        }
    }

    private enum Small: Hashable { case shot, penalty }

    private var smallButtons: [Small] {
        var kinds: [Small] = []
        if model.isLiveHole, model.mode.tracksShots { kinds.append(.shot) }
        if showsPenalty, model.state != .entry, model.mode.tracksShots { kinds.append(.penalty) }
        return kinds
    }

    @ViewBuilder
    private func smallButton(_ kind: Small) -> some View {
        let height: CGFloat = style == .singleRow ? 52 : 44
        switch kind {
        case .shot:
            OutlineActionButton(title: InRoundLabels.shot, minHeight: height, isBusy: model.isMarking,
                                action: actions.addShot)
                .disabled(model.isMarking)
                .accessibilityLabel("Log a shot where you are")
                .accessibilityIdentifier(InRoundAccessibilityID.addShot)
        case .penalty:
            OutlineActionButton(title: style == .singleRow ? "+ PEN" : InRoundLabels.penalty, isAlert: true,
                                minHeight: height, action: actions.askPenalty)
                .accessibilityLabel("Add a penalty")
                .accessibilityIdentifier(InRoundAccessibilityID.addPenalty)
        }
    }

    @ViewBuilder
    private func primary(height: CGFloat, font: CGFloat) -> some View {
        if model.isLiveHole {
            PrimaryActionButton(title: InRoundLabels.finish, fontSize: font, minHeight: height,
                                action: actions.finishHole)
                .accessibilityIdentifier(InRoundAccessibilityID.finishHole)
        } else if let next = model.reviewNext {
            ReviewNextButton(next: next, actions: actions, fontSize: font - 1, minHeight: height)
        } else {
            PrimaryActionButton(title: model.backToLiveTitle, fontSize: font - 2, minHeight: height,
                                action: actions.backToLive)
                .accessibilityIdentifier(InRoundAccessibilityID.backToLive)
        }
    }
}

/// Shown under the action row's small buttons on the live hole.
struct PanelHint: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(RoundFont.mono(9))
            .tracking(0.6)
            .foregroundStyle(palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
