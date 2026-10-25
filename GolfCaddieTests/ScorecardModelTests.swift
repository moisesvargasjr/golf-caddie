import SwiftUI
import XCTest
@testable import GolfCaddie

@MainActor
final class ScorecardModelTests: XCTestCase {
    static func shot(_ hole: UUID, _ seq: Int, club: String?, putt: Bool = false) -> Shot {
        Shot(id: UUID(), holeID: hole, sequenceNumber: seq, timestamp: Date(), latitude: nil,
             longitude: nil, gpsAccuracy: nil, hadGPS: false, club: club, source: .button,
             notes: nil, isPutt: putt)
    }

    /// Hole with `full` non-putts then `putts` putts.
    static func input(_ number: Int, par: Int?, full: Int, putts: Int, pens: Int = 0,
                      confirmed: Bool = true, roundID: UUID = UUID()) -> ScorecardModel.HoleInput {
        let hole = Hole(id: UUID(), roundID: roundID, holeNumber: number, par: par,
                        confirmedAt: confirmed ? Date() : nil)
        let clubs = ["driver", "sevenIron", "pitchingWedge", "sandWedge", "nineIron"]
        var shots = (0..<full).map { shot(hole.id, $0 + 1, club: clubs[$0 % clubs.count]) }
        shots += (0..<putts).map { shot(hole.id, full + $0 + 1, club: "putter", putt: true) }
        return .init(hole: hole, shots: shots, penaltyStrokes: pens)
    }

    func testMarks() {
        XCTAssertEqual(ScoreMark.mark(toPar: -2), .doubleCircle)
        XCTAssertEqual(ScoreMark.mark(toPar: -3), .doubleCircle)
        XCTAssertEqual(ScoreMark.mark(toPar: -1), .circle)
        XCTAssertEqual(ScoreMark.mark(toPar: 0), .none)
        XCTAssertEqual(ScoreMark.mark(toPar: 1), .square)
        XCTAssertEqual(ScoreMark.mark(toPar: 3), .doubleSquare)
        XCTAssertEqual(ScoreMark.mark(toPar: nil), .none)
    }

    func testGIR() {
        let h = UUID()
        // Par 4, on in 2, two putts → GIR.
        XCTAssertEqual(ScorecardModel.greenInRegulation(
            shots: [Self.shot(h, 1, club: "driver"), Self.shot(h, 2, club: "sevenIron"),
                    Self.shot(h, 3, club: "putter", putt: true)], par: 4), true)
        // Par 3, on in 2 → no GIR.
        XCTAssertEqual(ScorecardModel.greenInRegulation(
            shots: [Self.shot(h, 1, club: "sevenIron"), Self.shot(h, 2, club: "sandWedge"),
                    Self.shot(h, 3, club: "putter", putt: true)], par: 3), false)
        XCTAssertNil(ScorecardModel.greenInRegulation(shots: [], par: nil))
        XCTAssertNil(ScorecardModel.greenInRegulation(shots: [], par: 4), "no shots, nothing to judge")
        // Par 4, on in 2 plus a penalty stroke = 3 to reach the green: no GIR.
        XCTAssertEqual(ScorecardModel.greenInRegulation(
            shots: [Self.shot(h, 1, club: "driver"), Self.shot(h, 2, club: "sevenIron"),
                    Self.shot(h, 3, club: "putter", putt: true)], penalties: 1, par: 4), false)
    }

    func testTeeShotAndGirOverride() {
        var par4 = Self.input(1, par: 4, full: 2, putts: 2)
        par4 = .init(hole: { var h = par4.hole; h.teeShot = .fairway; h.girOverride = false; return h }(),
                     shots: par4.shots, penaltyStrokes: 0)
        var par3 = Self.input(2, par: 3, full: 1, putts: 2)
        par3 = .init(hole: { var h = par3.hole; h.teeShot = .left; return h }(),
                     shots: par3.shots, penaltyStrokes: 0)
        let par5 = Self.input(3, par: 5, full: 3, putts: 2)
        let model = ScorecardModel.build(holes: [par4, par3, par5], course: nil)
        XCTAssertEqual(model.columns[0].teeShot, .fairway)
        XCTAssertEqual(model.columns[0].gir, false, "the golfer's GIR wins over the worked-out one")
        XCTAssertTrue(model.columns[0].girIsManual)
        XCTAssertNil(model.columns[1].teeShot, "par 3s have no FIR")
        XCTAssertEqual(model.columns[1].gir, true)
        XCTAssertFalse(model.columns[1].girIsManual)
        XCTAssertEqual(model.columns[2].gir, true)
        XCTAssertEqual(model.firCount, 1)
        XCTAssertEqual(model.firText(nil), "1/1", "par 3s are not answered")
        XCTAssertNil(ScorecardModel.build(holes: [par5], course: nil).firText(nil), "blank before any answer")
        XCTAssertEqual(model.girCount, 2)
    }

    func testGirOverrideOnAHandScoredHole() {
        let hole = Hole(id: UUID(), roundID: UUID(), holeNumber: 4, par: 4, confirmedAt: Date(),
                        scoreSource: .hand, handStrokes: 4, handPutts: 2, girOverride: true)
        let model = ScorecardModel.build(holes: [.init(hole: hole, shots: [], penaltyStrokes: 0)], course: nil)
        XCTAssertEqual(model.columns[3].gir, true)
    }

    func testConfirmedHoleWithoutShotsIsBlank() {
        let model = ScorecardModel.build(holes: [Self.input(1, par: 4, full: 0, putts: 0)], course: nil)
        XCTAssertNil(model.columns[0].score)
        XCTAssertNil(model.columns[0].putts)
        XCTAssertNil(model.columns[0].gir)
    }

    func testFullNineParTotal() {
        let model = ScorecardModel.build(
            holes: (1...9).map { Self.input($0, par: 4, full: 2, putts: 2) }, course: nil)
        XCTAssertEqual(model.out.par, 36)
        XCTAssertNil(model.inn.par)
    }

    func testBuildTotalsAndBlanks() {
        let model = ScorecardModel.build(holes: [
            Self.input(1, par: 4, full: 2, putts: 2),           // 4, E, GIR
            Self.input(2, par: 3, full: 2, putts: 2, pens: 1),  // 5, +2
            Self.input(3, par: 5, full: 3, putts: 1),           // 4, -1, GIR
            Self.input(4, par: 4, full: 1, putts: 0, confirmed: false), // live hole
        ], course: nil)
        XCTAssertEqual(model.columns.count, 18)
        XCTAssertEqual(model.columns[0].score, 4)
        XCTAssertEqual(model.columns[1].score, 5)
        XCTAssertEqual(model.columns[1].penalties, 1)
        XCTAssertNil(model.columns[3].score, "unconfirmed holes stay blank")
        XCTAssertNil(model.columns[9].par)
        XCTAssertEqual(model.out.score, 13)
        XCTAssertNil(model.out.par, "holes 5-9 have no par, so the OUT par total is unknown")
        XCTAssertNil(model.inn.score)
        XCTAssertEqual(model.total.putts, 5)
        XCTAssertEqual(model.girCount, 2)
        XCTAssertEqual(model.grossToPar, 1)
        XCTAssertFalse(model.hasStrokeIndex)
    }

    func testStory() {
        let input = Self.input(1, par: 4, full: 2, putts: 2, pens: 1)
        XCTAssertEqual(ScorecardModel.story(shots: input.shots, penalties: 1), "Dr · 7i · 2 putts · 1 pen")
        XCTAssertEqual(ScorecardModel.story(shots: [], penalties: 0), "No shots logged")
    }

    /// Opt-in PNG of the card (TEST_RUNNER_RENDER_DUO_SNAPSHOTS=<dir>).
    func testRenderPhysicalCard() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_DUO_SNAPSHOTS"] else {
            throw XCTSkip("Set TEST_RUNNER_RENDER_DUO_SNAPSHOTS to render")
        }
        let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
        let scores = [4, 4, 4, 6, 5, 3, 7, 5, 4, 5, 2, 6]  // 12 holes played
        let inputs = (1...13).map { n -> ScorecardModel.HoleInput in
            let par = pars[n - 1]
            guard n <= scores.count else { return Self.input(n, par: par, full: 1, putts: 0, confirmed: false) }
            let putts = n % 3 == 0 ? 1 : 2
            return Self.input(n, par: par, full: max(1, scores[n - 1] - putts - (n == 7 ? 1 : 0)),
                              putts: putts, pens: n == 7 ? 1 : 0)
        }
        let model = ScorecardModel.build(holes: inputs, course: nil)
        let round = Round(id: UUID(), startedAt: Date(), endedAt: nil, courseName: nil, notes: nil,
                          curatedCourseId: nil, clubsLeftOut: nil)
        let view = PhysicalScorecardView.previewCard(round: round, model: model,
                                                     courseName: "Rancho Bernardo Inn",
                                                     currentHoleNumber: 13)
            .frame(width: 835)
            .padding(16)
            .background(PaletteValues.dark.paper)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let data = try XCTUnwrap(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("scorecard-wide-render-after.png"))
    }
}
