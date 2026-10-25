import SwiftUI

/// The one scorecard entry for the live round (CARD) and finished rounds
/// (Duo v2 PR 6). Picks the card from the display — the traditional card on
/// the open Duo held wide, front over back on the open Duo held tall, nine
/// tabs on the folded Duo and iPhone portrait, a paper card on iPhone
/// landscape — and follows a fold/unfold while it is open.
///
/// Picking a hole offers one action: ADD (or edit) a hand score, open the hole
/// (`onOpenHole`; hidden without one), or go back to the live hole.
struct ScorecardScreen: View {
    let round: Round
    /// The live hole; nil for a finished round.
    let currentHoleNumber: Int?
    let curatedCourseId: String?
    /// The live round's controller, so a hand score on the live hole routes
    /// through it. nil for finished rounds.
    let live: LiveHoleEditing?
    let onDismiss: () -> Void
    /// Open hole n: in the live round, go to it on the map; a finished round
    /// opens the hole's review (`FinishedRoundScreen`). nil = the CTA hides.
    let onOpenHole: ((Int) -> Void)?
    /// The card's MAP button (PR 8: the whole-course map). nil = hidden.
    let onOpenCourseMap: (() -> Void)?
    /// ··· beside the header buttons (a finished round's round actions).
    let roundMenu: AnyView?

    @Environment(\.displayContext) private var display
    @State private var snapshot = ScorecardSnapshot(model: ScorecardModel(columns: [], hasStrokeIndex: false),
                                                    courseName: nil)
    @State private var selectedHole: Int?
    @State private var entry: CardScoreDraft?
    @State private var loadError: String?

    init(round: Round, currentHoleNumber: Int?, curatedCourseId: String?,
         live: LiveHoleEditing? = nil, onDismiss: @escaping () -> Void,
         onOpenHole: ((Int) -> Void)? = nil, onOpenCourseMap: (() -> Void)? = nil,
         roundMenu: AnyView? = nil) {
        self.round = round
        self.currentHoleNumber = currentHoleNumber
        self.curatedCourseId = curatedCourseId
        self.live = live
        self.onDismiss = onDismiss
        self.onOpenHole = onOpenHole
        self.onOpenCourseMap = onOpenCourseMap
        self.roundMenu = roundMenu
    }

    private var variant: ScorecardVariant { .resolve(display) }

    var body: some View {
        ZStack {
            CardInk.palette.paper.ignoresSafeArea()
            if snapshot.model.columns.isEmpty {
                loadingOrError
            } else {
                card(content)
            }
        }
        .environment(\.palette, CardInk.palette)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(variant.accessibilityID)
        .onAppear(perform: reload)
        // A CARD left open stays current when the watch logs a shot or
        // finishes a hole (or any other writer changes the round's scores).
        .task {
            do {
                for try await _ in ScoringChanges.values() { reload() }
            } catch {}
        }
        .sheet(item: $entry) { draft in
            HandScoreEntrySheet(draft: draft, startingHole: round.startingHole,
                                onSave: save, onCancel: { entry = nil })
        }
    }

    @ViewBuilder
    private func card(_ content: ScorecardContent) -> some View {
        switch variant {
        case .traditional:
            PhysicalScorecardView(content: content, selectedHole: $selectedHole)
        case .frontOverBack:
            ScorecardSplitView(content: content, selectedHole: $selectedHole)
        case .tabs:
            ScorecardTabsView(content: content, selectedHole: $selectedHole,
                              windowHeight: display.windowSize.height)
        case .landscapeCard:
            ScorecardLandscapeCard(content: content, selectedHole: $selectedHole)
        }
    }

    private var content: ScorecardContent {
        ScorecardContent(
            round: round, model: snapshot.model,
            courseName: snapshot.courseName ?? round.courseName ?? "Golf course",
            currentHole: currentHoleNumber, variant: variant,
            canOpenHole: onOpenHole != nil, loadError: loadError,
            onDismiss: onDismiss, onOpenCourseMap: onOpenCourseMap, onPick: perform,
            onSecondary: performSecondary, roundMenu: roundMenu)
    }

    private var loadingOrError: some View {
        VStack(spacing: 16) {
            Text(loadError ?? "Loading the card…")
                .font(CardInk.serif(17))
                .foregroundStyle(loadError == nil ? CardInk.ink2 : CardInk.palette.red)
                .multilineTextAlignment(.center)
            ScorecardOutlinedButton(title: ScorecardText.dismissTitle(variant: variant,
                                                                       currentHole: currentHoleNumber),
                                    action: onDismiss)
        }
        .padding(24)
    }

    // MARK: Actions

    private func perform(_ pick: ScorecardPick) {
        switch pick {
        case .addScore, .editScore, .notPlayed:
            if let column = snapshot.model.column(pick.holeNumber) {
                entry = CardScoreDraft(column: column)
            }
        case let .openHole(n):
            onOpenHole?(n)
        case .backToHole:
            onDismiss()
        case .notReached:
            break
        }
    }

    private func performSecondary(_ pick: ScorecardSecondaryPick) {
        let notPlayed: Bool = if case .markNotPlayed = pick { true } else { false }
        do {
            try HoleRepository.setNotPlayed(notPlayed, roundID: round.id, holeNumbers: [pick.holeNumber])
            reload()
        } catch {
            loadError = "Couldn't change hole \(pick.holeNumber): \(error.localizedDescription)"
        }
    }

    /// Returns a message to show in the sheet when the save fails.
    private func save(_ draft: CardScoreDraft) -> String? {
        do {
            try ScorecardLoader.saveHandScore(draft, roundID: round.id, live: live)
            entry = nil
            reload()
            return nil
        } catch {
            return "Couldn't save hole \(draft.holeNumber): \(error.localizedDescription)"
        }
    }

    private func reload() {
        do {
            snapshot = try ScorecardLoader.load(round: round, curatedCourseId: curatedCourseId)
            loadError = nil
        } catch {
            loadError = "Couldn't load the card: \(error.localizedDescription)"
        }
    }
}

/// Everything a card variant draws from, plus the actions it can take.
struct ScorecardContent {
    let round: Round
    let model: ScorecardModel
    let courseName: String
    let currentHole: Int?
    let variant: ScorecardVariant
    let canOpenHole: Bool
    var loadError: String? = nil
    let onDismiss: () -> Void
    let onOpenCourseMap: (() -> Void)?
    let onPick: (ScorecardPick) -> Void
    /// MARK NOT PLAYED / UNDO NOT PLAYED.
    var onSecondary: (ScorecardSecondaryPick) -> Void = { _ in }
    /// ··· with the round actions (finished rounds); nil = none.
    var roundMenu: AnyView? = nil

    var isFinished: Bool { round.endedAt != nil || currentHole == nil }
    var dismissTitle: String { ScorecardText.dismissTitle(variant: variant, currentHole: currentHole) }
    var status: String { ScorecardText.status(round: round, scored: model.scoredCount) }
    /// "OCT 23 · IN PROGRESS · THRU 7".
    var shortSubtitle: String {
        let date = round.startedAt.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        return "\(date) · \(status)"
    }

    func column(_ n: Int) -> ScorecardColumn { model.columns[n - 1] }
    func cell(_ n: Int) -> ScorecardCell { .resolve(column(n), currentHole: currentHole) }
    func pick(_ n: Int) -> ScorecardPick { .resolve(column(n), currentHole: currentHole) }
    func accessibilityLabel(_ n: Int) -> String {
        ScorecardText.accessibilityLabel(column(n), currentHole: currentHole)
    }

    /// The picked hole has a CTA or a second choice to show.
    func hasActions(_ pick: ScorecardPick) -> Bool { ctaTitle(pick) != nil || pick.secondary != nil }

    /// The CTA for a picked hole, or nil when it has nothing to do.
    func ctaTitle(_ pick: ScorecardPick) -> String? {
        pick.isAvailable(canOpenHole: canOpenHole) ? pick.title(variant: variant, isFinished: isFinished) : nil
    }

    /// Tap on a hole in the column-style cards: select it, tap again to clear.
    static func toggle(_ n: Int, in selection: Binding<Int?>) {
        selection.wrappedValue = selection.wrappedValue == n ? nil : n
    }
}
