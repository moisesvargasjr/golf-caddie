import SwiftUI

/// A bordered "paper" card with a hard offset shadow — the printed-card-sitting-
/// on-a-desk feel from the design handoff. cornerRadius 2 keeps the printed
/// look (not iOS-default 12).
///
/// Use everywhere the prototype renders a PaperCard: hole pill, distance card,
/// expanded-mode collapse button, lying stamp, etc.
struct PaperCard<Content: View>: View {
    @Environment(\.palette) private var palette

    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    var background: Color? = nil   // defaults to palette.paper
    @ViewBuilder var content: () -> Content

    var body: some View {
        let bg = background ?? palette.paper
        content()
            .padding(padding)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(palette.ink, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .paperCardShadow(palette.cardShadow)
    }
}

extension PaperCard {
    /// Convenience initializer with uniform padding.
    init(padding: CGFloat, background: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.padding = EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        self.background = background
        self.content = content
    }
}

#Preview {
    VStack(spacing: 16) {
        PaperCard {
            Text("TO PIN")
                .font(AppFont.stamp)
                .tracking(1.4)
        }
        PaperCard(padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)) {
            Text("Hole I")
                .font(AppFont.bodyLarge)
                .italic()
        }
    }
    .padding(40)
    .background(PaletteValues.light.paper)
    .environment(\.palette, .light)
}
