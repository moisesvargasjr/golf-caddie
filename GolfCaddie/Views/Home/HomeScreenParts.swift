import SwiftUI

/// What a Home layout shows, resolved by `HomeView`.
struct HomeContent {
    let snapshot: HomeData.Snapshot
    let bag: [Club]
    let inPlayCount: Int
    let watch: WatchLinkStatus
    let glassesEnabled: Bool
    let courseLabel: String
    let actionError: String?
    let loadError: String?

    var bagCount: Int { bag.count }
    var clubsText: String { HomeViewModel.clubsRowText(inPlay: inPlayCount, total: bagCount) }
}

/// What a Home layout can ask `HomeView` to do.
struct HomeActions {
    /// Open the clubs in play (inline bag panel when open wide, sheet otherwise).
    let openBag: () -> Void
    /// Edit the bag itself (Bag Setup).
    let editBag: () -> Void
    let pickCourse: () -> Void
    let begin: () -> Void
    /// Reload after a round is deleted from its review.
    let refresh: () -> Void
}

/// Pushes a finished round: its card, then a hole's review on the map
/// (`FinishedRoundScreen`).
struct HomeRoundLink<Label: View>: View {
    let round: Round
    let bag: [Club]
    let onDeleted: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            FinishedRoundScreen(round: round, bag: bag, onDeleted: onDeleted)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

/// Last entry (tappable) or the empty state.
struct HomeLastEntrySlot: View {
    let content: HomeContent
    let style: HomeCopyStyle
    let onDeleted: () -> Void

    var body: some View {
        if let entry = content.snapshot.lastEntry {
            HomeRoundLink(round: entry.round, bag: content.bag, onDeleted: onDeleted) {
                HomeLastEntryCard(entry: entry, style: style)
            }
            .accessibilityIdentifier(HomeID.lastEntry)
        } else {
            HomeEmptyEntry()
        }
    }
}

/// Red error line under the start controls.
struct HomeErrorLine: View {
    let message: String?

    @Environment(\.palette) private var palette

    var body: some View {
        if let message {
            Text(message)
                .font(AppFont.micro)
                .tracking(1.2)
                .foregroundStyle(palette.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(HomeID.error)
        }
    }
}

/// The Duo's hinge line, faint and dashed, as the open mockup draws it.
struct HomeHingeLine: View {
    let windowSize: CGSize

    @Environment(\.palette) private var palette

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: windowSize.width / 2, y: 0))
            path.addLine(to: CGPoint(x: windowSize.width / 2, y: windowSize.height))
        }
        .stroke(palette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
