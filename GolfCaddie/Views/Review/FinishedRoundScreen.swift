import SwiftUI

/// A finished round (Duo v2 plan rule 12), from the Logbook, Home's last
/// entry or End round: the round's card first (`ScorecardScreen`); tap a hole
/// and the same round map screen opens in review on that hole
/// (`RoundMapScreen(.review)`, `live: nil`, so every edit goes through
/// `HoleSession`'s repository path). ‹ CARD — or Back to card › on the last
/// hole — returns to the card. The round actions (share, resume, course,
/// delete) live in the review's ···.
///
/// PR 8 adds the card's MAP: `FinishedRoundRoute` gains `.course`, and the
/// card → hole step glides the same map in instead of swapping screens.
struct FinishedRoundScreen: View {
    let bag: [Club]
    /// A live round is on: no resume, no delete (normally unreachable — the
    /// logbook is only reachable from Home).
    let liveRoundActive: Bool
    /// Resume the round; only the review pushed right after End round has one.
    let onResume: (() -> Void)?
    /// ‹ LOGBOOK; nil pops this screen.
    let onClose: (() -> Void)?
    /// After a delete (the caller refreshes its list).
    let onDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var round: Round
    @State private var route: FinishedRoundRoute
    @State private var question: RoundMapQuestion?
    @State private var curatedCourses: [CuratedCourse] = []
    @State private var showCoursePicker = false
    @State private var showDeleteConfirm = false
    @State private var sharing: ShareItems?
    @State private var actionError: String?

    /// `initialHole` opens straight on that hole's review (DEBUG launches).
    init(round: Round, bag: [Club], initialHole: Int? = nil, liveRoundActive: Bool = false,
         onResume: (() -> Void)? = nil, onClose: (() -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        _round = State(initialValue: round)
        _route = State(initialValue: .initial(hole: initialHole))
        self.bag = bag
        self.liveRoundActive = liveRoundActive
        self.onResume = onResume
        self.onClose = onClose
        self.onDeleted = onDeleted
    }

    var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            // `onAppear`, not `.task`: GRDB's sync reads trap in a `.task`.
            .onAppear { curatedCourses = (try? CourseDataRepository.allCourses()) ?? [] }
            .sheet(isPresented: $showCoursePicker) { coursePicker }
            .sheet(item: $sharing) { ShareSheet(items: $0.items) }
            .alert("Delete this round?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { performDelete() }
            } message: {
                Text("\(courseLabel) and all its holes, shots, and penalties will be permanently deleted.")
            }
            .alert("Something went wrong", isPresented: errorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch route.screen {
        case .card:
            ScorecardScreen(round: round, currentHoleNumber: nil, curatedCourseId: round.curatedCourseId,
                            live: nil, onDismiss: close,
                            onOpenHole: { number in route = route.openingHole(number) },
                            roundMenu: AnyView(CardRoundActionsButton(availability: availability,
                                                                      title: menuTitle,
                                                                      handlers: actionHandlers)))
        case .hole:
            RoundMapScreen(
                mode: .review,
                roundID: round.id,
                live: nil,
                curatedCourseId: round.curatedCourseId,
                courseName: linkedCourseName ?? round.courseName,
                clubs: ClubsInPlay.resolve(bag: bag, leftOut: round.clubsLeftOut ?? []),
                host: host,
                viewedHole: viewedHole,
                question: $question
            )
        }
    }

    /// The map screen's hole is the route's; ‹ › and Next hole move the route.
    private var viewedHole: Binding<Int?> {
        Binding(
            get: { route.reviewHole },
            set: { hole in route = hole.map { route.openingHole($0) } ?? route.backToCard() }
        )
    }

    private var host: RoundMapHost {
        RoundMapHost(
            openCard: backToCard,
            openHoleGrid: backToCard,
            linkCourse: { showCoursePicker = true },
            unlinkCourse: { setCourse(nil) },
            roundDate: round.startedAt,
            roundActions: availability,
            roundActionHandlers: actionHandlers
        )
    }

    private var actionHandlers: RoundActionHandlers {
        RoundActionHandlers(
            share: share,
            resume: { onResume?() },
            changeCourse: { showCoursePicker = true },
            unlinkCourse: { setCourse(nil) },
            delete: { showDeleteConfirm = true }
        )
    }

    /// The card's ··· header ("NATIVE OAKS"); the review's adds the score.
    private var menuTitle: String {
        (linkedCourseName ?? round.courseName).flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "THIS ROUND"
    }

    private var availability: RoundActionsAvailability {
        RoundActionsAvailability.resolve(round: round, canResumeHere: onResume != nil,
                                         liveRoundActive: liveRoundActive, linkedCourseName: linkedCourseName)
    }

    private var linkedCourseName: String? {
        round.curatedCourseId.flatMap { id in curatedCourses.first { $0.id == id }?.name }
    }

    private var courseLabel: String {
        round.courseName.flatMap { $0.isEmpty ? nil : $0 } ?? "This round"
    }

    private var coursePicker: some View {
        CoursePickerSheet(
            courses: curatedCourses,
            current: round.curatedCourseId,
            onPick: { id in
                setCourse(id)
                showCoursePicker = false
            },
            onCancel: { showCoursePicker = false },
            onRefresh: {
                // B29: pull-to-refresh bypasses the hourly catalog throttle.
                await CourseSyncClient.shared.syncIfStale(force: true)
                let fresh = await CourseDataRepository.allCoursesFromAsyncContext()
                curatedCourses = fresh
                return fresh
            }
        )
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    // MARK: Actions

    private func backToCard() {
        question = nil
        route = route.backToCard()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func setCourse(_ id: String?) {
        do {
            round = try FinishedRoundActions.settingCourse(id, on: round, courses: curatedCourses)
        } catch {
            actionError = "Couldn't set the course: \(error.localizedDescription)"
        }
    }

    private func share() {
        do {
            sharing = ShareItems(items: try FinishedRoundActions.shareItems(for: round))
        } catch {
            actionError = "Couldn't share the round: \(error.localizedDescription)"
        }
    }

    private func performDelete() {
        do {
            try FinishedRoundActions.delete(round)
            onDeleted?()
            if onClose == nil { dismiss() }
        } catch {
            actionError = "Delete failed: \(error.localizedDescription)"
        }
    }
}
