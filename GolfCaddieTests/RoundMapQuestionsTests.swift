import XCTest
@testable import GolfCaddie

/// The penalty and putts questions and the hand-score entry.
@MainActor
final class RoundMapQuestionsTests: XCTestCase {
    // MARK: Penalty

    func testPenaltyOptionsInOrder() {
        XCTAssertEqual(PenaltyOption.all.map(\.type), [.obOrLost, .water, .unplayable, .wrongBall, .other])
        XCTAssertEqual(PenaltyOption.all.map(\.title),
                       ["OB OR LOST", "WATER", "UNPLAYABLE", "WRONG BALL", "OTHER"])
    }

    func testPenaltyStrokesAndCosts() {
        let byType = Dictionary(uniqueKeysWithValues: PenaltyOption.all.map { ($0.type, $0) })
        XCTAssertEqual(byType[.wrongBall]?.strokes, 2)
        XCTAssertEqual(byType[.wrongBall]?.costText, "+2")
        XCTAssertEqual(byType[.obOrLost]?.strokes, 1)
        XCTAssertEqual(byType[.obOrLost]?.costText, "+1 · REHIT")
        for type in [PenaltyType.water, .unplayable, .other] {
            XCTAssertEqual(byType[type]?.strokes, 1, "\(type)")
            XCTAssertEqual(byType[type]?.costText, "+1", "\(type)")
        }
    }

    func testEveryPenaltyTypeIsOffered() {
        XCTAssertEqual(Set(PenaltyOption.all.map(\.type)), Set(PenaltyType.allCases))
    }

    func testPenaltyAddedText() {
        XCTAssertEqual(PenaltyOption.addedText(.wrongBall, holeNumber: 8), "WRONG BALL · +2 on hole 8")
    }

    // MARK: Putts

    func testPuttOptionsAndLabels() {
        XCTAssertEqual(PuttsQuestionModel.options, [0, 1, 2, 3, 4])
        XCTAssertEqual(PuttsQuestionModel.options.map(PuttsQuestionModel.label), ["0", "1", "2", "3", "4+"])
    }

    func testInitialChoice() {
        XCTAssertEqual(PuttsQuestionModel.initialChoice(loggedPutts: 0), 2)
        XCTAssertEqual(PuttsQuestionModel.initialChoice(loggedPutts: 1), 1)
        XCTAssertEqual(PuttsQuestionModel.initialChoice(loggedPutts: 6), 4)
    }

    func testPuttsSummaryText() {
        XCTAssertEqual(PuttsQuestionModel.summary(fullShots: 2, penaltyStrokes: 1, putts: 2, par: 4),
                       "5 (+1) · 2 SHOTS + 1 PEN + 2 PUTTS")
        XCTAssertEqual(PuttsQuestionModel.summary(fullShots: 2, penaltyStrokes: 0, putts: 2, par: 4),
                       "4 (E) · 2 SHOTS + 2 PUTTS")
        XCTAssertEqual(PuttsQuestionModel.summary(fullShots: 1, penaltyStrokes: 0, putts: 1, par: 3),
                       "2 (-1) · 1 SHOT + 1 PUTT")
        XCTAssertEqual(PuttsQuestionModel.summary(fullShots: 3, penaltyStrokes: 2, putts: 0, par: nil),
                       "5 · 3 SHOTS + 2 PEN + 0 PUTTS")
    }

    func testConfirmTitleWraps() {
        XCTAssertEqual(PuttsQuestionModel.confirmTitle(holeNumber: 8), "Save · hole 9 ›")
        XCTAssertEqual(PuttsQuestionModel.confirmTitle(holeNumber: 18), "Save · hole 1 ›")
    }

    // MARK: Hand entry

    func testDraftStartsFromHandScoreElsePar() {
        let hole = Hole(id: UUID(), roundID: UUID(), holeNumber: 4, par: 4, confirmedAt: nil,
                        scoreSource: .hand, handStrokes: 6, handPutts: 3)
        XCTAssertEqual(HandScoreDraft.initial(hole: hole, par: 4), HandScoreDraft(strokes: 6, putts: 3))
        XCTAssertEqual(HandScoreDraft.initial(hole: nil, par: 5), HandScoreDraft(strokes: 5, putts: 2))
        XCTAssertEqual(HandScoreDraft.initial(hole: nil, par: nil), HandScoreDraft(strokes: 4, putts: 2))
    }

    func testDraftClampsPuttsToStrokes() {
        let draft = HandScoreDraft(strokes: 2, putts: 2).steppingStrokes(by: -1)
        XCTAssertEqual(draft.strokes, 1)
        XCTAssertEqual(draft.putts, 1)
        XCTAssertFalse(draft.canIncreasePutts)
        XCTAssertFalse(draft.canDecreaseStrokes)
    }

    func testDraftStepsAreImmutable() {
        let draft = HandScoreDraft(strokes: 4, putts: 2)
        let more = draft.steppingStrokes(by: 1).steppingPutts(by: -1)
        XCTAssertEqual(draft, HandScoreDraft(strokes: 4, putts: 2))
        XCTAssertEqual(more, HandScoreDraft(strokes: 5, putts: 1))
        XCTAssertEqual(HandScoreDraft(strokes: 0, putts: -3), HandScoreDraft(strokes: 1, putts: 0))
    }

    func testDraftSummary() {
        XCTAssertEqual(HandScoreDraft(strokes: 4, putts: 2).summary(par: 4), "PAR")
        XCTAssertEqual(HandScoreDraft(strokes: 6, putts: 2).summary(par: 4), "+2")
        XCTAssertEqual(HandScoreDraft(strokes: 3, putts: 1).summary(par: 4), "-1")
        XCTAssertEqual(HandScoreDraft(strokes: 3, putts: 1).summary(par: nil), "")
    }

    func testSaveTitles() {
        XCTAssertEqual(HandEntryText.saveTitle(holeNumber: 4, alreadyScored: false, advancesHole: false),
                       "Save hole 4")
        XCTAssertEqual(HandEntryText.saveTitle(holeNumber: 4, alreadyScored: true, advancesHole: false),
                       "Update hole 4")
        XCTAssertEqual(HandEntryText.saveTitle(holeNumber: 8, alreadyScored: false, advancesHole: true),
                       "Save · hole 9 ›")
    }
}
