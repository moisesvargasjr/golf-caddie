import SwiftUI

// The Duo v2 canvas's chrome vocabulary: paper boxes with a 1.5 pt ink rule
// and a hard 3 pt shadow, Menlo stamps, Georgia numerals. Every round-map
// control is built from these so the six layouts stay one design.

enum RoundFont {
    static func mono(_ size: CGFloat) -> Font { .custom(AppFont.monoName, size: size).weight(.bold) }
    static func serif(_ size: CGFloat) -> Font { .custom(AppFont.serifName, size: size).weight(.bold) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom(AppFont.serifName, size: size).italic() }
}

enum RoundChromeMetrics {
    static let rule: CGFloat = 1.5
    static let shadow: CGFloat = 3
    static let panelShadow: CGFloat = 4
    /// Paper opacity of floating boxes / the command panel (canvas 0.94 / 0.96).
    static let boxOpacity = 0.94
    static let panelOpacity = 0.96
    static let minTap = SafeChrome.minTapTarget
}

private struct ChromeBox: ViewModifier {
    var opacity: Double
    var border: Color?
    var shadow: CGFloat
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(palette.paper.opacity(opacity))
            .overlay(Rectangle().strokeBorder(border ?? palette.ink, lineWidth: RoundChromeMetrics.rule))
            .compositingGroup()
            .shadow(color: palette.cardShadow.color, radius: 0, x: shadow, y: shadow)
    }
}

extension View {
    /// Paper box with the ink rule and hard shadow (canvas floating boxes).
    func chromeBox(opacity: Double = RoundChromeMetrics.boxOpacity, border: Color? = nil,
                   shadow: CGFloat = RoundChromeMetrics.shadow) -> some View {
        modifier(ChromeBox(opacity: opacity, border: border, shadow: shadow))
    }
}

/// Small outlined action ("+ SHOT", "+ PENALTY", "NOT YET", "DELETE").
struct OutlineActionButton: View {
    let title: String
    var isAlert = false
    var fontSize: CGFloat = 10
    var minHeight: CGFloat = RoundChromeMetrics.minTap
    var isBusy = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let color = isAlert ? palette.red : palette.ink
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().tint(color)
                } else {
                    Text(title).font(RoundFont.mono(fontSize)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: max(minHeight, RoundChromeMetrics.minTap))
            .overlay(Rectangle().strokeBorder(color, lineWidth: RoundChromeMetrics.rule))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The filled ink primary ("Finish hole ›", "Save · hole 9 ›").
struct PrimaryActionButton: View {
    let title: String
    var fontSize: CGFloat = 20
    var minHeight: CGFloat = 56
    var mono = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(mono ? RoundFont.mono(fontSize) : RoundFont.serif(fontSize))
                .foregroundStyle(palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: max(minHeight, RoundChromeMetrics.minTap))
                .background(palette.ink)
                .shadow(color: palette.cardShadow.color, radius: 0, x: RoundChromeMetrics.shadow,
                        y: RoundChromeMetrics.shadow)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// How a small chrome control is framed: a floating paper box (on the
/// map), an ink outline (inside a panel) or nothing (inside a bar).
enum ChromeFrame: Equatable {
    case box
    case outline
    case plain
}

private struct ChromeFrameModifier: ViewModifier {
    let frame: ChromeFrame
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        switch frame {
        case .box: content.chromeBox(shadow: 0)
        case .outline: content.overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
        case .plain: content
        }
    }
}

extension View {
    func chromeFrame(_ frame: ChromeFrame) -> some View {
        modifier(ChromeFrameModifier(frame: frame))
    }
}

/// 44 pt square floating button (compass, hide, ···) on a paper box.
struct ChromeSquareButton<Label: View>: View {
    let accessibilityLabel: String
    var frame: ChromeFrame = .box
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(palette.ink)
                .frame(width: RoundChromeMetrics.minTap, height: RoundChromeMetrics.minTap)
                .chromeFrame(frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// "TO PIN · WATCH GPS" style label.
struct StampLabel: View {
    let text: String
    var size: CGFloat = 9
    var color: Color?
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(RoundFont.mono(size))
            .tracking(0.8)
            .foregroundStyle(color ?? palette.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
