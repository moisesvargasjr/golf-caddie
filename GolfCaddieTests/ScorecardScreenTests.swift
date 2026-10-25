import GRDB
import SwiftUI
import XCTest
@testable import GolfCaddie

/// Duo v2 PR 6: the scorecard's pure rules — which card a display gets, what
/// each score cell shows, what a picked hole offers, the VoiceOver wording,
/// totals with hand scores and ADD holes, and the hand-score draft.
@MainActor
final class ScorecardScreenTests: XCTestCase {
    // MARK: Fixtures

    private func context(_ w: CGFloat, _ h: CGFloat, _ cls: LayoutClass,
                         _ posture: HingePosture = .unknown) -> DisplayContext {
        DisplayContext(layoutClass: cls, posture: posture, windowSize: CGSize(width: w, height: h))
    }

    private func column(_ n: Int, par: Int? = 4, score: Int? = nil, putts: Int? = nil,
                        penalties: Int? = nil, confirmed: Bool = false, needsEntry: Bool = false,
                        source: HoleScoreSource? = nil, gir: Bool? = nil) -> ScorecardColumn {
        ScorecardColumn(number: n, yards: 400, par: par, strokeIndex: nil, score: score, putts: putts,
                        gir: gir, penalties: penalties, story: nil, holeID: nil,
                        isConfirmed: confirmed, needsEntry: needsEntry, scoreSource: source)
    }

    private func model(_ overrides: [ScorecardColumn]) -> ScorecardModel {
        let byNumber = Dictionary(overrides.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        return ScorecardModel(columns: (1...18).map { byNumber[$0] ?? column($0) }, hasStrokeIndex: false)
    }

    private func handInput(_ n: Int, strokes: Int, putts: Int?, par: Int = 4) -> ScorecardModel.HoleInput {
        let hole = Hole(id: UUID(), roundID: UUID(), holeNumber: n, par: par, confirmedAt: Date(),
                        scoreSource: .hand, handStrokes: strokes, handPutts: putts)
        return .init(hole: hole, shots: [], penaltyStrokes: 0)
    }

    // MARK: Variant selection

    func testOpenWideGetsTheTraditionalCard() {
        XCTAssertEqual(ScorecardVariant.resolve(context(951, 669, .expanded, .open)), .traditional)
        XCTAssertEqual(ScorecardVariant.resolve(context(951, 669, .expanded, .unknown)), .traditional)
    }

    func testOpenPortraitGetsFrontOverBack() {
        XCTAssertEqual(ScorecardVariant.resolve(context(669, 951, .expanded, .open)), .frontOverBack)
        XCTAssertEqual(ScorecardVariant.resolve(context(669, 951, .expanded, .halfOpen)), .frontOverBack)
    }

    func testFoldedAndIPhonePortraitGetTabs() {
        XCTAssertEqual(ScorecardVariant.resolve(context(466, 678, .compact, .closed)), .tabs)
        XCTAssertEqual(ScorecardVariant.resolve(context(402, 874, .compact)), .tabs)
        XCTAssertEqual(ScorecardVariant.resolve(context(0, 0, .compact)), .tabs, "unmeasured window")
    }

    func testIPhoneLandscapeGetsThePaperCard() {
        XCTAssertEqual(ScorecardVariant.resolve(context(874, 402, .compact)), .landscapeCard)
        XCTAssertEqual(ScorecardVariant.resolve(context(956, 440, .compact)), .landscapeCard)
    }

    func testVariantIdentifiersAreDistinct() {
        let ids = Set(ScorecardVariant.allCases.map(\.accessibilityID))
        XCTAssertEqual(ids.count, ScorecardVariant.allCases.count)
    }

    func testTabsRowHeightFollowsTheScreen() {
        XCTAssertEqual(ScorecardTabsMetrics.rowHeight(windowHeight: 678), 40)
        XCTAssertEqual(ScorecardTabsMetrics.rowHeight(windowHeight: 874), 48)
        XCTAssertEqual(ScorecardTabsMetrics.subtotalHeight(windowHeight: 678), 40)
        XCTAssertEqual(ScorecardTabsMetrics.subtotalHeight(windowHeight: 874), 46)
    }

    func testInitialNineFollowsTheCurrentHole() {
        XCTAssertEqual(ScorecardNine.initial(currentHole: nil), .front)
        XCTAssertEqual(ScorecardNine.initial(currentHole: 9), .front)
        XCTAssertEqual(ScorecardNine.initial(currentHole: 10), .back)
        XCTAssertEqual(ScorecardNine.front.holes, 1...9)
        XCTAssertEqual(ScorecardNine.back.holes, 10...18)
    }

    func testFractionalWidths() {
        let widths = FractionalRow.widths(total: 400, fixedLeading: 62, fractions: [1, 1, 2])
        XCTAssertEqual(widths, [62, 84.5, 84.5, 169])
        XCTAssertEqual(FractionalRow.widths(total: 50, fixedLeading: 62, fractions: [1]), [62, 0])
    }

    // MARK: Cells and marks

    func testCellStates() {
        XCTAssertEqual(ScorecardCell.resolve(column(2, needsEntry: true), currentHole: 8), .add)
        XCTAssertEqual(ScorecardCell.resolve(column(8), currentHole: 8), .now)
        XCTAssertEqual(ScorecardCell.resolve(column(9), currentHole: 8), .blank)
        XCTAssertEqual(ScorecardCell.resolve(column(7, score: 5, confirmed: true), currentHole: 8),
                       .score(5, .square))
        XCTAssertEqual(ScorecardCell.resolve(column(8, score: 3, confirmed: true, source: .hand),
                                             currentHole: 8),
                       .score(3, .circle), "a scored current hole shows its score, not NOW")
    }

    func testRelativeToParMarks() {
        func mark(_ score: Int, par: Int) -> ScorecardCell {
            ScorecardCell.resolve(column(1, par: par, score: score, confirmed: true), currentHole: nil)
        }
        XCTAssertEqual(mark(2, par: 4), .score(2, .doubleCircle), "eagle")
        XCTAssertEqual(mark(1, par: 4), .score(1, .doubleCircle), "albatross")
        XCTAssertEqual(mark(3, par: 4), .score(3, .circle), "birdie")
        XCTAssertEqual(mark(4, par: 4), .score(4, .none), "par")
        XCTAssertEqual(mark(5, par: 4), .score(5, .square), "bogey")
        XCTAssertEqual(mark(6, par: 4), .score(6, .doubleSquare), "double")
        XCTAssertEqual(mark(9, par: 4), .score(9, .doubleSquare), "worse")
        XCTAssertEqual(ScorecardCell.resolve(column(1, par: nil, score: 4, confirmed: true), currentHole: nil),
                       .score(4, .none), "no par, no mark")
    }

    // MARK: Not played

    func testNotPlayedHoleShowsNPAndOffersEntryOrUndo() {
        var np = column(16)
        np.isNotPlayed = true
        XCTAssertEqual(ScorecardCell.resolve(np, currentHole: nil), .notPlayed)
        XCTAssertEqual(ScorecardPick.resolve(np, currentHole: nil), .notPlayed(16))
        XCTAssertEqual(ScorecardPick.notPlayed(16).title(variant: .traditional, isFinished: true), "Enter hole 16 score ›")
        XCTAssertEqual(ScorecardPick.notPlayed(16).secondary, .undoNotPlayed(16))
        XCTAssertEqual(ScorecardPick.addScore(12).secondary, .markNotPlayed(12))
        XCTAssertNil(ScorecardPick.openHole(7).secondary)
        XCTAssertEqual(ScorecardSecondaryPick.markNotPlayed(12).title, "MARK NOT PLAYED")
        XCTAssertEqual(ScorecardText.accessibilityLabel(np, currentHole: nil), "Hole 16, par 4, not played")
    }

    func testNotPlayedNote() {
        var a = column(17), b = column(18)
        a.isNotPlayed = true
        b.isNotPlayed = true
        let card = model([a, b])
        XCTAssertEqual(card.playedCount, 16)
        XCTAssertEqual(card.notPlayedNote, "16 OF 18 PLAYED · NP NOT IN TOTALS")
        XCTAssertNil(model([]).notPlayedNote)
    }

    // MARK: Picks

    func testPickActions() {
        XCTAssertEqual(ScorecardPick.resolve(column(2, needsEntry: true), currentHole: 8), .addScore(2))
        XCTAssertEqual(ScorecardPick.resolve(column(8), currentHole: 8), .backToHole(8))
        XCTAssertEqual(ScorecardPick.resolve(column(3, score: 4, confirmed: true, source: .hand),
                                             currentHole: 8), .editScore(3))
        XCTAssertEqual(ScorecardPick.resolve(column(7, score: 5, confirmed: true, source: .tracked),
                                             currentHole: 8), .openHole(7))
        XCTAssertEqual(ScorecardPick.resolve(column(12), currentHole: 8), .notReached(12))
        XCTAssertEqual(ScorecardPick.resolve(column(12, confirmed: true), currentHole: nil), .openHole(12),
                       "a confirmed hole with no shots can still be opened")
        // Finished round, tracking missed on hole 12: type its score straight in.
        XCTAssertEqual(ScorecardPick.resolve(column(12), currentHole: nil), .addScore(12))
        XCTAssertEqual(ScorecardCell.resolve(column(12), currentHole: nil), .add)
        XCTAssertEqual(ScorecardCell.resolve(column(12, confirmed: true), currentHole: nil), .blank,
                       "a confirmed hole with no shots is opened, not added")
    }

    func testPickAvailability() {
        XCTAssertTrue(ScorecardPick.addScore(2).isAvailable(canOpenHole: false))
        XCTAssertTrue(ScorecardPick.editScore(2).isAvailable(canOpenHole: false))
        XCTAssertTrue(ScorecardPick.backToHole(8).isAvailable(canOpenHole: false))
        XCTAssertFalse(ScorecardPick.openHole(7).isAvailable(canOpenHole: false), "no callback, no-op")
        XCTAssertTrue(ScorecardPick.openHole(7).isAvailable(canOpenHole: true))
        XCTAssertFalse(ScorecardPick.notReached(12).isAvailable(canOpenHole: true))
    }

    func testPickTitles() {
        XCTAssertEqual(ScorecardPick.addScore(4).title(variant: .tabs, isFinished: false), "Add hole 4 score ›")
        XCTAssertEqual(ScorecardPick.editScore(4).title(variant: .traditional, isFinished: false),
                       "Edit hole 4 score ›")
        XCTAssertEqual(ScorecardPick.openHole(7).title(variant: .traditional, isFinished: false),
                       "Open hole 7 on the map ›")
        XCTAssertEqual(ScorecardPick.openHole(7).title(variant: .tabs, isFinished: false), "Open hole 7 ›")
        XCTAssertEqual(ScorecardPick.openHole(9).title(variant: .tabs, isFinished: true),
                       "Review hole 9 on the map ›")
        XCTAssertEqual(ScorecardPick.backToHole(8).title(variant: .traditional, isFinished: false),
                       "Back to hole 8 ›")
        XCTAssertEqual(ScorecardPick.notReached(12).title(variant: .tabs, isFinished: false), "Not played yet")
    }

    // MARK: VoiceOver

    func testAccessibilityLabels() {
        XCTAssertEqual(ScorecardText.accessibilityLabel(
            column(4, par: 3, score: 4, putts: 2, confirmed: true), currentHole: 8),
                       "Hole 4, par 3, 4 strokes, 2 putts")
        XCTAssertEqual(ScorecardText.accessibilityLabel(column(2, needsEntry: true), currentHole: 8),
                       "Hole 2, not tracked, add score")
        XCTAssertEqual(ScorecardText.accessibilityLabel(column(8, par: 4), currentHole: 8),
                       "Hole 8, par 4, in progress")
        XCTAssertEqual(ScorecardText.accessibilityLabel(column(12, par: 3), currentHole: 8),
                       "Hole 12, par 3, not played yet")
        XCTAssertEqual(ScorecardText.accessibilityLabel(
            column(5, par: nil, score: 1, putts: 1, confirmed: true), currentHole: nil),
                       "Hole 5, 1 stroke, 1 putt")
        XCTAssertEqual(ScorecardText.accessibilityLabel(
            column(6, par: 4, score: 5, confirmed: true, source: .hand), currentHole: nil),
                       "Hole 6, par 4, 5 strokes, entered by hand")
    }

    func testTotalAccessibilityLabel() {
        let totals = ScorecardTotals(yards: 3400, par: 36, score: 41, putts: 16, penalties: 1)
        XCTAssertEqual(ScorecardText.totalAccessibilityLabel("Out", totals), "Out, par 36, 41 strokes, 16 putts")
        let empty = ScorecardTotals(yards: nil, par: nil, score: nil, putts: nil, penalties: nil)
        XCTAssertEqual(ScorecardText.totalAccessibilityLabel("In", empty), "In, no score yet")
    }

    // MARK: Text

    func testToParAndNumbers() {
        XCTAssertEqual(ScorecardText.toPar(nil), "—")
        XCTAssertEqual(ScorecardText.toPar(0), "E")
        XCTAssertEqual(ScorecardText.toPar(3), "+3")
        XCTAssertEqual(ScorecardText.toPar(-2), "-2")
        XCTAssertEqual(ScorecardText.number(nil), "—")
        XCTAssertEqual(ScorecardText.number(41), "41")
    }

    func testNeedsEntryNotes() {
        XCTAssertNil(ScorecardText.needsEntryNote([]))
        XCTAssertEqual(ScorecardText.needsEntryNote([2]), "Hole 2 wasn't tracked. Tap it to add its score.")
        XCTAssertEqual(ScorecardText.needsEntryNote([1, 2, 3, 4, 5, 6]),
                       "Holes 1–6 weren't tracked. Tap one to add its score.")
        XCTAssertEqual(ScorecardText.holeList([1, 2, 4, 6, 7]), "1–2, 4, 6–7")
        XCTAssertEqual(ScorecardText.needsEntryStamp([1, 2, 3, 4, 5, 6]), "HOLES 1–6 · TAP TO ADD")
        XCTAssertEqual(ScorecardText.needsEntryStamp([3]), "HOLE 3 · TAP TO ADD")
        XCTAssertNil(ScorecardText.needsEntryStamp([]))
    }

    func testStories() {
        XCTAssertEqual(ScorecardText.story(column(2, needsEntry: true), currentHole: 8, startingHole: 7),
                       "Not tracked — you started on hole 7. Add the score you kept.")
        XCTAssertEqual(ScorecardText.story(column(8), currentHole: 8, startingHole: 7),
                       "You are here. Finish the hole to fill it in.")
        XCTAssertEqual(ScorecardText.story(column(3, score: 4, putts: 2, confirmed: true, source: .hand),
                                           currentHole: 8, startingHole: 7),
                       "4 strokes · 2 putts · entered by hand (you started on 7)")
        XCTAssertEqual(ScorecardText.story(column(12), currentHole: 8, startingHole: 7), "Not played yet.")
    }

    func testDurationAndSubtitle() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ScorecardText.duration(from: start, to: start.addingTimeInterval(4 * 3600 + 5 * 60)),
                       "4H 05M")
        XCTAssertNil(ScorecardText.duration(from: start, to: nil))

        var round = Round(id: UUID(), startedAt: start, endedAt: nil, courseName: nil, notes: nil,
                          curatedCourseId: nil, clubsLeftOut: nil)
        XCTAssertEqual(ScorecardText.status(round: round, scored: 7), "IN PROGRESS · THRU 7")
        round.endedAt = start.addingTimeInterval(4 * 3600 + 5 * 60)
        round.mode = .tracking
        XCTAssertEqual(ScorecardText.status(round: round, scored: 18), "TRACKED · 4H 05M")
        round.mode = .casual
        XCTAssertEqual(ScorecardText.status(round: round, scored: 18), "CASUAL · 4H 05M")
    }

    func testDismissTitles() {
        XCTAssertEqual(ScorecardText.dismissTitle(variant: .traditional, currentHole: 8), "‹ HOLE 8")
        XCTAssertEqual(ScorecardText.dismissTitle(variant: .frontOverBack, currentHole: 8), "BACK TO MAP")
        XCTAssertEqual(ScorecardText.dismissTitle(variant: .tabs, currentHole: 8), "MAP")
        XCTAssertEqual(ScorecardText.dismissTitle(variant: .landscapeCard, currentHole: 8), "MAP")
        XCTAssertEqual(ScorecardText.dismissTitle(variant: .tabs, currentHole: nil), "‹ LOGBOOK")
    }

    // MARK: Totals

    func testFrontBackTotalsWithHandScores() {
        let model = ScorecardModel.build(holes: [
            handInput(1, strokes: 6, putts: 2),
            handInput(2, strokes: 4, putts: nil),
            ScorecardModelTests.input(3, par: 3, full: 1, putts: 2),
            ScorecardModelTests.input(10, par: 4, full: 3, putts: 2),
            handInput(18, strokes: 5, putts: 1),
        ], course: nil, startingHole: 1)
        XCTAssertEqual(model.totals(.front).score, 13, "6 + 4 by hand + 3 tracked")
        XCTAssertEqual(model.totals(.front).putts, 4)
        XCTAssertEqual(model.totals(.back).score, 10)
        XCTAssertEqual(model.totals(.back).putts, 3)
        XCTAssertEqual(model.out, model.totals(.front))
        XCTAssertEqual(model.inn, model.totals(.back))
        XCTAssertEqual(model.total.score, 23)
        XCTAssertEqual(model.total.putts, 7)
        XCTAssertEqual(model.scoredCount, 5)
        XCTAssertEqual(model.columns(.back).map(\.number), Array(10...18))
    }

    func testAddHolesAreLeftOutOfEveryTotal() {
        let model = ScorecardModel.build(holes: [
            ScorecardModelTests.input(7, par: 4, full: 3, putts: 2),
        ], course: nil, startingHole: 7)
        XCTAssertEqual(model.holesNeedingEntry, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(model.out.score, 5)
        XCTAssertEqual(model.grossToPar, 1)
        XCTAssertEqual(model.scoredCount, 1)
    }

    func testAddColumnPenaltiesNeverReachTheTotals() {
        let m = model([
            column(1, score: nil, penalties: 2, confirmed: true, needsEntry: true),
            column(2, score: 5, putts: 2, penalties: 1, confirmed: true),
        ])
        XCTAssertEqual(m.out.penalties, 1, "the ADD hole's penalty rows don't count until it's scored")
        XCTAssertEqual(m.out.score, 5)
        XCTAssertEqual(m.out.par, 36, "par still totals across ADD holes")
    }

    func testGIRCountPerNine() {
        let m = model([
            column(1, score: 4, confirmed: true, gir: true),
            column(2, score: 4, confirmed: true, gir: false),
            column(11, score: 4, confirmed: true, gir: true),
            column(12, score: 4, confirmed: true, gir: true),
        ])
        XCTAssertEqual(m.girCount(.front), 1)
        XCTAssertEqual(m.girCount(.back), 2)
        XCTAssertEqual(m.girCount, 3)
    }

    // MARK: Hand-score draft

    func testDraftStartsAtParWithTwoPutts() {
        let draft = CardScoreDraft(column: column(4, par: 3, needsEntry: true))
        XCTAssertEqual(draft.strokes, 3)
        XCTAssertEqual(draft.putts, 2)
        XCTAssertEqual(draft.summary, "PAR")
        XCTAssertEqual(CardScoreDraft(column: column(4, par: nil, needsEntry: true)).strokes, 4)
    }

    func testDraftPrefillsAnExistingHandScore() {
        let draft = CardScoreDraft(column: column(4, par: 4, score: 6, putts: 3, confirmed: true, source: .hand))
        XCTAssertEqual(draft.strokes, 6)
        XCTAssertEqual(draft.putts, 3)
        XCTAssertEqual(draft.summary, "+2")
    }

    func testDraftSteppersKeepAPlausibleScore() {
        var draft = CardScoreDraft(column: column(4, par: 3, needsEntry: true))
        draft = draft.decrementingStrokes().decrementingStrokes()
        XCTAssertEqual(draft.strokes, 1)
        XCTAssertEqual(draft.putts, 1, "putts never exceed strokes")
        XCTAssertFalse(draft.canDecrementStrokes)
        XCTAssertEqual(draft.decrementingStrokes(), draft)
        XCTAssertEqual(draft.summary, "-2")
        XCTAssertFalse(draft.canIncrementPutts)
        XCTAssertEqual(draft.incrementingPutts().putts, 1)
        draft = draft.decrementingPutts().decrementingPutts()
        XCTAssertEqual(draft.putts, 0)
        XCTAssertFalse(draft.canDecrementPutts)
        draft = draft.incrementingStrokes()
        XCTAssertEqual(draft.strokes, 2)
        XCTAssertNoThrow(try HoleScoring.validateHandScore(strokes: draft.strokes, putts: draft.putts))
    }

    func testDraftStopsAtTheStrokeCeiling() {
        var draft = CardScoreDraft(column: column(4, par: 4, needsEntry: true))
        for _ in 0..<40 { draft = draft.incrementingStrokes() }
        XCTAssertEqual(draft.strokes, HoleScoring.strokeRange.upperBound)
        XCTAssertFalse(draft.canIncrementStrokes)
    }

    // MARK: ADD → hand entry → card (database)

    func testAddedScoreFillsTheCard() throws {
        let queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
        defer { TestDatabase.restore() }

        let round = Round(id: UUID(), startedAt: Date(), endedAt: nil, courseName: "Native Oaks", notes: nil,
                          curatedCourseId: nil, clubsLeftOut: nil, mode: .tracking, startingHole: 7)
        try RoundRepository.insert(round)
        try TestDatabase.seedHole(roundID: round.id, holeNumber: 7, par: 4)

        var snapshot = try ScorecardLoader.load(round: round, curatedCourseId: nil)
        XCTAssertEqual(snapshot.model.holesNeedingEntry, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ScorecardCell.resolve(snapshot.model.columns[3], currentHole: 7), .add)

        let draft = CardScoreDraft(column: snapshot.model.columns[3]).incrementingStrokes()
        try ScorecardLoader.saveHandScore(draft, roundID: round.id, live: nil)

        snapshot = try ScorecardLoader.load(round: round, curatedCourseId: nil)
        XCTAssertEqual(snapshot.model.holesNeedingEntry, [1, 2, 3, 5, 6])
        XCTAssertEqual(snapshot.model.columns[3].score, 5)
        XCTAssertEqual(snapshot.model.columns[3].putts, 2)
        XCTAssertEqual(snapshot.model.out.score, 5, "the entered hole now counts")
        XCTAssertEqual(ScorecardPick.resolve(snapshot.model.columns[3], currentHole: 7), .editScore(4))
        XCTAssertEqual(snapshot.courseName, nil, "no curated course")
    }
}
