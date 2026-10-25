import SwiftUI

/// Home on the open Duo held wide (Home-Open mockup). Left page: settings and
/// status, the bag (tap → clubs in play, inline on the same page) and Start a
/// round. Right page: number, date, title, last entry and earlier rounds.
/// Both pages come from `HomeLayout.pages` (SafeChrome regions), so nothing
/// sits within 24 pt of an edge or on the hinge band.
struct HomeOpenLayout: View {
    let content: HomeContent
    let actions: HomeActions
    @Binding var bag: [Club]
    @Binding var startState: HomeStartState
    @Binding var clubsLeftOut: [String]
    @Binding var bagPanelOpen: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        // The outer reader respects the safe area, so its insets are real (the
        // status bar's clock on the open Duo); the inner one ignores it for
        // the whole window. An ignoring reader reports zero insets, which let
        // the date run under the clock.
        GeometryReader { safe in
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    HomeHingeLine(windowSize: size)
                    if let pages = HomeLayout.pages(windowSize: size, safeArea: safe.safeAreaInsets) {
                        leftPage
                            .frame(width: pages.left.width, height: pages.left.height, alignment: .top)
                            .position(x: pages.left.midX, y: pages.left.midY)
                        rightPage
                            .frame(width: pages.right.width, height: pages.right.height, alignment: .top)
                            .position(x: pages.right.midX, y: pages.right.midY)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HomeID.openWide)
    }

    // MARK: Left page

    private var leftPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HomeSettingsButton(bag: $bag)
                HomeStatusIndicators(watch: content.watch, glassesEnabled: content.glassesEnabled,
                                     style: .open)
                Spacer(minLength: 0)
            }
            if bagPanelOpen {
                bagPanel
            } else {
                bagButton
                Spacer(minLength: 8)
                HomeErrorLine(message: content.actionError ?? content.loadError)
                HomeStartPanel(
                    state: $startState,
                    style: .open,
                    courseLabel: content.courseLabel,
                    clubsText: content.clubsText,
                    beginSubtitle: startState.beginSubtitle(clubsInPlay: content.inPlayCount, style: .open),
                    onCourse: actions.pickCourse,
                    onClubs: actions.openBag,
                    onBegin: actions.begin
                )
            }
        }
    }

    private var bagButton: some View {
        Button(action: actions.openBag) {
            HStack(spacing: 14) {
                HomeBagIllustration()
                    .frame(width: 150)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The Bag")
                        .font(.custom(AppFont.serifName, size: 26).weight(.bold).italic())
                        .foregroundStyle(palette.ink)
                    HomeMonoLabel(text: HomeViewModel.bagInPlayText(inPlay: content.inPlayCount,
                                                                    total: content.bagCount),
                                  size: 11, tracking: 0.8, color: palette.ink)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(.custom(AppFont.serifName, size: 30).weight(.bold))
                    .foregroundStyle(palette.ink)
                    .padding(.trailing, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 190, alignment: .leading)
            .background(palette.paper, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
            .compositingGroup()
            .shadow(color: palette.cardShadow.color, radius: 0, x: 3, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeViewModel.bagAccessibilityLabel(inPlay: content.inPlayCount,
                                                                total: content.bagCount))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(HomeID.bag)
    }

    /// The clubs in play, on the bag's own page (a system sheet would cross
    /// the hinge). Wraps `ClubsInPlaySheet`; its ‹ DONE closes the panel.
    private var bagPanel: some View {
        VStack(spacing: 0) {
            ClubsInPlaySheet(bag: content.bag, leftOut: $clubsLeftOut,
                             onDone: { bagPanelOpen = false })
            Button(action: actions.editBag) {
                HomeMonoLabel(text: "EDIT THE BAG ›", size: 10, tracking: 1, color: palette.ink)
                    .frame(maxWidth: .infinity, minHeight: SafeChrome.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 1.5) }
            .accessibilityIdentifier(HomeID.bagEditor)
        }
        .background(palette.paper.opacity(0.98))
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
        .compositingGroup()
        .shadow(color: palette.cardShadow.color, radius: 0, x: 4, y: 4)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HomeID.bagPanel)
    }

    // MARK: Right page

    private var rightPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HomeProfileButton()
                Spacer(minLength: 8)
                HomeMonoLabel(text: HomeViewModel.dateStrip(Date(), style: .open), size: 10, tracking: 1)
            }
            HomeMasthead(style: .open)
            HomeLastEntrySlot(content: content, style: .open, onDeleted: actions.refresh)
            earlierRounds
            Spacer(minLength: 0)
        }
    }

    private var earlierRounds: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Earlier rounds")
                    .font(.custom(AppFont.serifName, size: 16).weight(.bold).italic())
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HomeLogbookLink(bag: content.bag, roundCount: content.snapshot.roundCount, inline: true)
            }
            ForEach(content.snapshot.earlierRounds) { entry in
                HomeRoundLink(round: entry.round, bag: content.bag, onDeleted: actions.refresh) {
                    earlierRow(entry)
                }
                .accessibilityIdentifier(HomeID.earlierRound)
            }
        }
    }

    private func earlierRow(_ entry: HomeRoundEntry) -> some View {
        HStack(spacing: 10) {
            HomeMonoLabel(text: entry.dateText, size: 10, tracking: 0)
                .frame(width: 54, alignment: .leading)
            Text(entry.courseTitle)
                .font(.custom(AppFont.serifName, size: 15))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.score > 0 ? "\(entry.score)" : "—")
                .font(.custom(AppFont.serifName, size: 18).weight(.bold))
                .tabularNumerals()
                .frame(width: 40, alignment: .trailing)
            Text("›")
                .font(.custom(AppFont.serifName, size: 18).weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: SafeChrome.minTapTarget)
        .background(palette.paper, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
        .padding(.top, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
