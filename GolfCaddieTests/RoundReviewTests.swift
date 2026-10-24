import XCTest
@testable import GolfCaddie

/// Duo v2 PR 7: a finished round's review on the round map. The review mode's
/// traits, Next hole ›, the round actions in ···, the result text, and the
/// Logbook → card → hole routing.
@MainActor
final class RoundReviewTests: XCTestCase {
    // MARK: Review traits

    func testReviewTraits() {
        let review = RoundMapMode.review
        XCTAssertTrue(review.tracksShots, "pins, the shot list and the club list stay editable")
        XCTAssertFalse(review.showsYardage, "the result card replaces the yardage")
        XCTAssertFalse(review.allowsAutoHide)
        XCTAssertTrue(review.allowsHoldToAdd)
        XCTAssertFalse(review.entryUsesScoreGrid, "untracked holes get the strokes / putts entry")
        XCTAssertFalse(review.showsRoundSoFar)
        XCTAssertEqual(review.captionTag, "REVIEW")
        XCTAssertTrue(review.advancesWithNextHole)
        XCTAssertFalse(review.showsWatchStatus)
        XCTAssertTrue(review.editsPuttsInResult)
        XCTAssertEqual(review.cardButtonTitle, "‹ CARD")
    }

    func testLiveModesKeepTheirTraits() {
        for mode in [RoundMapMode.tracking, .casual] {
            XCTAssertTrue(mode.showsYardage)
            XCTAssertTrue(mode.allowsAutoHide)
            XCTAssertFalse(mode.advancesWithNextHole)
            XCTAssertTrue(mode.showsWatchStatus)
            XCTAssertFalse(mode.editsPuttsInResult)
            XCTAssertEqual(mode.cardButtonTitle, "CARD")
        }
    }

    func testReviewHolesResolveAsPastOrEntry() {
        XCTAssertEqual(HolePanelState.resolve(mode: .review, isLive: false, isTracked: true,
                                              needsEntry: false, isHandScored: false), .pastTracked)
        XCTAssertEqual(HolePanelState.resolve(mode: .review, isLive: false, isTracked: false,
                                              needsEntry: true, isHandScored: false), .entry)
        XCTAssertEqual(HolePanelState.resolve(mode: .review, isLive: false, isTracked: false,
                                              needsEntry: false, isHandScored: true), .entry)
    }

    func testReviewKeepsTheControlsUp() {
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: false, shotSelected: false,
                                                   dragging: false, modeAllowsAutoHide: false), [.modeOff])
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: true, entryOpen: false, shotSelected: false,
                                                   dragging: false, modeAllowsAutoHide: false),
                       [.question, .modeOff])
        XCTAssertEqual(AutoHideWiring.pauseReasons(questionOpen: false, entryOpen: false, shotSelected: false,
                                                   dragging: false), [], "live modes are unchanged")
    }

    func testReviewNeverHidesOnATimer() {
        let scheduler = TestAutoHideScheduler()
        let folded = DisplayContext(layoutClass: .compact, posture: .closed,
                                    windowSize: CGSize(width: 466, height: 678))
        let controller = AutoHideController(display: folded, scheduler: scheduler)
        AutoHideWiring.apply([.modeOff], to: controller)
        scheduler.advance(by: 60)
        XCTAssertTrue(controller.controlsVisible)
        controller.setManuallyHidden(true)
        XCTAssertFalse(controller.controlsVisible, "the manual hide button still works")
    }

    // MARK: ‹ › in review: 1…18, stop at the ends

    func testChevronsWithoutALiveHole() {
        XCTAssertNil(HoleNavigation.previous(viewing: 1, live: nil))
        XCTAssertEqual(HoleNavigation.previous(viewing: 7, live: nil), .view(6))
        XCTAssertEqual(HoleNavigation.next(viewing: 7, live: nil), .view(8))
        XCTAssertNil(HoleNavigation.next(viewing: 18, live: nil))
    }

    // MARK: Next hole ›

    func testNextHoleFromHoleOneStopsAt18() {
        XCTAssertEqual(ReviewNavigation.next(after: 1, startingHole: 1), .hole(2))
        XCTAssertEqual(ReviewNavigation.next(after: 17, startingHole: 1), .hole(18))
        XCTAssertEqual(ReviewNavigation.next(after: 18, startingHole: 1), .backToCard)
    }

    func testPreV10RoundsStartOnOne() {
        XCTAssertEqual(ReviewNavigation.next(after: 9, startingHole: nil), .hole(10))
        XCTAssertEqual(ReviewNavigation.next(after: 18, startingHole: nil), .backToCard)
        XCTAssertEqual(ReviewNavigation.firstHole(startingHole: nil), 1)
    }

    func testNextHoleWrapsPast18ForALaterStart() {
        XCTAssertEqual(ReviewNavigation.next(after: 10, startingHole: 10), .hole(11))
        XCTAssertEqual(ReviewNavigation.next(after: 18, startingHole: 10), .hole(1))
        XCTAssertEqual(ReviewNavigation.next(after: 8, startingHole: 10), .hole(9))
        XCTAssertEqual(ReviewNavigation.next(after: 9, startingHole: 10), .backToCard,
                       "the hole before the start is the round's last")
        XCTAssertEqual(ReviewNavigation.firstHole(startingHole: 10), 10)
    }

    func testPlayOrderCoversEveryHoleOnce() {
        let order = ReviewNavigation.playOrder(startingHole: 7)
        XCTAssertEqual(order.first, 7)
        XCTAssertEqual(order.last, 6)
        XCTAssertEqual(Set(order), Set(1...18))
        XCTAssertEqual(order.count, 18)
    }

    func testOutOfRangeStartIsTreatedAsHoleOne() {
        XCTAssertEqual(ReviewNavigation.playOrder(startingHole: 0), Array(1...18))
        XCTAssertEqual(ReviewNavigation.playOrder(startingHole: 19), Array(1...18))
        XCTAssertEqual(ReviewNavigation.next(after: 40, startingHole: 1), .backToCard)
    }

    func testNextTitles() {
        XCTAssertEqual(ReviewNavigation.Next.hole(8).title, "Next hole ›")
        XCTAssertEqual(ReviewNavigation.Next.backToCard.title, "Back to card ›")
        XCTAssertEqual(ReviewNavigation.Next.hole(8).shortTitle, "NEXT HOLE ›")
        XCTAssertEqual(ReviewNavigation.Next.backToCard.shortTitle, "BACK TO CARD ›")
    }

    // MARK: Result text

    func testTrackedResultLabel() {
        XCTAssertEqual(ReviewText.resultLabel(fullShots: 3, penaltyStrokes: 0, putts: 2, handScored: false),
                       "RESULT · 3 SHOTS + 2 PUTTS")
        XCTAssertEqual(ReviewText.resultLabel(fullShots: 1, penaltyStrokes: 2, putts: 1, handScored: false),
                       "RESULT · 1 SHOT + 2 PEN + 1 PUTT")
        XCTAssertEqual(ReviewText.resultLabel(fullShots: 4, penaltyStrokes: 0, putts: 2, handScored: true),
                       "RESULT · ENTERED BY HAND")
    }

    func testToParLabel() {
        XCTAssertEqual(ReviewText.toParLabel(score: 5, par: 4), "+1 · BOGEY")
        XCTAssertEqual(ReviewText.toParLabel(score: 4, par: 4), "E · PAR")
        XCTAssertEqual(ReviewText.toParLabel(score: 3, par: 4), "-1 · BIRDIE")
        XCTAssertEqual(ReviewText.toParLabel(score: 6, par: 4), "+2 · DOUBLE BOGEY")
        XCTAssertEqual(ReviewText.toParLabel(score: 5, par: nil), "")
        XCTAssertEqual(ReviewText.toParLabel(score: nil, par: 4), "")
    }

    func testRoundText() {
        let holes: [(par: Int?, score: Int?)] = [(par: 4, score: 5), (par: 3, score: 3), (par: 5, score: nil),
                                                (par: 4, score: 6)]
        XCTAssertEqual(ReviewText.roundText(dateText: "OCT 23", holes: holes), "OCT 23 · 14 (+3)")
        XCTAssertEqual(ReviewText.roundText(dateText: "OCT 23", holes: [(par: 4, score: 4)]), "OCT 23 · 4 (E)")
        XCTAssertEqual(ReviewText.roundText(dateText: "OCT 23", holes: [(par: nil, score: 4)]), "OCT 23 · 4")
        XCTAssertEqual(ReviewText.roundText(dateText: "OCT 23", holes: [(par: 4, score: nil)]), "OCT 23 · NO SCORE")
    }

    func testShareText() {
        XCTAssertEqual(ReviewText.shareText(courseName: "Native Oaks", roundText: "OCT 23 · 79 (+7)"),
                       "Native Oaks · OCT 23 · 79 (+7) — from The Fairway Logbook")
        XCTAssertEqual(ReviewText.shareText(courseName: nil, roundText: "OCT 23 · 79 (+7)"),
                       "Golf round · OCT 23 · 79 (+7) — from The Fairway Logbook")
    }

    func testPuttsStepperStaysInRange() {
        XCTAssertEqual(ReviewPutts.stepped(2, by: 1), 3)
        XCTAssertEqual(ReviewPutts.stepped(0, by: -1), 0)
        XCTAssertEqual(ReviewPutts.stepped(nil, by: 1), 1)
        XCTAssertEqual(ReviewPutts.stepped(HoleScoring.puttRange.upperBound, by: 1),
                       HoleScoring.puttRange.upperBound)
        XCTAssertTrue(ReviewPutts.canDecrease(1))
        XCTAssertFalse(ReviewPutts.canDecrease(0))
        XCTAssertFalse(ReviewPutts.canIncrease(HoleScoring.puttRange.upperBound))
    }

    // MARK: Round actions (···)

    private func round(ended: Bool, course: String? = nil) -> Round {
        Round(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_792_700_000),
              endedAt: ended ? Date(timeIntervalSince1970: 1_792_714_000) : nil,
              courseName: "Native Oaks", notes: nil, curatedCourseId: course, clubsLeftOut: nil)
    }

    func testJustEndedRoundCanResume() {
        let actions = RoundActionsAvailability.resolve(round: round(ended: true), canResumeHere: true,
                                                       liveRoundActive: false, linkedCourseName: nil)
        XCTAssertTrue(actions.canShare)
        XCTAssertTrue(actions.canResume)
        XCTAssertTrue(actions.canDelete)
        XCTAssertTrue(actions.canChangeCourse)
    }

    func testResumeOnlyWhereTheHostCanResume() {
        // Logbook / Home open rounds without a resume route (as before PR 7:
        // only the end-of-round review offered Resume).
        let actions = RoundActionsAvailability.resolve(round: round(ended: true), canResumeHere: false,
                                                       liveRoundActive: false, linkedCourseName: nil)
        XCTAssertFalse(actions.canResume)
        XCTAssertTrue(actions.canDelete)
    }

    func testNoResumeOrDeleteWhileARoundIsLive() {
        let actions = RoundActionsAvailability.resolve(round: round(ended: true), canResumeHere: true,
                                                       liveRoundActive: true, linkedCourseName: nil)
        XCTAssertFalse(actions.canResume)
        XCTAssertFalse(actions.canDelete)
    }

    func testUnfinishedRoundCannotBeResumedOrDeletedHere() {
        let actions = RoundActionsAvailability.resolve(round: round(ended: false), canResumeHere: true,
                                                       liveRoundActive: false, linkedCourseName: nil)
        XCTAssertFalse(actions.canResume)
        XCTAssertFalse(actions.canDelete)
        XCTAssertTrue(actions.canShare)
    }

    func testCourseTitle() {
        let linked = RoundActionsAvailability.resolve(round: round(ended: true, course: "native-oaks"),
                                                      canResumeHere: false, liveRoundActive: false,
                                                      linkedCourseName: "Native Oaks")
        XCTAssertEqual(linked.courseTitle, "Course · Native Oaks ✓")
        XCTAssertTrue(linked.isCourseLinked)
        let unlinked = RoundActionsAvailability.resolve(round: round(ended: true), canResumeHere: false,
                                                        liveRoundActive: false, linkedCourseName: nil)
        XCTAssertEqual(unlinked.courseTitle, "Link course…")
        XCTAssertFalse(unlinked.isCourseLinked)
        let unknown = RoundActionsAvailability.resolve(round: round(ended: true, course: "gone"),
                                                       canResumeHere: false, liveRoundActive: false,
                                                       linkedCourseName: nil)
        XCTAssertEqual(unknown.courseTitle, "Course · linked ✓")
    }

    // MARK: Logbook → card → hole

    func testOpensOnTheCard() {
        XCTAssertEqual(FinishedRoundRoute.card.screen, .card)
        XCTAssertNil(FinishedRoundRoute.card.reviewHole)
        XCTAssertEqual(FinishedRoundRoute.initial(hole: nil), .card)
    }

    func testCardHoleOpensTheReview() {
        let route = FinishedRoundRoute.card.openingHole(7)
        XCTAssertEqual(route.screen, .hole(7))
        XCTAssertEqual(route.reviewHole, 7)
        XCTAssertEqual(FinishedRoundRoute.initial(hole: 12), FinishedRoundRoute.card.openingHole(12))
    }

    func testOffCardHolesAreIgnored() {
        XCTAssertEqual(FinishedRoundRoute.card.openingHole(0), .card)
        XCTAssertEqual(FinishedRoundRoute.card.openingHole(19), .card)
        XCTAssertEqual(FinishedRoundRoute.initial(hole: 25), .card)
    }

    func testNextHoleAndBackToCard() {
        let onSeven = FinishedRoundRoute.card.openingHole(7)
        XCTAssertEqual(onSeven.applying(.hole(8)).reviewHole, 8)
        XCTAssertEqual(onSeven.applying(.backToCard), .card)
        XCTAssertEqual(onSeven.backToCard(), .card)
        XCTAssertEqual(onSeven.openingHole(3).reviewHole, 3, "‹ › move within the review")
    }
}
