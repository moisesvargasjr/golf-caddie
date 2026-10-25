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
        // The round just ended: its card, then any hole's review on the map
        // (`FinishedRoundScreen`). The only place Resume is offered. The
        // controller's `mostRecentlyEndedRound` survives across this push.
        .navigationDestination(isPresented: endedRoundBinding) {
            if let round = endedRoundForReview {
                FinishedRoundScreen(
                    round: round,
                    bag: bag,
                    liveRoundActive: controller.isActive,
                    onResume: { resumeRound(round) },
                    onClose: closeEndedRound,
                    onDeleted: closeEndedRound
                )
            }
        }
        // End round asks once: the holes not reached are marked not played
        // (on by default), or left empty to add later (EndRound-NotPlayed).
        .sheet(isPresented: $showEndRoundConfirm) {
            EndRoundSheet(summary: endRoundSummary(), onCancel: { showEndRoundConfirm = false },
                          onEnd: { holes in
                              showEndRoundConfirm = false
                              performEndRound(markingNotPlayed: holes)
                          })
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
    /// `-DebugOpen review|penalty|card|bag|course|grid|end|casual|casual-finish`
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
        case "end", "end-round": showEndRoundConfirm = true
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

    private func closeEndedRound() {
        endedRoundForReview = nil
        controller.clearMostRecentlyEndedRound()
    }

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

    /// What End round shows: the course, the holes scored so far and their
    /// total, and the holes still to play (`HoleScoring.remainingUnscored`).
    private func endRoundSummary() -> EndRoundSummary {
        let round = controller.currentRound
        let holes = controller.holesForCurrentRound()
        var scored: [Int: (score: Int, par: Int?)] = [:]
        for hole in holes {
            let counts = hole.confirmedAt != nil || (hole.isHandScored && hole.handStrokes != nil)
            guard counts else { continue }
            let shots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
            let pens = ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? []).totalStrokes
            if let score = HoleScoring.score(hole: hole, shots: shots, penaltyStrokes: pens) {
                scored[hole.holeNumber] = (score, hole.par)
            }
        }
        var started = Set(scored.keys)
        // The live hole with shots on it was played, just not finished.
        if let live = controller.currentHole, !controller.currentHoleShots.isEmpty { started.insert(live.holeNumber) }
        let remaining = controller.currentHole.map {
            HoleScoring.remainingUnscored(liveHole: $0.holeNumber, startingHole: round?.startingHole,
                                          scored: started)
        } ?? []
        return EndRoundSummary(courseName: round?.courseName, scored: scored.mapValues(\.score),
                               pars: scored.compactMapValues(\.par), remaining: remaining)
    }

    private func performEndRound(markingNotPlayed holes: [Int] = []) {
        actionError = nil
        let toReview = controller.currentRound
        do {
            try controller.endRound(markingNotPlayed: holes)
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

// MARK: - End round

/// End round's numbers (pure, `EndRoundSheetTests`).
struct EndRoundSummary: Equatable {
    var courseName: String?
    /// Hole number → score, for the holes scored so far.
    var scored: [Int: Int]
    /// Hole number → par, where known.
    var pars: [Int: Int]
    /// The holes not reached yet, in play order.
    var remaining: [Int]

    /// "61 (+5)" (to par over the holes with one), "61", or nil before a score.
    var scoreText: String? {
        guard !scored.isEmpty else { return nil }
        let total = scored.values.reduce(0, +)
        let rated = scored.filter { pars[$0.key] != nil }
        guard !rated.isEmpty else { return "\(total)" }
        let toPar = rated.reduce(0) { $0 + $1.value - (pars[$1.key] ?? 0) }
        return "\(total) (\(RoundMapFormat.toPar(toPar)))"
    }

    /// "NATIVE OAKS · 14 HOLES SCORED · 61 (+5)".
    var headline: String {
        let holes = "\(scored.count) \(scored.count == 1 ? "HOLE" : "HOLES") SCORED"
        return [courseName?.uppercased(), holes, scoreText].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Mark holes 15–18 not played" / "Mark hole 18 not played".
    var markTitle: String {
        "Mark \(remaining.count == 1 ? "hole" : "holes") \(ScorecardText.holeList(remaining)) not played"
    }

    /// The line over the buttons: "14 OF 18 PLAYED · 61 (+5) · NOT COMPLETE".
    func footer(marking: Bool) -> String {
        guard !remaining.isEmpty else { return ["ALL 18 SCORED", scoreText].compactMap { $0 }.joined(separator: " · ") }
        let parts = marking
            ? ["\(18 - remaining.count) OF 18 PLAYED", scoreText, "NOT COMPLETE"]
            : ["\(scored.count) OF 18 SCORED", "\(remaining.count) TO ADD", "NOT COMPLETE"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// "End the round?" across the bottom. When holes are left it offers to mark
/// them not played (NP on the card, out of every total), on by default; off
/// leaves them empty (ADD) to fill in later.
struct EndRoundSheet: View {
    let summary: EndRoundSummary
    let onCancel: () -> Void
    let onEnd: ([Int]) -> Void
    @State private var marking = true
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("End the round?")
                    .font(RoundFont.serifItalic(28).weight(.bold))
                    .foregroundStyle(palette.ink)
                StampLabel(text: summary.headline, size: 10)
            }
            if !summary.remaining.isEmpty {
                markToggle
                holeStrip
            }
            StampLabel(text: summary.footer(marking: marking && !summary.remaining.isEmpty), size: 11,
                       color: palette.ink)
            Text("You can resume the round from its card's ··· menu.")
                .font(RoundFont.serifItalic(13))
                .foregroundStyle(palette.ink2)
            HStack(spacing: 8) {
                OutlineActionButton(title: "CANCEL", fontSize: 11, minHeight: 56, action: onCancel)
                    .frame(width: 120)
                PrimaryActionButton(title: "End round", fontSize: 20, minHeight: 56) {
                    onEnd(marking ? summary.remaining : [])
                }
                .accessibilityIdentifier("endRound.confirm")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.paper)
        .accessibilityIdentifier("endRound.sheet")
    }

    private var markToggle: some View {
        Button { marking.toggle() } label: {
            HStack(spacing: 12) {
                Text(marking ? "✓" : "")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.paper)
                    .frame(width: 30, height: 30)
                    .background(marking ? palette.ink : Color.clear, ignoresSafeAreaEdges: [])
                    .overlay { if !marking { Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule) } }
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.markTitle)
                        .font(RoundFont.serif(18))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(marking ? "Shown as NP on the card and left out of every total."
                                 : "Left empty: you can add their scores later.")
                        .font(RoundFont.serifItalic(13))
                        .foregroundStyle(palette.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(marking ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("endRound.markNotPlayed")
    }

    /// The holes left, NP struck through (marking) or ADD.
    private var holeStrip: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: min(6, summary.remaining.count))
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(summary.remaining, id: \.self) { n in
                VStack(spacing: 2) {
                    StampLabel(text: "HOLE \(n)", size: 9)
                    if marking {
                        Text("NP").font(RoundFont.mono(13)).foregroundStyle(palette.ink2)
                    } else {
                        Text("ADD").font(RoundFont.mono(13)).foregroundStyle(palette.red)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background {
                    if marking {
                        GeometryReader { geo in
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: geo.size.height))
                                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                            }
                            .stroke(palette.ink.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                }
                .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: 0.5))
            }
        }
        .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
        .accessibilityHidden(true)
    }
}
