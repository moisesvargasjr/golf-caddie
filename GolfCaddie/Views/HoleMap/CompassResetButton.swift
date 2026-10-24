import SwiftUI

/// 44 pt square paper button with a two-tone needle (Duo v2 rule 10): the
/// red tip points along the hole, so it turns as the map is pinch-rotated;
/// tapping turns the map back to hole-up. Pass `controller.rotationFromHoleUp`.
struct CompassResetButton: View {
    /// Degrees the map is turned from hole-up (`HoleMapController.rotationFromHoleUp`).
    let rotationFromHoleUp: Double
    let action: () -> Void

    @Environment(\.palette) private var palette

    static let size: CGFloat = SafeChrome.minTapTarget

    var body: some View {
        Button(action: action) {
            CompassNeedle(tip: PaletteValues.light.flag, tail: palette.ink)
                .frame(width: 22, height: 22)
                // The camera turning clockwise turns the picture anticlockwise.
                .rotationEffect(.degrees(-rotationFromHoleUp))
                .animation(.easeOut(duration: 0.35), value: rotationFromHoleUp)
                .frame(width: Self.size, height: Self.size)
                .background(palette.paper.opacity(0.94))
                .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset map to hole-up")
        .accessibilityValue(Self.accessibilityValue(rotationFromHoleUp))
    }

    static func accessibilityValue(_ rotation: Double) -> String {
        let degrees = Int(abs(rotation).rounded())
        guard degrees >= 1 else { return "Hole-up" }
        return "Turned \(degrees) degrees \(rotation > 0 ? "right" : "left")"
    }
}

/// The canvas needle: filled tip up, outlined tail down, in a 22 pt box.
private struct CompassNeedle: View {
    let tip: Color
    let tail: Color

    var body: some View {
        Canvas { context, size in
            let s = size.width / 22
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var top = Path()
            top.move(to: p(11, 2))
            top.addLine(to: p(15, 11))
            top.addLine(to: p(11, 9))
            top.addLine(to: p(7, 11))
            top.closeSubpath()
            context.fill(top, with: .color(tip))
            var bottom = Path()
            bottom.move(to: p(11, 20))
            bottom.addLine(to: p(15, 11))
            bottom.addLine(to: p(11, 13))
            bottom.addLine(to: p(7, 11))
            bottom.closeSubpath()
            context.stroke(bottom, with: .color(tail), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        CompassResetButton(rotationFromHoleUp: 0) {}
        CompassResetButton(rotationFromHoleUp: 30) {}
    }
    .padding()
}
