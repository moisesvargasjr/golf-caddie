import SwiftUI

// In-round action controls, shared by the compact and expanded layouts. Most
// shots are logged by the watch, so manual logging is a small secondary
// ("+ SHOT") and Finish hole is the primary, filled action. The controls take
// only the values they draw (not the whole snapshot) to keep re-renders cheap.

/// One vocabulary for every layout (asserted in tests).
enum InRoundLabels {
    static let shot = "+ SHOT"
    static let missed = "+ MISSED"
    static let penalty = "⚠ PENALTY"
    static let putt = "PUTT +1"
    static let finish = "Finish hole ›"
    static let watchShort = "WATCH DETECTING"
    static let watchLong = "WATCH IS DETECTING SWINGS"

    /// Secondary row titles after the ↶ undo icon.
    static func secondaryTitles(showsPenalty: Bool) -> [String] {
        showsPenalty ? [shot, missed, penalty] : [shot, missed]
    }
}

/// Values the action rows draw.
struct InRoundActionState: Equatable {
    var canUndo: Bool
    var isMarking: Bool
    var watchDetecting: Bool
}

/// The expanded bottom bar, two rows:
/// 1. [⌚ WATCH IS DETECTING SWINGS] · ↶ · + SHOT · + MISSED · ⚠ PENALTY (44 pt)
/// 2. PUTT +1 (~120 pt) · primary filled Finish hole › (fills the rest)
struct InRoundActionBar: View {
    let state: InRoundActionState
    let actions: InRoundActions
    /// The rail layout (H4) shows the watch line in its panel instead.
    var showsWatchStatus = true

    static let puttWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if showsWatchStatus, state.watchDetecting {
                    WatchStatusFitting(isDetecting: true)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                SecondaryActionRow(state: state, actions: actions, showsPenalty: true)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: 8) {
                PuttButton(isMarking: state.isMarking, action: actions.putt)
                    .frame(width: Self.puttWidth)
                FinishHoleButton(action: actions.finishHole)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// ↶ undo · + SHOT (manual mark) · + MISSED (missing-shot pin sheet)
/// [· ⚠ PENALTY (penalty sheet) — expanded layouts; compact has its stamp].
struct SecondaryActionRow: View {
    let state: InRoundActionState
    let actions: InRoundActions
    var showsPenalty = false

    var body: some View {
        HStack(spacing: 6) {
            UndoButton(canUndo: state.canUndo, action: actions.undo)
                .frame(width: InRoundMetrics.minTouch + 8)
            ForEach(InRoundLabels.secondaryTitles(showsPenalty: showsPenalty), id: \.self) { title in
                switch title {
                case InRoundLabels.shot:
                    SmallActionButton(title: title, isBusy: state.isMarking, action: actions.logShot)
                        .disabled(state.isMarking)
                case InRoundLabels.missed:
                    SmallActionButton(title: title, action: actions.markMissed)
                default:
                    SmallActionButton(title: title, isAlert: true, action: actions.addPenalty)
                }
            }
        }
        .frame(height: InRoundMetrics.minTouch)
    }
}

struct SmallActionButton: View {
    let title: String
    var isBusy = false
    var isAlert = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let color = isAlert ? palette.red : palette.ink
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().tint(color)
                } else {
                    Text(title).font(AppFont.stamp).tracking(1.0)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: InRoundMetrics.minTouch)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: isAlert ? 1.4 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct UndoButton: View {
    let canUndo: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, minHeight: InRoundMetrics.minTouch)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canUndo)
        .opacity(canUndo ? 1 : 0.4)
        .accessibilityLabel("Undo last shot or penalty")
    }
}

struct PuttButton: View {
    let isMarking: Bool
    var label = InRoundLabels.putt
    var fontSize: CGFloat = 12
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "circle.fill").font(.system(size: fontSize - 2, weight: .bold))
                Text(label).font(.custom(AppFont.monoName, size: fontSize).weight(.bold)).tracking(0.8)
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: InRoundMetrics.minTouch)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1.4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMarking)
    }
}

/// The primary action on every layout: opens the Finish Hole flow.
struct FinishHoleButton: View {
    var fontSize: CGFloat = 20
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Finish").font(.custom(AppFont.serifName, size: fontSize).italic())
                    .foregroundStyle(palette.paper.opacity(0.85))
                Text("hole").font(.custom(AppFont.serifName, size: fontSize).weight(.bold))
                Text("›").font(.custom(AppFont.serifName, size: fontSize + 4).weight(.bold))
            }
            .foregroundStyle(palette.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: InRoundMetrics.minTouch)
            .background(palette.flag)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(InRoundLabels.finish)
    }
}

/// "⌚ WATCH IS DETECTING SWINGS" — only while the watch app is reachable.
struct WatchDetectingLine: View {
    let isDetecting: Bool
    var label = InRoundLabels.watchLong
    @Environment(\.palette) private var palette

    var body: some View {
        if isDetecting {
            HStack(spacing: 6) {
                Image(systemName: "applewatch").font(.system(size: 11, weight: .semibold))
                Text(label).font(AppFont.micro).tracking(1.2)
            }
            .foregroundStyle(palette.ink2)
        }
    }
}

/// Compact (cover screen / iPhone) bottom rows:
/// 1. [⌚ WATCH DETECTING] · ↶ · + SHOT · + MISSED (44 pt)
/// 2. PUTT +1 (~104 pt) · primary Finish hole › (fills the rest)
/// (Penalty stays on the compact sheet's PENALTY stamp.)
struct CompactActionRows: View {
    let state: InRoundActionState
    let actions: InRoundActions

    static let puttWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if state.watchDetecting {
                    WatchDetectingLine(isDetecting: true, label: InRoundLabels.watchShort)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                SecondaryActionRow(state: state, actions: actions)
                    .frame(maxWidth: 260)
            }
            HStack(spacing: 8) {
                PuttButton(isMarking: state.isMarking, action: actions.putt)
                    .frame(width: Self.puttWidth)
                FinishHoleButton(action: actions.finishHole)
            }
            .frame(height: 52)
        }
    }
}

/// Plain button style whose label gets a >= 44 pt hit area (`ExpandedHitShape`)
/// without changing its drawn size — for the small compact stamps.
struct HitTargetPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(ExpandedHitShape())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// "WATCH IS DETECTING SWINGS" when it fits, else "WATCH DETECTING".
struct WatchStatusFitting: View {
    let isDetecting: Bool

    var body: some View {
        if isDetecting {
            ViewThatFits(in: .horizontal) {
                WatchDetectingLine(isDetecting: true).lineLimit(1).fixedSize()
                WatchDetectingLine(isDetecting: true, label: InRoundLabels.watchShort).lineLimit(1).fixedSize()
                Image(systemName: "applewatch").font(.system(size: 11, weight: .semibold))
                    .accessibilityLabel(InRoundLabels.watchShort)
            }
        }
    }
}
