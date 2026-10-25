import SwiftUI

/// Home in one column (Home-Folded mockup): last entry up top, Start a round
/// at the bottom in thumb reach. Also used, until they are designed, for the
/// regular iPhone and the open Duo held portrait (a centred readable column
/// there, via `readableOnExpanded`). Scrolls only when the window is too
/// short (iPhone landscape).
struct HomeSingleLayout: View {
    let content: HomeContent
    let actions: HomeActions
    @Binding var bag: [Club]
    @Binding var startState: HomeStartState

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                column
                    .padding(.horizontal, SafeChrome.edgeInset)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .readableOnExpanded()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HomeID.single)
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            HStack(alignment: .bottom) {
                HomeMasthead(style: .folded)
                Spacer(minLength: 8)
                HomeMonoLabel(text: HomeViewModel.dateStrip(Date(), style: .folded), tracking: 1)
                    .padding(.bottom, 4)
            }
            HomeLastEntrySlot(content: content, style: .folded, onDeleted: actions.refresh)
            bagAndLogbook
            Spacer(minLength: 8)
            HomeErrorLine(message: content.actionError ?? content.loadError)
            HomeStartPanel(
                state: $startState,
                style: .folded,
                courseLabel: content.courseLabel,
                clubsText: content.clubsText,
                beginSubtitle: startState.beginSubtitle(clubsInPlay: content.inPlayCount, style: .folded),
                onCourse: actions.pickCourse,
                onClubs: actions.openBag,
                onBegin: actions.begin
            )
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            HomeProfileButton()
            Spacer(minLength: 4)
            HomeStatusIndicators(watch: content.watch, glassesEnabled: content.glassesEnabled,
                                 style: .folded)
            HomeSettingsButton(bag: $bag)
        }
    }

    /// THE BAG and LOGBOOK as boxed navigation buttons (Home-Folded-Buttons).
    private var bagAndLogbook: some View {
        HStack(spacing: 8) {
            Button(action: actions.editBag) {
                HomeNavBox(title: "THE BAG",
                           subtitle: HomeViewModel.bagInPlayText(inPlay: content.inPlayCount, total: content.bagCount))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("The bag, \(content.inPlayCount) of \(content.bagCount) clubs in play. Edit the bag.")
            .accessibilityIdentifier(HomeID.bag)
            HomeLogbookLink(bag: content.bag, roundCount: content.snapshot.roundCount)
        }
    }
}
