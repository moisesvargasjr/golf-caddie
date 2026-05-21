import SwiftUI

/// Newspaper-style divider — a 2pt ink line, 3pt gap, 1pt ink line. Used in
/// the Round Summary masthead-to-score transition.
struct DoubleRule: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 3) {
            Rectangle()
                .fill(palette.ink)
                .frame(height: 2)
            Rectangle()
                .fill(palette.ink)
                .frame(height: 1)
        }
    }
}

/// Single hairline rule, optionally muted. Used between scorecard sections
/// and as the home-screen masthead divider.
struct SingleRule: View {
    enum Weight { case hairline, thin, medium }

    var weight: Weight = .thin
    var opacity: Double = 1.0

    @Environment(\.palette) private var palette

    var body: some View {
        let h: CGFloat = {
            switch weight {
            case .hairline: return 1
            case .thin:     return 1.5
            case .medium:   return 2
            }
        }()
        Rectangle()
            .fill(palette.ink.opacity(opacity))
            .frame(height: h)
    }
}
