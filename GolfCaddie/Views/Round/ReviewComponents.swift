import SwiftUI

// The pieces review mode adds to the shared panel (Review-Open / -Folded /
// -iPhone boards): the result block, the PUTTS stepper and Next hole ›.

/// "RESULT · 3 SHOTS + 2 PUTTS", the score, "+1 · BOGEY" — the top of the
/// panel on a finished hole in review (instead of the live yardage).
struct ReviewResultBlock: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    /// Big score over a putts row (side panels) or score + putts side by side.
    var stacked = true
    var hero: CGFloat = 60
    /// Folded keeps the stepper in its action box instead.
    var showsStepper = true
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StampLabel(text: model.reviewResultLabel)
            if stacked {
                score
                if showsStepper, model.showsPuttsStepper {
                    ReviewPuttsStepper(model: model, actions: actions)
                        .padding(.top, 6)
                        .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    score
                    Spacer(minLength: 4)
                    if showsStepper, model.showsPuttsStepper {
                        ReviewPuttsStepper(model: model, actions: actions, compact: true)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.reviewResult)
    }

    private var score: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.reviewScoreText)
                .font(RoundFont.serif(hero))
                .foregroundStyle(palette.ink)
                .tabularNumerals()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !model.reviewToParLabel.isEmpty {
                Text(model.reviewToParLabel)
                    .font(RoundFont.mono(stacked ? 14 : 12))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreAccessibilityLabel)
    }

    private var scoreAccessibilityLabel: String {
        let toPar = model.reviewToParLabel.isEmpty ? "" : ", \(model.reviewToParLabel)"
        return "Hole \(model.holeNumber) score \(model.reviewScoreText)\(toPar)"
    }
}

/// PUTTS − n + (one putt at a time; trims or adds putt strokes).
struct ReviewPuttsStepper: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    /// Number with PUTTS under it (iPhone / folded) instead of PUTTS beside it.
    var compact = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            if !compact {
                StampLabel(text: "PUTTS", size: 10)
                Spacer(minLength: 4)
            }
            stepButton("−", label: "One fewer putt", enabled: ReviewPutts.canDecrease(model.putts)) {
                actions.stepPutts(-1)
            }
            VStack(spacing: 0) {
                Text(model.putts.map { String($0) } ?? "—")
                    .font(RoundFont.serif(22))
                    .foregroundStyle(palette.ink)
                    .tabularNumerals()
                if compact { StampLabel(text: "PUTTS", size: 8) }
            }
            .frame(minWidth: 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.putts ?? 0) putts")
            stepButton("+", label: "One more putt", enabled: ReviewPutts.canIncrease(model.putts)) {
                actions.stepPutts(1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.reviewPutts)
    }

    private func stepButton(_ glyph: String, label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.custom(AppFont.serifName, size: 18))
                .foregroundStyle(palette.ink)
                .frame(width: RoundChromeMetrics.minTap, height: RoundChromeMetrics.minTap)
                .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// The review's primary: Next hole › (Back to card › on the last hole).
struct ReviewNextButton: View {
    let next: ReviewNavigation.Next
    let actions: RoundPanelActions
    var fontSize: CGFloat = 19
    var minHeight: CGFloat = 52

    var body: some View {
        PrimaryActionButton(title: next.title, fontSize: fontSize, minHeight: minHeight,
                            action: actions.reviewNext)
            .accessibilityLabel(next.accessibilityLabel)
            .accessibilityIdentifier(InRoundAccessibilityID.reviewNext)
    }
}
