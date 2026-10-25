import SwiftUI

/// Home while no round is active; the round map screen while one is. Owns
/// the round-level sheets (card, hole grid, clubs in play, course picker) and
/// the end-of-round flow; everything on the hole lives in `RoundMapScreen`.
struct ActiveRoundView: View {
    let controller: RoundController
    let location: LocationManager
    @Binding var bag: [Club]

    @State private var actionError: String?
    @State private var endedRoundForReview: Round?
    @State private var showEndRoundConfirm = false
    @State private var showCoursePicker = false
    @State private var showHoleGrid = false
    @State private var curatedCourses: [CuratedCourse] = []
    @State private var showScorecard = false
    @State private var showClubsInPlay = false
    /// The hole on screen; nil follows the live hole.
    @State private var viewedHole: Int?
    @State private var question: RoundMapQuestion?

    var body: some View {
        Group {
            if controller.isActive {
                activeBody
            } else {
                idleBody
            }
        }
        // Push (not sheet) so HoleDetailView can stack on top of Summary. The
        // controller's `mostRecentlyEndedRound` survives across this push.
        .navigationDestination(isPresented: endedRoundBinding) {
            if let round = endedRoundForReview {
                RoundReviewView(
                    round: round,
                    bag: bag,
                    onResume: { resumeRound(round) },
                    onDismiss: {
                        endedRoundForReview = nil
                        controller.clearMostRecentlyEndedRound()
                    },
                    onDeleted: {
                        endedRoundForReview = nil
                        controller.clearMostRecentlyEndedRound()
                    }
                )
            }
        }
        .alert("End Round?", isPresented: $showEndRoundConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Round", role: .destructive) { performEndRound() }
        } message: {
            Text("Your round will be saved. You can resume it from the review screen if you change your mind.")
        }
        // Mid-round link / re-link to a curated course — the recovery for a
        // missed or wrong auto-detect. Routes through the controller so the
        // yardage, anchors and par auto-fill pick it up immediately.
        .sheet(isPresented: $showCoursePicker) {
            CoursePickerSheet(
                courses: curatedCourses,
                current: controller.curatedCourseId,
                onPick: { id in
                    controller.setCuratedCourseId(id)
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
    }

    private var idleBody: some View {
        HomeView(
            bag: $bag,
            onStartRound: { startRound($0) },
            actionError: actionError
        )
    }

    @ViewBuilder
    private var activeBody: some View {
        if let round = controller.currentRound {
            RoundMapScreen(
                mode: controller.isCasualMode ? .casual : .tracking,
                roundID: round.id,
                live: controller,
                curatedCourseId: controller.curatedCourseId,
                courseName: controller.curatedCourseId.flatMap { id in curatedCourses.first { $0.id == id }?.name },
                clubs: clubsInPlay,
                host: host,
                viewedHole: $viewedHole,
                question: $question
            )
            .onChange(of: round.id) { _, _ in viewedHole = nil }
            .sheet(isPresented: $showHoleGrid) {
                HoleGridSheet(
                    currentHole: viewedHole ?? controller.currentHole?.holeNumber ?? 1,
                    holes: controller.holesForCurrentRound(),
                    onPick: { number in
                        pickFromGrid(number, round: round)
                        showHoleGrid = false
                    },
                    onCancel: { showHoleGrid = false }
                )
            }
            .sheet(isPresented: $showClubsInPlay) {
                ClubsInPlaySheet(
                    bag: bag,
                    leftOut: Binding(
                        get: { controller.currentRound?.clubsLeftOut ?? [] },
                        set: { new in
                            controller.setClubsLeftOut(new)
                            // A mid-round fix is the best guess for next round too.
                            UserDefaults.standard.set(controller.currentRound?.clubsLeftOut ?? [],
                                                      forKey: ClubsInPlay.leftOutDefaultsKey)
                        }
                    ),
                    onDone: { showClubsInPlay = false }
                )
            }
            // One presentation for every layout, so folding/unfolding while the
            // card is open swaps the card variant instead of dismissing it.
            // Opening a hole from the card goes there on the round map (a
            // finished hole is viewed; an unplayed one becomes the live hole).
            .fullScreenCover(isPresented: $showScorecard) {
                AdaptiveScorecardPresentation(
                    round: round,
                    currentHoleNumber: controller.currentHole?.holeNumber ?? 1,
                    curatedCourseId: controller.curatedCourseId,
                    live: controller,
                    onOpenHole: { number in
                        pickFromGrid(number, round: round)
                        showScorecard = false
                    },
                    onDismiss: { showScorecard = false }
                )
            }
            // `onAppear`, not `.task`: GRDB's sync dispatch inside
            // `CourseDataRepository.allCourses` trips Swift's concurrency
            // check when run inside a `.task` closure.
            .onAppear {
                curatedCourses = (try? CourseDataRepository.allCourses()) ?? []
                #if DEBUG
                openDebugScreen()
                #endif
            }
        }
    }

    private var host: RoundMapHost {
        RoundMapHost(
            openCard: { showScorecard = true },
            openBag: { showClubsInPlay = true },
            openHoleGrid: { showHoleGrid = true },
            linkCourse: { showCoursePicker = true },
            unlinkCourse: { controller.setCuratedCourseId(nil) },
            toggleCasual: { controller.setCasualMode(!controller.isCasualMode) },
            endRound: { showEndRoundConfirm = true }
        )
    }

    /// The bag minus what this round left home — the in-round club list.
    private var clubsInPlay: [Club] {
        ClubsInPlay.resolve(bag: bag, leftOut: controller.currentRound?.clubsLeftOut ?? [])
    }

    private func pickFromGrid(_ number: Int, round: Round) {
        let row = controller.holesForCurrentRound().first { $0.holeNumber == number }
        let finished = row.map { $0.confirmedAt != nil || $0.isHandScored } ?? false
        let beforeStart = round.startingHole.map { number < $0 } ?? false
        switch HoleNavigation.gridPick(number, live: controller.currentHole?.holeNumber,
                                       isFinished: finished, isBeforeStart: beforeStart) {
        case let .view(hole): viewedHole = hole
        case .live: viewedHole = nil
        case .skipAhead:
            viewedHole = nil
            controller.goToHole(number)
        }
    }

    #if DEBUG
    /// `-DebugOpen review|penalty|card|bag|course|grid|casual|casual-finish`
    /// for screenshots (`review` now opens the putts question that replaced
    /// the review sheet; `casual` is started by `DebugHarness`, and
    /// `casual-finish` also opens its score grid).
    private func openDebugScreen() {
        switch DebugHarness.openScreen {
        case "review", "finish", "putts": question = .putts
        case "casual-finish", "score": question = .score
        case "penalty": question = .penalty
        case "card": showScorecard = true
        case "bag": showClubsInPlay = true
        case "course": showCoursePicker = true
        case "grid": showHoleGrid = true
        default: break
        }
        if UserDefaults.standard.bool(forKey: "DebugShowHoleGrid") { showHoleGrid = true }
        // `-DebugViewHole N`: open hole N as a grid pick would (a hole before
        // a late start shows iPhone-PastHole's score entry).
        let viewHole = UserDefaults.standard.integer(forKey: "DebugViewHole")
        if HoleScoring.holeRange.contains(viewHole), let round = controller.currentRound {
            pickFromGrid(viewHole, round: round)
        }
    }
    #endif

    /// `navigationDestination(isPresented:)` wants a `Binding<Bool>`; any
    /// ended round pushes, and dismissing clears it.
    private var endedRoundBinding: Binding<Bool> {
        Binding(
            get: { endedRoundForReview != nil },
            set: { isShown in
                if !isShown {
                    endedRoundForReview = nil
                    controller.clearMostRecentlyEndedRound()
                }
            }
        )
    }

    private func startRound(_ request: HomeStartRequest) {
        actionError = nil
        do {
            try controller.startRound(request)
            viewedHole = nil
            question = nil
        } catch {
            actionError = "Couldn't start round: \(error.localizedDescription)"
        }
    }

    private func performEndRound() {
        actionError = nil
        let toReview = controller.currentRound
        do {
            try controller.endRound()
            viewedHole = nil
            question = nil
            endedRoundForReview = toReview
        } catch {
            actionError = "Couldn't end round: \(error.localizedDescription)"
        }
    }

    private func resumeRound(_ round: Round) {
        actionError = nil
        do {
            try controller.resumeRound(round)
            endedRoundForReview = nil
            viewedHole = nil
        } catch {
            actionError = "Couldn't resume: \(error.localizedDescription)"
        }
    }
}
