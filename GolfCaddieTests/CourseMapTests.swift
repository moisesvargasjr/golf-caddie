import GRDB
import CoreLocation
import XCTest
@testable import GolfCaddie

/// Duo v2 PR 8: the finished round's course map — outlines built from the
/// round's holes and shots (+ curated tee/green anchors when the round has a
/// matched course), the card ⇄ course ⇄ hole route, and Next hole › gliding
/// along the course.
final class CourseMapTests: XCTestCase {
    private let roundID = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Fixtures

    private func coordinate(_ hole: Int, _ step: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 33 + Double(hole) * 0.01 + Double(step) * 0.001, longitude: -117)
    }

    private func hole(_ number: Int, par: Int? = 4, confirmed: Bool = true) -> Hole {
        Hole(id: UUID(), roundID: roundID, holeNumber: number, par: par,
             confirmedAt: confirmed ? t0 : nil)
    }

    private func handHole(_ number: Int, strokes: Int?, par: Int? = 4) -> Hole {
        Hole(id: UUID(), roundID: roundID, holeNumber: number, par: par, confirmedAt: nil,
             scoreSource: .hand, handStrokes: strokes, handPutts: 2)
    }

    private func shot(_ hole: Hole, _ sequence: Int, placed: Bool = true, putt: Bool = false) -> Shot {
        let c = coordinate(hole.holeNumber, sequence)
        return Shot(id: UUID(), holeID: hole.id, sequenceNumber: sequence, timestamp: t0,
                    latitude: placed ? c.latitude : nil, longitude: placed ? c.longitude : nil,
                    gpsAccuracy: 5, hadGPS: placed, club: nil, source: .button, notes: nil, isPutt: putt)
    }

    private func anchors(_ number: Int) -> HolePathAnchors {
        HolePathAnchors(tee: coordinate(number, 0), green: coordinate(number, 9))
    }

    // MARK: Hole rows → course-map holes

    func testScoresFollowTheCardRules() {
        let tracked = hole(1, par: 4)
        let unconfirmed = hole(2, par: 3, confirmed: false)
        let hand = handHole(3, strokes: 6, par: 5)
        let handBlank = handHole(4, strokes: nil)
        let shots = [tracked.id: [shot(tracked, 1), shot(tracked, 2), shot(tracked, 3, putt: true)],
                     unconfirmed.id: [shot(unconfirmed, 1)]]
        let holes = CourseOutlineBuilder.holes(from: [hand, unconfirmed, tracked, handBlank], shots: shots,
                                               penaltyStrokes: [tracked.id: 1])
        XCTAssertEqual(holes.map(\.number), [1, 2, 3, 4], "sorted by hole number")
        XCTAssertEqual(holes[0].score, 4, "3 shots + 1 penalty stroke")
        XCTAssertNil(holes[1].score, "an unconfirmed tracked hole has no score yet")
        XCTAssertEqual(holes[2].score, 6, "hand-scored")
        XCTAssertNil(holes[3].score, "hand-scored with nothing entered")
        XCTAssertEqual(holes[0].shots.count, 3)
        XCTAssertEqual(holes[2].par, 5)
    }

    func testUnplacedShotsAreLeftOffTheLine() {
        let h = hole(1)
        let holes = CourseOutlineBuilder.holes(from: [h], shots: [h.id: [shot(h, 1), shot(h, 2, placed: false),
                                                                        shot(h, 3)]],
                                               penaltyStrokes: [:])
        XCTAssertEqual(holes[0].shots.count, 2)
        XCTAssertEqual(holes[0].score, 3, "the unplaced shot still counts")
    }

    // MARK: Outlines with a matched course

    func testWithCourseAnchorsEveryHoleRunsTeeShotsGreen() {
        let h1 = hole(1, par: 4)
        let holes = CourseOutlineBuilder.holes(from: [h1], shots: [h1.id: [shot(h1, 1), shot(h1, 2)]],
                                               penaltyStrokes: [:])
        let outlines = CourseOutlineBuilder.outlines(holes, anchors: anchors, curatedPar: { _ in 3 })
        XCTAssertEqual(outlines.map(\.number), Array(1...18), "the whole course, untracked holes included")

        let first = outlines[0]
        XCTAssertEqual(first.route.count, 4, "tee, 2 shots, green")
        XCTAssertEqual(first.route.first?.latitude, coordinate(1, 0).latitude)
        XCTAssertEqual(first.route.last?.latitude, coordinate(1, 9).latitude)
        XCTAssertEqual(first.score, 2)
        XCTAssertEqual(first.par, 4, "the round's par wins over the curated one")
        XCTAssertEqual(first.badgeCoordinate?.latitude, coordinate(1, 0).latitude, "badge on the tee")
    }

    func testUntrackedHolesOnAMatchedCourseShowTheHoleWithoutAScore() {
        let outlines = CourseOutlineBuilder.outlines([], anchors: anchors, curatedPar: { $0 == 5 ? 3 : 4 })
        let five = outlines.first { $0.number == 5 }
        XCTAssertNotNil(five)
        XCTAssertNil(five?.score)
        XCTAssertEqual(five?.par, 3, "par from the curated course")
        XCTAssertEqual(five?.route.count, 2, "tee → green")
        XCTAssertFalse(five?.isOverPar ?? true)
    }

    func testOverParHolesAreFlagged() {
        let h = hole(2, par: 3)
        let holes = CourseOutlineBuilder.holes(from: [h], shots: [h.id: (1...5).map { shot(h, $0) }],
                                               penaltyStrokes: [:])
        let outline = CourseOutlineBuilder.outlines(holes, anchors: anchors).first { $0.number == 2 }
        XCTAssertEqual(outline?.score, 5)
        XCTAssertTrue(outline?.isOverPar ?? false)
    }

    // MARK: Outlines without a matched course

    func testWithoutACourseOnlyTheShotsAreDrawn() {
        let h1 = hole(1), h2 = hole(2), h3 = hole(3)
        let holes = CourseOutlineBuilder.holes(
            from: [h1, h2, h3],
            shots: [h1.id: [shot(h1, 1), shot(h1, 2)], h2.id: [shot(h2, 1, placed: false)], h3.id: [shot(h3, 1)]],
            penaltyStrokes: [:])
        let outlines = CourseOutlineBuilder.outlines(holes, anchors: { _ in .none })
        XCTAssertEqual(outlines.map(\.number), [1, 3], "a hole with no placed shot has nothing to draw")
        XCTAssertNil(outlines[0].tee)
        XCTAssertNil(outlines[0].green)
        XCTAssertEqual(outlines[0].route.count, 2)
        XCTAssertEqual(outlines[1].route.count, 1, "one shot: a badge, no line")
        XCTAssertEqual(outlines[0].score, 2)
    }

    func testHandScoredHolesWithoutShotsOrAnchorsAreLeftOff() {
        let hand = handHole(7, strokes: 5)
        let holes = CourseOutlineBuilder.holes(from: [hand], shots: [:], penaltyStrokes: [:])
        XCTAssertTrue(CourseOutlineBuilder.outlines(holes, anchors: { _ in .none }).isEmpty)
        let matched = CourseOutlineBuilder.outlines(holes, anchors: anchors).first { $0.number == 7 }
        XCTAssertEqual(matched?.score, 5, "on a matched course the hole shows with its hand score")
    }

    func testPartialAnchorsKeepWhatExists() {
        let h = hole(4)
        let holes = CourseOutlineBuilder.holes(from: [h], shots: [h.id: [shot(h, 1)]], penaltyStrokes: [:])
        let outlines = CourseOutlineBuilder.outlines(holes, anchors: { n in
            n == 4 ? HolePathAnchors(tee: nil, green: self.coordinate(4, 9)) : .none
        })
        XCTAssertEqual(outlines.map(\.number), [4])
        XCTAssertEqual(outlines[0].route.count, 2, "shot → green")
    }

    // MARK: Content and text

    func testContentKnowsWhetherThereIsAnythingToDraw() {
        let empty = CourseMapContent(outlines: [], title: "Debug Links", caption: "", hasCourseAnchors: false)
        XCTAssertFalse(empty.hasContent)
        let outline = CourseHoleOutline(number: 1, tee: nil, green: nil, shots: [coordinate(1, 1)])
        XCTAssertTrue(CourseMapContent(outlines: [outline], title: "", caption: "", hasCourseAnchors: false).hasContent)
    }

    func testCaptionSaysWhatTheMapShows() {
        XCTAssertEqual(CourseMapText.caption(roundText: "OCT 18 · 82 (+10)", hasCourseAnchors: true),
                       "OCT 18 · 82 (+10) · YOUR SHOTS ON EVERY HOLE")
        XCTAssertEqual(CourseMapText.caption(roundText: "OCT 18 · 82 (+10)", hasCourseAnchors: false),
                       "OCT 18 · 82 (+10) · YOUR SHOTS ONLY")
        XCTAssertEqual(CourseMapText.title(courseName: "  "), "This round")
        XCTAssertEqual(CourseMapText.title(courseName: "Native Oaks"), "Native Oaks")
    }

    func testRoundTextCountsEveryScoredHole() {
        let rows = [CourseMapHole(number: 1, par: 4, score: 5, shots: []),
                    CourseMapHole(number: 2, par: 3, score: nil, shots: []),
                    CourseMapHole(number: 3, par: 5, score: 5, shots: [])]
        XCTAssertEqual(CourseMapText.roundText(dateText: "OCT 18", holes: rows), "OCT 18 · 10 (+1)")
    }

    func testBadgesReadTheirScore() {
        XCTAssertEqual(HoleMapAccessibility.holeBadgeLabel(number: 7, score: 5), "Hole 7, score 5, tap to review")
        XCTAssertEqual(CourseMapAccessibilityID.badge(7), "course.badge.7")
        XCTAssertEqual(CourseMapAccessibilityID.stripHole(7), "course.strip.7")
    }

    // MARK: Chrome per pose

    func testCourseChromePerLayout() {
        XCTAssertEqual(CourseMapChromeStyle.resolve(.openWide), .openDuo)
        XCTAssertEqual(CourseMapChromeStyle.resolve(.openPortrait), .openDuo)
        XCTAssertEqual(CourseMapChromeStyle.resolve(.book), .openDuo)
        XCTAssertEqual(CourseMapChromeStyle.resolve(.folded), .bottomStrip)
        XCTAssertEqual(CourseMapChromeStyle.resolve(.phonePortrait), .bottomStrip)
        XCTAssertEqual(CourseMapChromeStyle.resolve(.phoneLandscape), .sideStrip)
    }

    // MARK: Route: card → course → hole → next → course → card

    func testCardCourseHoleNextCourseCard() {
        let course = FinishedRoundRoute.card.openingCourse()
        XCTAssertEqual(course.screen, .course)
        XCTAssertTrue(course.showsMap)
        XCTAssertTrue(course.showsCourse)
        XCTAssertNil(course.reviewHole, "no hole under review on the course map")

        let seven = course.openingHole(7)
        XCTAssertEqual(seven.screen, .hole(7))
        XCTAssertTrue(seven.showsMap, "the same map, now the hole's review")
        XCTAssertFalse(seven.showsCourse)

        let eight = seven.applying(ReviewNavigation.next(after: 7, startingHole: 1))
        XCTAssertEqual(eight.reviewHole, 8)

        let back = eight.openingCourse()
        XCTAssertEqual(back.screen, .course, "COURSE MAP glides back out")

        let card = back.backToCard()
        XCTAssertEqual(card, .card)
        XCTAssertFalse(card.showsMap)
    }

    func testOffCourseHolesStayOnTheCourseMap() {
        let course = FinishedRoundRoute.card.openingCourse()
        XCTAssertEqual(course.openingHole(0), course)
        XCTAssertEqual(course.openingHole(19), course)
    }

    func testDebugLaunchOpensOnTheCourseMap() {
        XCTAssertEqual(FinishedRoundRoute.initial(hole: nil, courseMap: true).screen, .course)
        XCTAssertEqual(FinishedRoundRoute.initial(hole: 5, courseMap: true).screen, .hole(5),
                       "a requested hole wins")
        XCTAssertEqual(FinishedRoundRoute.initial(hole: nil), .card)
    }

    // MARK: Next hole › along the course

    func testNextHoleGlidesAlongTheCourseInPlayOrder() {
        var route = FinishedRoundRoute.card.openingCourse().openingHole(16)
        var visited: [Int] = []
        while let hole = route.reviewHole {
            visited.append(hole)
            route = route.applying(ReviewNavigation.next(after: hole, startingHole: 16))
        }
        XCTAssertEqual(visited, [16, 17, 18] + Array(1...15), "every hole once, wrapping for a later start")
        XCTAssertEqual(route, .card, "Back to card › after the round's last hole")
    }
}

/// The course map's caption scores a late-start ADD hole against its course's
/// par, like its badge and the card (#36 review).
@MainActor
final class CourseMapLoaderParTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    func testAHandScoreOnAHoleWithoutAParCountsAgainstTheCoursePar() throws {
        _ = try TestDatabase.seedCuratedCourse(id: "vineyard", name: "The Vineyard",
                                               holes: [CuratedHole(number: 1, par: 4,
                                                                   teeAnchor: GeoPoint(lat: 33.0, lng: -117.0),
                                                                   greenAnchor: GeoPoint(lat: 33.003, lng: -117.0))])
        let round = try TestDatabase.seedRound(endedAt: Date(), courseName: "The Vineyard",
                                               curatedCourseId: "vineyard")
        // ADD on a late start: the row has no par.
        let hole = try HoleRepository.setHandScore(roundID: round.id, holeNumber: 1, strokes: 5, putts: 2)
        XCTAssertNil(hole.par)

        let content = CourseMapLoader.load(round: round, courseName: "The Vineyard")
        XCTAssertTrue(content.caption.contains("5 (+1)"), content.caption)
        XCTAssertEqual(content.outlines.first { $0.number == 1 }?.isOverPar, true)
    }
}
