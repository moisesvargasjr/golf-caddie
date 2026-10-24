import CoreLocation
import SwiftUI

// Everything the controls and the map do. Every write goes through the
// `HoleSession` (live vs past routing lives there) except the round-level
// moves that only the live round can make (log a shot, finish, skip ahead).
extension RoundMapScreen {
    func panelActions() -> RoundPanelActions {
        RoundPanelActions(
            previousHole: { go(HoleNavigation.previous(viewing: holeNumber, live: liveHoleNumber)) },
            nextHole: { go(HoleNavigation.next(viewing: holeNumber, live: liveHoleNumber)) },
            openHoleGrid: host.openHoleGrid,
            backToLive: { go(.live) },
            addShot: logShot,
            askPenalty: { open(.penalty) },
            finishHole: finishHole,
            pickPutts: { puttsChoice = $0 },
            confirmFinish: confirmFinish,
            pickPenalty: addPenalty,
            cancelQuestion: { question = nil },
            selectShot: toggleSelection,
            removePenalty: { id in perform("remove the penalty") { try session?.removePenalty(id) } },
            pickClub: pickClub,
            deleteSelectedShot: deleteSelectedShot,
            doneSelection: { selectedShotID = nil },
            pickScore: { scoreDraft = scoreDraft.picking(strokes: $0) },
            pickScorePutts: { scoreDraft = scoreDraft.picking(putts: $0) },
            saveScore: saveScore,
            openRoundHole: openRoundHole,
            reviewNext: goToReviewNext,
            stepPutts: stepPutts,
            stepEntryStrokes: { entryDraft = entryDraft.steppingStrokes(by: $0) },
            stepEntryPutts: { entryDraft = entryDraft.steppingPutts(by: $0) },
            saveEntry: saveEntry,
            hideControls: hideControls,
            showControls: { autoHide?.setManuallyHidden(false) },
            resetCompass: { mapController.resetToHoleUp() },
            noteInteraction: { autoHide?.noteInteraction() },
            openCard: host.openCard,
            openBag: host.openBag,
            linkCourse: host.linkCourse,
            unlinkCourse: host.unlinkCourse,
            toggleCasual: host.toggleCasual,
            endRound: host.endRound,
            roundActions: host.roundActionHandlers
        )
    }

    // MARK: Review

    /// Next hole › in play order; on the round's last hole, back to the card.
    private func goToReviewNext() {
        question = nil
        switch ReviewNavigation.next(after: holeNumber, startingHole: session?.startingHole) {
        case let .hole(number): viewedHole = number
        case .backToCard: host.openCard()
        }
    }

    /// The result card's PUTTS − n +: trims or appends putt strokes on a
    /// tracked hole (`HoleSession.setPutts`).
    private func stepPutts(_ delta: Int) {
        guard let session else { return }
        let putts = ReviewPutts.stepped(session.putts, by: delta)
        guard putts != session.putts else { return }
        perform("change the putts") {
            try session.setPutts(putts)
            refreshRoundScore()
        }
    }

    // MARK: Navigation

    func go(_ step: HoleNavigation.Step?) {
        guard let step else { return }
        switch step {
        case let .view(number): viewedHole = number
        case .live: viewedHole = nil
        case .skipAhead:
            viewedHole = nil
            live?.stepHole(by: 1)
        }
    }

    // MARK: Live hole

    private func logShot() {
        guard let live, !isMarking else { return }
        isMarking = true
        Task { @MainActor in
            do {
                try await live.markShot()
                let number = live.currentHoleShots.count
                toast = RoundToast(text: "Shot \(number) · \(live.currentClub?.shortName ?? "no club") logged here")
            } catch {
                toast = RoundToast(text: "Couldn't log the shot: \(error.localizedDescription)", kind: .error)
            }
            isMarking = false
        }
    }

    /// Finish hole asks the mode's question: putts (tracking) or the score
    /// grid (casual), which starts with nothing picked.
    private func finishHole() {
        switch mode.finishQuestion {
        case .score:
            scoreDraft = ScoreGridDraft.initial(hole: session?.hole)
            open(.score)
        case .putts, .penalty:
            askPutts()
        }
    }

    private func askPutts() {
        let logged = (session?.shots ?? []).filter(\.isPutt).count
        puttsChoice = PuttsQuestionModel.initialChoice(loggedPutts: logged)
        open(.putts)
    }

    /// Putts → the score (full shots + penalties + putts) → confirm and move
    /// on, through the same reconciliation as the watch's Finish.
    private func confirmFinish() {
        guard let live, let session, session.isLive else { return }
        let number = holeNumber
        let fullShots = session.shots.filter { !$0.isPutt }.count
        let score = PuttsQuestionModel.score(fullShots: fullShots, penaltyStrokes: session.penaltyStrokes,
                                             putts: puttsChoice)
        let par = session.par
        perform("finish the hole") {
            try live.finishHole(putts: puttsChoice, score: score)
            question = nil
            viewedHole = nil
            let result = RoundMapFormat.resultLine(score: score, par: par, putts: puttsChoice)
            toast = RoundToast(text: "Hole \(number) saved · \(result)")
        }
    }

    // MARK: Questions

    private func open(_ next: RoundMapQuestion) {
        selectedShotID = nil
        question = next
    }

    private func addPenalty(_ type: PenaltyType) {
        let number = holeNumber
        perform("add the penalty") {
            try session?.addPenalty(type)
            question = nil
            toast = RoundToast(text: PenaltyOption.addedText(type, holeNumber: number))
            refreshRoundScore()
        }
    }

    private func saveEntry() {
        guard let session else { return }
        let number = holeNumber
        let draft = entryDraft
        let advances = session.isLive
        perform("save the score") {
            try session.setHandScore(strokes: draft.strokes, putts: draft.putts)
            if advances, let live {
                try live.confirmHoleAndAdvance(par: session.par)
                viewedHole = nil
            }
            toast = RoundToast(text: "Hole \(number) saved · \(draft.strokes) (\(draft.summary(par: session.par)))")
            refreshRoundScore()
        }
    }

    /// Casual: the grid's (strokes, putts) as the hole's hand score. On the
    /// live hole (Finish) the round then moves on, as the watch's Finish does.
    private func saveScore() {
        guard let session else { return }
        let number = holeNumber
        let par = session.par
        let advances = question == .score && session.isLive
        perform("save the score") {
            let result = try scoreDraft.result()
            try session.setHandScore(strokes: result.strokes, putts: result.putts)
            if advances, let live {
                try live.confirmHoleAndAdvance(par: par)
                viewedHole = nil
            }
            question = nil
            let toPar = par.map { " (\(RoundMapFormat.toPar(result.strokes - $0)))" } ?? ""
            toast = RoundToast(text: "Hole \(number) saved · \(result.strokes)\(toPar)")
            refreshRoundScore()
        }
    }

    /// A hole tapped in the round-so-far list: open it to edit its score
    /// (the live hole goes back to following the round).
    private func openRoundHole(_ number: Int) {
        question = nil
        let step: HoleNavigation.Step = number == liveHoleNumber ? .live : .view(number)
        go(step)
        autoHide?.noteInteraction()
    }

    // MARK: Shots

    func toggleSelection(_ id: UUID) {
        question = nil
        selectedShotID = selectedShotID == id ? nil : id
        autoHide?.noteInteraction()
    }

    private func pickClub(_ club: Club) {
        if let id = selectedShotID {
            perform("change the club") { try session?.setClub(club, forShot: id) }
        } else if isViewingLive {
            live?.setCurrentClub(club)
        }
    }

    private func deleteSelectedShot() {
        guard let id = selectedShotID else { return }
        perform("delete the shot") {
            try session?.deleteShot(id)
            selectedShotID = nil
        }
    }

    func moveShot(_ id: UUID, to coordinate: CLLocationCoordinate2D) {
        perform("move the shot") { try session?.moveShot(id, to: coordinate) }
    }

    /// Hold the map: a shot where the finger is, numbered by its place along
    /// the hole, selected so the next club tap sets its club.
    func holdToAdd(at coordinate: CLLocationCoordinate2D) {
        guard mode.allowsHoldToAdd, let session, panelState(for: session) != .entry else { return }
        perform("add the shot") {
            let shot = try session.insertShot(at: coordinate)
            question = nil
            selectedShotID = shot.id
            if let tip = HoldToAddTip().consume() {
                toast = RoundToast(text: tip, kind: .tip)
            } else {
                toast = RoundToast(text: "Shot \(shot.sequenceNumber) added · pick its club")
            }
        }
    }

    // MARK: Chrome

    private func hideControls() {
        selectedShotID = nil
        question = nil
        autoHide?.setManuallyHidden(true)
    }

    /// The glasses finished a hole (and moved the live hole on).
    func noteGlassesFinish() {
        guard let live, let hole = live.mostRecentlyConfirmedHoleFromGlasses else { return }
        toast = RoundToast(text: "Hole \(hole.holeNumber) finished on the glasses · ‹ to review it")
        live.clearMostRecentlyConfirmedHoleFromGlasses()
        refreshRoundScore()
    }

    /// Runs a write; a failure shows as a red toast.
    func perform(_ what: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            toast = RoundToast(text: "Couldn't \(what): \(error.localizedDescription)", kind: .error)
        }
    }
}
