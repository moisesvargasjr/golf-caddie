@testable import GolfCaddie
import XCTest

final class ClubAutoPilotTests: XCTestCase {
    private let clubs = [
        WatchClub(short: "Dr", name: "Driver", avgYards: 235),
        WatchClub(short: "7i", name: "7 Iron", avgYards: 150),
        WatchClub(short: "8i", name: "8 Iron", avgYards: 138),
        WatchClub(short: "SW", name: "Sand Wedge", avgYards: 80),
    ]

    func testFollowsTheSuggestionAsTheDistanceChanges() {
        var pilot = ClubAutoPilot()
        XCTAssertEqual(pilot.update(hole: 1, strokeCount: 0, yards: 412, clubs: clubs, currentShort: nil), "Dr")
        XCTAssertNil(pilot.update(hole: 1, strokeCount: 0, yards: 400, clubs: clubs, currentShort: "Dr"), "already right")
        // The review case: drive logged, walk to the ball at 152 — no longer Driver.
        XCTAssertEqual(pilot.update(hole: 1, strokeCount: 1, yards: 152, clubs: clubs, currentShort: "Dr"), "7i")
    }

    func testHysteresisStopsFlipFlopAtTheMidpoint() {
        var pilot = ClubAutoPilot()
        // Midpoint of 7i (150) / 8i (138) is 144. At 143 the 8i is closer by only 2.
        XCTAssertNil(pilot.update(hole: 1, strokeCount: 1, yards: 143, clubs: clubs, currentShort: "7i"))
        XCTAssertEqual(pilot.update(hole: 1, strokeCount: 1, yards: 142, clubs: clubs, currentShort: "7i"), "8i")
        XCTAssertNil(pilot.update(hole: 1, strokeCount: 1, yards: 145, clubs: clubs, currentShort: "8i"), "and not straight back")
    }

    func testManualPickHoldsUntilTheShotIsLogged() {
        var pilot = ClubAutoPilot()
        _ = pilot.update(hole: 1, strokeCount: 1, yards: 150, clubs: clubs, currentShort: "7i")
        pilot.userPicked()
        XCTAssertFalse(pilot.isAuto)
        XCTAssertNil(pilot.update(hole: 1, strokeCount: 1, yards: 80, clubs: clubs, currentShort: "8i"), "manual holds")
        // Shot logged → auto again, picks for the new distance.
        XCTAssertEqual(pilot.update(hole: 1, strokeCount: 2, yards: 80, clubs: clubs, currentShort: "8i"), "SW")
        XCTAssertTrue(pilot.isAuto)
    }

    func testNewHoleResumesAuto() {
        var pilot = ClubAutoPilot()
        _ = pilot.update(hole: 1, strokeCount: 3, yards: 20, clubs: clubs, currentShort: "SW")
        pilot.userPicked()
        XCTAssertEqual(pilot.update(hole: 2, strokeCount: 0, yards: 390, clubs: clubs, currentShort: "SW"), "Dr")
    }

    func testFirstUpdateDoesNotOverrideAManualPick() {
        var pilot = ClubAutoPilot()
        pilot.userPicked()
        XCTAssertNil(pilot.update(hole: 5, strokeCount: 2, yards: 150, clubs: clubs, currentShort: "Dr"))
    }

    func testNoYardageOrNoClubsIsANoOp() {
        var pilot = ClubAutoPilot()
        XCTAssertNil(pilot.update(hole: 1, strokeCount: 0, yards: nil, clubs: clubs, currentShort: "Dr"))
        XCTAssertNil(pilot.update(hole: 1, strokeCount: 0, yards: 150, clubs: [], currentShort: "Dr"))
    }
}
