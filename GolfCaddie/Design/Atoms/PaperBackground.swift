import SwiftUI

/// Paints the "Fairway Logbook" paper-stock background — a vertical gradient
/// from `paper` → `paperDark` with a subtle 45° cross-hatch and two soft
/// radial corners. Apply to the root of any full-screen view that isn't a
/// full-bleed map.
///
/// The cross-hatch is rendered via `Canvas` for crisp pixel-aligned lines that
/// don't depend on asset bundles.
struct PaperBackground: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.paper, palette.paperDark],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: palette.inkRgb.r, green: palette.inkRgb.g, blue: palette.inkRgb.b, opacity: 0.04), .clear],
                center: UnitPoint(x: 0.2, y: 0.1),
                startRadius: 0,
                endRadius: 400
            )
            RadialGradient(
                colors: [Color(red: palette.inkRgb.r, green: palette.inkRgb.g, blue: palette.inkRgb.b, opacity: 0.03), .clear],
                center: UnitPoint(x: 0.8, y: 0.8),
                startRadius: 0,
                endRadius: 400
            )
            crosshatch
        }
        .ignoresSafeArea()
    }

    /// Repeating 45° single-pixel lines, 12pt apart. Opacity tuned per scheme.
    private var crosshatch: some View {
        Canvas { ctx, size in
            let opacity: Double = scheme == .dark ? 0.018 : 0.012
            let stroke = Color(red: palette.inkRgb.r, green: palette.inkRgb.g, blue: palette.inkRgb.b, opacity: opacity)
            let spacing: CGFloat = 12
            // 45° lines: draw diagonal lines across the canvas. Cover top-left to bottom-right.
            let extent = size.width + size.height
            var x: CGFloat = -size.height
            while x < extent {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(path, with: .color(stroke), lineWidth: 1)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Apply the paper background behind this view (full bleed). Use at the root of a screen.
    func paperBackground() -> some View {
        self.background(PaperBackground())
    }
}
