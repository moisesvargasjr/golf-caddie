import SwiftUI

/// 22×22 score cell used in the Round Summary scorecard. Shape varies by
/// shots-vs-par delta:
/// - d ≤ -1 (birdie+): **circle**, red border + red text
/// - d == 0  (par):    plain number, no border, ink text
/// - d == +1 (bogey):  **square**, ink border, ink text
/// - d ≥ +2 (double+): **square**, red border, red text
struct ScoreBadge: View {
    let score: Int
    let par: Int

    @Environment(\.palette) private var palette

    var body: some View {
        let delta = score - par
        let shape = shapeFor(delta: delta)
        let color = colorFor(delta: delta)

        Group {
            switch shape {
            case .none:
                Text("\(score)")
                    .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                    .foregroundStyle(color)
                    .tabularNumerals()
            case .circle:
                Text("\(score)")
                    .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                    .foregroundStyle(color)
                    .tabularNumerals()
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(color, lineWidth: 1.5))
            case .square:
                Text("\(score)")
                    .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                    .foregroundStyle(color)
                    .tabularNumerals()
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(color, lineWidth: 1.5)
                    )
            }
        }
    }

    private enum BadgeShape { case none, circle, square }

    private func shapeFor(delta: Int) -> BadgeShape {
        if delta <= -1 { return .circle }
        if delta == 0 { return .none }
        return .square  // +1 bogey or +2 double+
    }

    private func colorFor(delta: Int) -> Color {
        // Birdie (circle) + double+ (square red) → red. Par + bogey → ink.
        if delta <= -1 || delta >= 2 { return palette.red }
        return palette.ink
    }
}

#Preview {
    HStack(spacing: 12) {
        ScoreBadge(score: 2, par: 3)  // birdie (circle red)
        ScoreBadge(score: 4, par: 4)  // par (plain ink)
        ScoreBadge(score: 5, par: 4)  // bogey (square ink)
        ScoreBadge(score: 7, par: 4)  // triple+ (square red)
    }
    .padding(40)
    .background(PaletteValues.light.paper)
    .environment(\.palette, .light)
}
