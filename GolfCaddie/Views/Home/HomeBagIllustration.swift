import SwiftUI

/// The golf bag drawing from the Home-Open mockup (150×190 viewBox), in
/// palette colours so it follows the theme. Decorative.
struct HomeBagIllustration: View {
    static let viewBox = CGSize(width: 150, height: 190)

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.viewBox.width, size.height / Self.viewBox.height)
            context.translateBy(x: (size.width - Self.viewBox.width * scale) / 2,
                                y: (size.height - Self.viewBox.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            drawShafts(in: context)
            drawHeads(in: context)
            drawBag(in: context)
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static let shafts: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 52, y: 62), CGPoint(x: 44, y: 14)),
        (CGPoint(x: 60, y: 62), CGPoint(x: 58, y: 10)),
        (CGPoint(x: 68, y: 62), CGPoint(x: 72, y: 18)),
        (CGPoint(x: 76, y: 62), CGPoint(x: 84, y: 12)),
        (CGPoint(x: 84, y: 62), CGPoint(x: 96, y: 20)),
        (CGPoint(x: 92, y: 62), CGPoint(x: 104, y: 28)),
        (CGPoint(x: 56, y: 62), CGPoint(x: 50, y: 26)),
        (CGPoint(x: 72, y: 62), CGPoint(x: 66, y: 28)),
        (CGPoint(x: 88, y: 62), CGPoint(x: 90, y: 30)),
    ]

    /// Iron heads: four-point parallelograms; `dark` = ink, else ink2.
    private static let irons: [([CGPoint], Bool)] = [
        ([CGPoint(x: 80, y: 8), CGPoint(x: 92, y: 10), CGPoint(x: 90, y: 15), CGPoint(x: 80, y: 13)], true),
        ([CGPoint(x: 93, y: 16), CGPoint(x: 104, y: 19), CGPoint(x: 102, y: 24), CGPoint(x: 92, y: 21)], true),
        ([CGPoint(x: 101, y: 24), CGPoint(x: 112, y: 27), CGPoint(x: 110, y: 32), CGPoint(x: 100, y: 29)], true),
        ([CGPoint(x: 46, y: 22), CGPoint(x: 56, y: 24), CGPoint(x: 55, y: 29), CGPoint(x: 45, y: 27)], false),
        ([CGPoint(x: 62, y: 24), CGPoint(x: 72, y: 26), CGPoint(x: 71, y: 31), CGPoint(x: 61, y: 29)], false),
        ([CGPoint(x: 86, y: 26), CGPoint(x: 97, y: 28), CGPoint(x: 95, y: 33), CGPoint(x: 85, y: 31)], false),
    ]

    private func drawShafts(in context: GraphicsContext) {
        var path = Path()
        for (start, end) in Self.shafts {
            path.move(to: start)
            path.addLine(to: end)
        }
        context.stroke(path, with: .color(palette.ink),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func drawHeads(in context: GraphicsContext) {
        // Woods.
        context.fill(ellipse(cx: 41, cy: 11, rx: 9, ry: 6), with: .color(palette.ink))
        context.fill(ellipse(cx: 57, cy: 7, rx: 8, ry: 5), with: .color(palette.ink))
        context.fill(ellipse(cx: 72, cy: 15, rx: 7, ry: 4.5), with: .color(palette.ink2))
        for (points, dark) in Self.irons {
            context.fill(polygon(points), with: .color(dark ? palette.ink : palette.ink2))
        }
    }

    private func drawBag(in context: GraphicsContext) {
        let ink = GraphicsContext.Shading.color(palette.ink)
        // Collar.
        let collar = Path(roundedRect: CGRect(x: 44, y: 58, width: 60, height: 14), cornerRadius: 4)
        context.fill(collar, with: .color(palette.paper))
        context.stroke(collar, with: ink, lineWidth: 2)
        // Body.
        var body = Path()
        body.move(to: CGPoint(x: 46, y: 72))
        body.addLine(to: CGPoint(x: 102, y: 72))
        body.addLine(to: CGPoint(x: 98, y: 176))
        body.addQuadCurve(to: CGPoint(x: 50, y: 176), control: CGPoint(x: 74, y: 184))
        body.closeSubpath()
        context.fill(body, with: .color(palette.paperDark))
        context.stroke(body, with: ink, lineWidth: 2)
        // Pocket.
        let pocket = Path(roundedRect: CGRect(x: 56, y: 100, width: 34, height: 46), cornerRadius: 5)
        context.fill(pocket, with: .color(palette.paper))
        context.stroke(pocket, with: ink, lineWidth: 1.5)
        var seam = Path()
        seam.move(to: CGPoint(x: 60, y: 112))
        seam.addLine(to: CGPoint(x: 86, y: 112))
        context.stroke(seam, with: ink, lineWidth: 1.2)
        // Strap.
        var strap = Path()
        strap.move(to: CGPoint(x: 100, y: 80))
        strap.addCurve(to: CGPoint(x: 98, y: 164),
                       control1: CGPoint(x: 128, y: 96), control2: CGPoint(x: 128, y: 150))
        context.stroke(strap, with: .color(palette.flag),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        // Base.
        context.fill(Path(roundedRect: CGRect(x: 48, y: 176, width: 52, height: 8), cornerRadius: 3),
                     with: ink)
    }

    private func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
