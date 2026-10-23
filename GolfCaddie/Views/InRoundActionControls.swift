import SwiftUI

// Action controls for the expanded in-round layouts. Most shots are logged by
// the watch, so manual logging is a small secondary ("+ SHOT HERE") and
// Finish hole is the primary, filled action.

/// The expanded bottom bar, two rows:
/// 1. [⌚ WATCH IS DETECTING SWINGS] · ↶ undo · + SHOT · + MISSED (44 pt)
/// 2. PUTT +1 (~120 pt) · primary filled Finish hole › (fills the rest)
struct InRoundActionBar: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    /// The rail layout (H4) shows the watch line in its panel instead.
    var showsWatchStatus = true

    static let puttWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if showsWatchStatus, snapshot.watchDetecting {
                    WatchDetectingLine(isDetecting: true)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                SecondaryActionRow(snapshot: snapshot, actions: actions)
                    .frame(maxWidth: 320)
            }
            HStack(spacing: 8) {
                PuttButton(snapshot: snapshot, actions: actions, label: "PUTT +1")
                    .frame(width: Self.puttWidth)
                FinishHoleButton(actions: actions)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// ↶ undo · + SHOT (manual mark) · + MISSED (missing-shot pin sheet).
struct SecondaryActionRow: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    var shotTitle = "+ SHOT"

    var body: some View {
        HStack(spacing: 6) {
            UndoButton(snapshot: snapshot, actions: actions)
                .frame(width: InRoundMetrics.minTouch + 8)
            SmallActionButton(title: shotTitle, isBusy: snapshot.isMarking,
                              action: actions.logShot)
                .disabled(snapshot.isMarking)
            SmallActionButton(title: "+ MISSED", action: actions.markMissed)
        }
        .frame(height: InRoundMetrics.minTouch)
    }
}

struct SmallActionButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().tint(palette.ink)
                } else {
                    Text(title).font(AppFont.stamp).tracking(1.0)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, minHeight: InRoundMetrics.minTouch)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct UndoButton: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: actions.undo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, minHeight: InRoundMetrics.minTouch)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!snapshot.canUndo)
        .opacity(snapshot.canUndo ? 1 : 0.4)
        .accessibilityLabel("Undo last shot or penalty")
    }
}

struct PuttButton: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    var label = "PUTT"
    var fontSize: CGFloat = 12
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: actions.putt) {
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
        .disabled(snapshot.isMarking)
    }
}

/// The primary action on every expanded layout: opens the Finish Hole flow.
struct FinishHoleButton: View {
    let action: () -> Void
    var fontSize: CGFloat = 20
    @Environment(\.palette) private var palette

    init(actions: InRoundActions, fontSize: CGFloat = 20) {
        self.action = actions.finishHole
        self.fontSize = fontSize
    }

    init(fontSize: CGFloat = 20, action: @escaping () -> Void) {
        self.action = action
        self.fontSize = fontSize
    }

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
    }
}

/// "⌚ WATCH IS DETECTING SWINGS" — only while the watch app is reachable.
struct WatchDetectingLine: View {
    let isDetecting: Bool
    var label = "WATCH IS DETECTING SWINGS"
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
struct CompactActionRows: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions

    static let puttWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if snapshot.watchDetecting {
                    WatchDetectingLine(isDetecting: true, label: "WATCH DETECTING")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                SecondaryActionRow(snapshot: snapshot, actions: actions)
                    .frame(maxWidth: 260)
            }
            HStack(spacing: 8) {
                PuttButton(snapshot: snapshot, actions: actions, label: "PUTT +1")
                    .frame(width: Self.puttWidth)
                FinishHoleButton(actions: actions)
            }
            .frame(height: 52)
        }
    }
}
