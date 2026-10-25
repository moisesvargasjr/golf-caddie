import XCTest
@testable import GolfCaddie

/// The casual screen's round-so-far model: which holes are listed, in what
/// order, the to-par running total, and the marker for the hole on screen.
@MainActor
final class RoundSoFarTests: XCTestCase {
    private func input(_ n: Int, par: Int?, strokes: Int, putts: Int? = 2) -> RoundScoreInput {
        RoundScoreInput(holeNumber: n, par: par, strokes: strokes, putts: putts)
    }

    /// The canvas round: holes 1–7 scored, hole 8 live.
    private var canvasRound: [RoundScoreInput] {
        [input(1, par: 4, strokes: 4), input(2, par: 5, strokes: 6), input(3, par: 3, strokes: 3, putts: 1),
         input(4, par: 4, strokes: 5), input(5, par: 4, strokes: 4), input(6, par: 3, strokes: 4),
         input(7, par: 4, strokes: 5)]
    }

    // MARK: Scored holes

    func testEmptyRound() {
        let model = RoundSoFar.build(scores: [], startingHole: 1, onScreen: 1, live: 1)
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.thru, 0)
        XCTAssertEqual(model.headerText, "NO HOLES SCORED")
        XCTAssertEqual(model.shortText, "NO HOLES YET")
    }

    func testRowsAreNewestFirst() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 8, live: 8)
        XCTAssertEqual(model.rows.map(\.holeNumber), [7, 6, 5, 4, 3, 2, 1])
    }

    func testInputOrderDoesNotMatter() {
        let model = RoundSoFar.build(scores: canvasRound.reversed(), startingHole: 1, onScreen: 8, live: 8)
        XCTAssertEqual(model.rows.map(\.holeNumber), [7, 6, 5, 4, 3, 2, 1])
    }

    func testDuplicateHoleKeepsTheFirst() {
        let model = RoundSoFar.build(scores: [input(3, par: 3, strokes: 3), input(3, par: 3, strokes: 9)],
                                     startingHole: 1, onScreen: 4, live: 4)
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows.first?.strokes, 3)
    }

    func testLateStartOrdersByPlay() {
        // Started on 16: played 16, 17, 18, then 1, 2.
        let scores = [input(1, par: 4, strokes: 4), input(2, par: 4, strokes: 5),
                      input(16, par: 4, strokes: 4), input(17, par: 3, strokes: 3), input(18, par: 5, strokes: 5)]
        let model = RoundSoFar.build(scores: scores, startingHole: 16, onScreen: 3, live: 3)
        XCTAssertEqual(model.rows.map(\.holeNumber), [2, 1, 18, 17, 16])
    }

    func testHolesBeforeTheStartEnteredLaterComeLast() {
        // Started on 7; hole 1 entered by hand afterwards counts as played after 18.
        let scores = [input(1, par: 4, strokes: 5), input(7, par: 4, strokes: 4), input(8, par: 4, strokes: 4)]
        let model = RoundSoFar.build(scores: scores, startingHole: 7, onScreen: 9, live: 9)
        XCTAssertEqual(model.rows.map(\.holeNumber), [1, 8, 7])
    }

    // MARK: Totals

    func testCanvasTotals() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 8, live: 8)
        XCTAssertEqual(model.totalStrokes, 31)
        XCTAssertEqual(model.toPar, 4)
        XCTAssertEqual(model.thru, 7)
        XCTAssertEqual(model.headerText, "31 · +4 THRU 7")
        XCTAssertEqual(model.shortText, "+4 THRU 7")
    }

    func testRunningToParFollowsPlayOrder() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 8, live: 8)
        // Oldest first: 0, +1, +1, +2, +2, +3, +4.
        XCTAssertEqual(model.rows.reversed().map(\.runningToPar), [0, 1, 1, 2, 2, 3, 4])
    }

    func testEvenAndUnderPar() {
        let even = RoundSoFar.build(scores: [input(1, par: 4, strokes: 4)], startingHole: 1, onScreen: 2, live: 2)
        XCTAssertEqual(even.shortText, "E THRU 1")
        let under = RoundSoFar.build(scores: [input(1, par: 4, strokes: 3)], startingHole: 1, onScreen: 2, live: 2)
        XCTAssertEqual(under.headerText, "3 · -1 THRU 1")
    }

    func testHoleWithoutParCountsStrokesButNotToPar() {
        let model = RoundSoFar.build(scores: [input(1, par: nil, strokes: 6), input(2, par: 4, strokes: 5)],
                                     startingHole: 1, onScreen: 3, live: 3)
        XCTAssertEqual(model.totalStrokes, 11)
        XCTAssertEqual(model.toPar, 1)
        XCTAssertEqual(model.thru, 2)
        let noPar = model.rows.first { $0.holeNumber == 1 }
        XCTAssertNil(noPar?.toPar)
        XCTAssertEqual(noPar?.parText, "PAR —")
        XCTAssertEqual(noPar?.toParText, "—")
        XCTAssertEqual(noPar?.shape, .plain)
    }

    // MARK: Rows

    func testRowTextAndShape() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 8, live: 8)
        let bogey = model.rows.first { $0.holeNumber == 7 }
        XCTAssertEqual(bogey?.parText, "PAR 4")
        XCTAssertEqual(bogey?.toParText, "+1")
        XCTAssertEqual(bogey?.detailText, "+1 · 2P")
        XCTAssertEqual(bogey?.shape, .square)
        let par = model.rows.first { $0.holeNumber == 3 }
        XCTAssertEqual(par?.detailText, "E · 1P")
        XCTAssertEqual(par?.shape, .plain)
        let birdie = RoundSoFar.build(scores: [input(1, par: 4, strokes: 3, putts: nil)],
                                      startingHole: 1, onScreen: 2, live: 2).rows.first
        XCTAssertEqual(birdie?.shape, .circle)
        XCTAssertEqual(birdie?.detailText, "-1")
    }

    func testRowAccessibilityLabel() {
        let row = RoundSoFar.build(scores: [input(7, par: 4, strokes: 5, putts: 2)],
                                   startingHole: 1, onScreen: 8, live: 8).rows.first
        XCTAssertEqual(row?.accessibilityLabel, "Hole 7, par 4, scored 5, bogey, 2 putts")
        let birdie = RoundSoFar.build(scores: [input(3, par: 4, strokes: 3, putts: 1)],
                                      startingHole: 1, onScreen: 8, live: 8).rows.first
        XCTAssertEqual(birdie?.accessibilityLabel, "Hole 3, par 4, scored 3, birdie, 1 putt")
        let noPar = RoundSoFar.build(scores: [input(2, par: nil, strokes: 6, putts: nil)],
                                     startingHole: 1, onScreen: 8, live: 8).rows.first
        XCTAssertEqual(noPar?.accessibilityLabel, "Hole 2, scored 6")
    }

    // MARK: Current hole marker

    func testLiveHoleOnScreenMarksNoRow() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 8, live: 8)
        XCTAssertFalse(model.rows.contains { $0.isOnScreen })
        XCTAssertEqual(model.liveHoleNumber, 8)
    }

    func testPastHoleOnScreenIsMarked() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 4, live: 8)
        XCTAssertEqual(model.rows.filter(\.isOnScreen).map(\.holeNumber), [4])
    }

    func testFinishedRoundMarksTheHoleOnScreen() {
        let model = RoundSoFar.build(scores: canvasRound, startingHole: 1, onScreen: 2, live: nil)
        XCTAssertEqual(model.rows.filter(\.isOnScreen).map(\.holeNumber), [2])
        XCTAssertNil(model.liveHoleNumber)
    }
}
