import SwiftUI
import XCTest
@testable import GolfCaddie

final class HomeViewModelTests: XCTestCase {
    // MARK: Fixtures

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func round(started: Date, ended: Date?, course: String? = "Native Oaks") -> Round {
        Round(id: UUID(), startedAt: started, endedAt: ended, courseName: course, notes: nil,
              clubsLeftOut: nil)
    }

    // MARK: Start mode

    func testInitialModeFollowsSettingsCasualDefault() {
        XCTAssertEqual(RoundStartMode.initial(casualDefault: false), .tracking)
        XCTAssertEqual(RoundStartMode.initial(casualDefault: true), .casual)
    }

    func testModeCopy() {
        XCTAssertEqual(RoundStartMode.tracking.title, "Track shots")
        XCTAssertEqual(RoundStartMode.tracking.caption, "WATCH + MAP + CLUBS")
        XCTAssertEqual(RoundStartMode.casual.title, "Casual")
        XCTAssertEqual(RoundStartMode.casual.caption, "YARDAGE + SCORE")
    }

    // MARK: Start state

    func testStartStateDefaults() {
        let state = HomeStartState(mode: .tracking)
        XCTAssertEqual(state.startingHole, 1)
        XCTAssertNil(state.curatedCourseId)
        XCTAssertTrue(state.showsClubsRow)
    }

    func testStartingHoleWrapsBothWays() {
        let first = HomeStartState(mode: .tracking)
        XCTAssertEqual(first.steppingHole(by: -1).startingHole, 18)
        XCTAssertEqual(first.steppingHole(by: 1).startingHole, 2)
        let last = HomeStartState(mode: .tracking, startingHole: 18)
        XCTAssertEqual(last.steppingHole(by: 1).startingHole, 1)
        XCTAssertEqual(last.steppingHole(by: -1).startingHole, 17)
    }

    func testSteppingReturnsACopy() {
        let original = HomeStartState(mode: .tracking, startingHole: 4)
        _ = original.steppingHole(by: 1)
        _ = original.with(mode: .casual)
        _ = original.with(courseId: "oaks")
        XCTAssertEqual(original, HomeStartState(mode: .tracking, startingHole: 4))
    }

    func testOutOfRangeStartingHoleIsClamped() {
        XCTAssertEqual(HomeStartState(mode: .tracking, startingHole: 0).startingHole, 1)
        XCTAssertEqual(HomeStartState(mode: .tracking, startingHole: 40).startingHole, 18)
    }

    func testCasualHidesTheClubsRow() {
        XCTAssertFalse(HomeStartState(mode: .casual).showsClubsRow)
    }

    func testCourseLabel() {
        let names = ["oaks": "Native Oaks"]
        XCTAssertEqual(HomeStartState(mode: .tracking).courseLabel(names: names), "Auto-detect")
        XCTAssertEqual(HomeStartState(mode: .tracking).with(courseId: "oaks").courseLabel(names: names),
                       "Native Oaks")
        // A course that left the catalog still reads as linked, not blank.
        XCTAssertEqual(HomeStartState(mode: .tracking).with(courseId: "gone").courseLabel(names: names),
                       "Linked course")
    }

    func testBeginSubtitleOpen() {
        let tracking = HomeStartState(mode: .tracking)
        XCTAssertEqual(tracking.beginSubtitle(clubsInPlay: 11, style: .open), "TRACKED · 11 CLUBS · HOLE 1")
        XCTAssertEqual(tracking.steppingHole(by: 9).beginSubtitle(clubsInPlay: 11, style: .open),
                       "TRACKED · 11 CLUBS · HOLE 10 · EARLIER HOLES ADDED LATER")
        XCTAssertEqual(HomeStartState(mode: .casual).beginSubtitle(clubsInPlay: 11, style: .open),
                       "CASUAL · HOLE 1")
    }

    func testBeginSubtitleFolded() {
        XCTAssertEqual(HomeStartState(mode: .tracking).beginSubtitle(clubsInPlay: 11, style: .folded),
                       "TRACKED · HOLE 1")
        XCTAssertEqual(HomeStartState(mode: .casual, startingHole: 10)
                        .beginSubtitle(clubsInPlay: 11, style: .folded),
                       "CASUAL · HOLE 10 · ADD EARLIER LATER")
    }

    func testRequestCarriesEverything() {
        let state = HomeStartState(mode: .casual, startingHole: 10).with(courseId: "oaks")
        let request = state.request(clubsLeftOut: ["lobWedge"])
        XCTAssertEqual(request, HomeStartRequest(startingHole: 10, clubsLeftOut: ["lobWedge"],
                                                 mode: .casual, curatedCourseId: "oaks"))
    }

    // MARK: Last entry selection

    func testLastEntryIsTheMostRecentEndedRound() {
        let older = round(started: date(2026, 10, 18), ended: date(2026, 10, 18, 13))
        let newest = round(started: date(2026, 10, 23), ended: date(2026, 10, 23, 13))
        let abandoned = round(started: date(2026, 10, 24), ended: nil)
        XCTAssertEqual(HomeViewModel.lastEntry(from: [older, abandoned, newest]), newest)
    }

    func testNoLastEntryWithoutEndedRounds() {
        XCTAssertNil(HomeViewModel.lastEntry(from: []))
        XCTAssertNil(HomeViewModel.lastEntry(from: [round(started: date(2026, 10, 24), ended: nil)]))
    }

    func testEarlierRoundsSkipTheLastEntryAndRespectTheLimit() {
        let rounds = (1...6).map { day in
            round(started: date(2026, 10, day), ended: date(2026, 10, day, 13))
        }
        let last = HomeViewModel.lastEntry(from: rounds)
        let earlier = HomeViewModel.earlierRounds(from: rounds, excluding: last, limit: 3)
        XCTAssertEqual(earlier.map(\.id), [rounds[4].id, rounds[3].id, rounds[2].id])
        XCTAssertFalse(earlier.contains(where: { $0.id == last?.id }))
    }

    func testEarlierRoundsLeaveOutUnfinishedRounds() {
        let ended = round(started: date(2026, 10, 1), ended: date(2026, 10, 1, 13))
        let open = round(started: date(2026, 10, 2), ended: nil)
        XCTAssertEqual(HomeViewModel.earlierRounds(from: [ended, open], excluding: nil, limit: 3), [ended])
    }

    // MARK: Entry summary

    func testEntryTotalsAndCells() {
        let r = round(started: date(2026, 10, 23, 8), ended: date(2026, 10, 23, 12, 12))
        let holes = [
            HomeHoleInput(number: 2, par: 5, strokes: 6, confirmed: true),
            HomeHoleInput(number: 1, par: 4, strokes: 3, confirmed: true),
            HomeHoleInput(number: 3, par: 3, strokes: 3, confirmed: true),
            // Played but not confirmed: counts toward the score, no cell.
            HomeHoleInput(number: 4, par: 4, strokes: 5, confirmed: false),
            // Never played: neither its strokes nor its par count.
            HomeHoleInput(number: 5, par: 4, strokes: 0, confirmed: false),
        ]
        let entry = HomeRoundEntry.make(round: r, holes: holes)
        XCTAssertEqual(entry.score, 17)
        XCTAssertEqual(entry.par, 16)
        XCTAssertEqual(entry.deltaText, "+1")
        XCTAssertEqual(entry.cells.map(\.number), [1, 2, 3])
        XCTAssertEqual(entry.cells.map(\.shape), [.circle, .square, .plain])
        XCTAssertEqual(entry.courseTitle, "Native Oaks")
        XCTAssertEqual(entry.durationText, "4H 12M")
    }

    func testEntryDeltaHiddenWithoutParOrAtEven() {
        let r = round(started: date(2026, 10, 23), ended: date(2026, 10, 23, 10))
        let noPar = HomeRoundEntry.make(round: r, holes: [HomeHoleInput(number: 1, par: nil, strokes: 5, confirmed: true)])
        XCTAssertNil(noPar.deltaText)
        XCTAssertEqual(noPar.cells.first?.shape, .plain)
        let even = HomeRoundEntry.make(round: r, holes: [HomeHoleInput(number: 1, par: 4, strokes: 4, confirmed: true)])
        XCTAssertEqual(even.deltaText, "E")
        let under = HomeRoundEntry.make(round: r, holes: [HomeHoleInput(number: 1, par: 4, strokes: 3, confirmed: true)])
        XCTAssertEqual(under.deltaText, "-1")
    }

    func testEntryFallbacks() {
        let r = round(started: date(2026, 10, 23), ended: nil, course: "  ")
        let entry = HomeRoundEntry.make(round: r, holes: [])
        XCTAssertEqual(entry.courseTitle, "Untitled round")
        XCTAssertEqual(entry.durationText, "—")
        XCTAssertEqual(entry.score, 0)
    }

    func testEntryDateTexts() {
        let r = round(started: date(2026, 10, 23, 8), ended: date(2026, 10, 23, 12, 12))
        let entry = HomeRoundEntry.make(round: r, holes: [])
        XCTAssertEqual(entry.dateText, "OCT 23")
        XCTAssertEqual(entry.dateAndDurationText, "OCT 23 · 4H 12M")
    }

    // MARK: Bag copy

    func testBagCopy() {
        XCTAssertEqual(HomeViewModel.bagInPlayText(inPlay: 11, total: 14), "11 OF 14 IN PLAY")
        XCTAssertEqual(HomeViewModel.bagButtonText(total: 14), "THE BAG · 14 CLUBS")
        XCTAssertEqual(HomeViewModel.clubsRowText(inPlay: 11, total: 14), "11/14")
        XCTAssertEqual(HomeViewModel.bagAccessibilityLabel(inPlay: 11, total: 14),
                       "The bag: 11 of 14 clubs in play. Change the clubs in play.")
    }

    func testDateStrips() {
        let friday = date(2026, 10, 23)
        XCTAssertEqual(HomeViewModel.dateStrip(friday, style: .open), "OCT 23 · FRIDAY")
        XCTAssertEqual(HomeViewModel.dateStrip(friday, style: .folded), "OCT 23 · FRI")
    }

    // MARK: Watch status

    func testWatchStatus() {
        XCTAssertEqual(WatchLinkStatus.resolve(isSupported: false, isActivated: true, isPaired: true,
                                               isAppInstalled: true, isReachable: true), .unavailable)
        XCTAssertEqual(WatchLinkStatus.resolve(isSupported: true, isActivated: false, isPaired: true,
                                               isAppInstalled: true, isReachable: false), .unavailable)
        XCTAssertEqual(WatchLinkStatus.resolve(isSupported: true, isActivated: true, isPaired: false,
                                               isAppInstalled: false, isReachable: false), .unavailable)
        XCTAssertEqual(WatchLinkStatus.resolve(isSupported: true, isActivated: true, isPaired: true,
                                               isAppInstalled: false, isReachable: false), .unavailable)
        XCTAssertEqual(WatchLinkStatus.resolve(isSupported: true, isActivated: true, isPaired: true,
                                               isAppInstalled: true, isReachable: false), .asleep)
        XCTAssertEqual(WatchLinkStatus.resolve(isSupported: true, isActivated: true, isPaired: true,
                                               isAppInstalled: true, isReachable: true), .ready)
    }

    func testWatchStatusCopy() {
        XCTAssertEqual(WatchLinkStatus.ready.label(style: .open), "WATCH READY")
        XCTAssertEqual(WatchLinkStatus.ready.label(style: .folded), "WATCH")
        XCTAssertEqual(WatchLinkStatus.asleep.label(style: .open), "WATCH ASLEEP")
        XCTAssertEqual(WatchLinkStatus.unavailable.label(style: .folded), "NO WATCH")
        XCTAssertTrue(WatchLinkStatus.ready.isLive)
        XCTAssertFalse(WatchLinkStatus.asleep.isLive)
    }
}
