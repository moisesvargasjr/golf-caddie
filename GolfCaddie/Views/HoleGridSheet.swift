import SwiftUI

/// Jump to any hole during a round — a grid of 1–18 showing which are played,
/// current, started-but-open (skipped), and not yet visited. Tapping a hole
/// navigates there (returning to a skipped hole keeps its shots).
struct HoleGridSheet: View {
    let currentHole: Int
    let holes: [Hole]
    let onPick: (Int) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette

    private enum HoleState { case current, played, open, unvisited }

    private var byNumber: [Int: Hole] {
        Dictionary(holes.map { ($0.holeNumber, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func state(_ n: Int) -> HoleState {
        if n == currentHole { return .current }
        guard let hole = byNumber[n] else { return .unvisited }
        return hole.confirmedAt != nil ? .played : .open
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    masthead

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(1...18, id: \.self) { n in
                            cell(n)
                        }
                    }

                    legend
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .background(PaperBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        Text("‹ DONE")
                            .font(AppFont.metadata).tracking(1.4)
                            .foregroundStyle(palette.ink)
                    }
                }
            }
        }
        .themedRoot()
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Stamp(text: "Caddie")
            ItalicHeadline(
                lines: ["Jump to", "a hole."],
                font: AppFont.masthead,
                color: palette.ink,
                tracking: -2,
                lineSpacing: -6
            )
            .padding(.top, 12)
        }
    }

    private func cell(_ n: Int) -> some View {
        let s = state(n)
        return Button {
            onPick(n)
        } label: {
            Text("\(n)")
                .font(.custom(AppFont.serifName, size: 22).italic().weight(.bold))
                .foregroundStyle(foreground(s))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(s == .current ? palette.ink : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(border(s), lineWidth: s == .unvisited ? 1 : 1.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private func foreground(_ s: HoleState) -> Color {
        switch s {
        case .current: palette.paper
        case .played: palette.ink
        case .open: palette.ink2
        case .unvisited: palette.ink3
        }
    }

    private func border(_ s: HoleState) -> Color {
        switch s {
        case .current: palette.ink
        case .played: palette.ink
        case .open: palette.flag
        case .unvisited: palette.rule
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            legendRow(color: palette.ink, fill: true, text: "Current hole")
            legendRow(color: palette.ink, fill: false, text: "Played")
            legendRow(color: palette.flag, fill: false, text: "Started — tap to return")
            legendRow(color: palette.rule, fill: false, text: "Not yet played")
        }
        .padding(.top, 4)
    }

    private func legendRow(color: Color, fill: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill ? color : Color.clear)
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 1.4))
            Text(text)
                .font(AppFont.micro).tracking(1.0)
                .foregroundStyle(palette.ink2)
        }
    }
}
