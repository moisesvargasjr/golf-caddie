import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// Clubs in play: the per-round subset of the bag (field test 1 follow-up —
/// auto-club offered clubs that weren't carried).
final class ClubsInPlayTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    private func bag(_ ids: String...) -> [Club] {
        ids.compactMap { id in Club.seedCatalog.first { $0.id == id } }
    }

    private func saveBag(_ ids: String...) throws {
        try ClubConfigurationRepository.save(ClubConfiguration(bag: ids))
    }

    @MainActor
    private func startedController(leftOut: [String]) throws -> RoundController {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(clubsLeftOut: leftOut)
        return controller
    }

    // MARK: - resolve

    func testNothingLeftOutIsTheWholeBag() {
        let b = bag("driver", "sevenIron", "putter")
        XCTAssertEqual(ClubsInPlay.resolve(bag: b, leftOut: []), b)
    }

    func testLeftOutClubsDropInBagOrder() {
        let b = bag("driver", "threeWood", "sevenIron", "sandWedge", "putter")
        let out = ClubsInPlay.resolve(bag: b, leftOut: ["sandWedge", "threeWood", "notInTheBag"])
        XCTAssertEqual(out.map(\.id), ["driver", "sevenIron", "putter"])
    }

    func testAPutterAlwaysStaysInPlay() {
        let b = bag("driver", "putter", "sevenIron")
        let out = ClubsInPlay.resolve(bag: b, leftOut: ["putter"])
        XCTAssertEqual(out.map(\.id), ["driver", "putter", "sevenIron"])
    }

    func testLeavingOutEveryFullShotClubFallsBackToTheBag() {
        let b = bag("driver", "sevenIron", "putter")
        XCTAssertEqual(ClubsInPlay.resolve(bag: b, leftOut: ["driver", "sevenIron"]), b)
    }

    func testCanLeaveOutGuardsTheLastPutterAndLastFullShotClub() throws {
        let b = bag("driver", "sevenIron", "putter")
        let driver = try XCTUnwrap(b.first), putter = try XCTUnwrap(b.last)
        XCTAssertTrue(ClubsInPlay.canLeaveOut(driver, bag: b, leftOut: []))
        XCTAssertFalse(ClubsInPlay.canLeaveOut(driver, bag: b, leftOut: ["sevenIron"]))
        XCTAssertFalse(ClubsInPlay.canLeaveOut(putter, bag: b, leftOut: []))
    }

    func testNormalizedDropsStaleIdsAndOverriddenPicks() {
        let b = bag("driver", "sevenIron", "putter")
        XCTAssertEqual(ClubsInPlay.normalized(bag: b, leftOut: ["sevenIron", "deletedClub"]),
                       ["sevenIron"])
        XCTAssertEqual(ClubsInPlay.normalized(bag: b, leftOut: ["putter"]), [],
                       "the last putter can't be out")
        XCTAssertEqual(ClubsInPlay.normalized(bag: b, leftOut: ["driver", "sevenIron"]), [],
                       "no full-shot club left → the whole bag is in play")
    }

    // MARK: - RoundController

    @MainActor
    func testStartRoundStoresTheLeftOutClubs() throws {
        try saveBag("driver", "threeWood", "sevenIron", "putter")
        let controller = try startedController(leftOut: ["threeWood"])
        XCTAssertEqual(controller.clubsInPlay.map(\.id), ["driver", "sevenIron", "putter"])
        XCTAssertEqual(try RoundRepository.activeRound()?.clubsLeftOut, ["threeWood"])
    }

    @MainActor
    func testChangingClubsMidRoundPersistsAndClearsAClubNoLongerCarried() throws {
        try saveBag("driver", "threeWood", "sevenIron", "putter")
        let controller = try startedController(leftOut: ["threeWood"])
        controller.setCurrentClub(Club.seedCatalog.first { $0.id == "sevenIron" })

        controller.setClubsLeftOut(["sevenIron"])

        XCTAssertEqual(controller.clubsInPlay.map(\.id), ["driver", "threeWood", "putter"])
        XCTAssertEqual(try RoundRepository.activeRound()?.clubsLeftOut, ["sevenIron"])
        XCTAssertNil(controller.currentClub, "the selected club was just left home")

        controller.setClubsLeftOut([])
        XCTAssertNil(try RoundRepository.activeRound()?.clubsLeftOut, "all in stores nil")
    }

    @MainActor
    func testWatchPuttUsesThePutterInPlay() throws {
        let blade = Club(id: "blade", name: "Blade", shortName: "Bl", kind: .putter,
                         defaultYards: 12, sortOrder: 18)
        try ClubRepository.save(blade)
        try saveBag("driver", "sevenIron", "putter", "blade")
        let controller = try startedController(leftOut: ["putter"])

        try controller.addPuttFromWatch()

        XCTAssertEqual(controller.currentHoleShots.last?.club, "blade")
    }

    @MainActor
    func testWatchOnlyGetsTheClubsInPlay() throws {
        try saveBag("driver", "threeWood", "sevenIron", "putter")
        let controller = try startedController(leftOut: ["threeWood"])
        let publisher = WatchStatePublisher()
        publisher.bind(controller: controller, location: LocationManager())
        XCTAssertEqual(publisher.build().clubs.map(\.short), ["Dr", "7i", "Pt"])

        controller.setClubsLeftOut([])
        XCTAssertEqual(publisher.build().clubs.map(\.short), ["Dr", "3W", "7i", "Pt"])
    }

    // MARK: - persistence + wire

    func testRoundPersistsItsLeftOutClubs() throws {
        let round = Round(id: UUID(), startedAt: Date(), endedAt: nil, courseName: nil,
                          notes: nil, clubsLeftOut: ["threeWood", "lobWedge"])
        try RoundRepository.insert(round)
        XCTAssertEqual(try RoundRepository.activeRound()?.clubsLeftOut, ["threeWood", "lobWedge"])
    }

    func testV7KeepsExistingRoundsOnTheWholeBag() throws {
        let q = try TestDatabase.makeInMemory(upTo: "v6_shot_excluded")
        let id = UUID()
        try q.write { db in
            try db.execute(
                sql: "INSERT INTO round (id, startedAt, courseName) VALUES (?, ?, ?)",
                arguments: [id.uuidString, Date(), "The Oaks"])
        }
        try Database.migrator.migrate(q, upTo: "v7_round_clubs_left_out")
        let round = try q.read { db in try Round.fetchOne(db) }
        XCTAssertEqual(round?.courseName, "The Oaks")
        XCTAssertNil(round?.clubsLeftOut)
    }

    @MainActor
    func testGlassesOnlyOfferTheClubsInPlay() throws {
        try ClubConfigurationRepository.save(
            ClubConfiguration(bag: ["driver", "threeWood", "sevenIron", "putter"]))
        let round = Round(id: UUID(), startedAt: Date(), endedAt: nil, courseName: nil,
                          notes: nil, clubsLeftOut: ["threeWood"])
        try RoundRepository.insert(round)
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let state = GlassesStateMapper.snapshot(inputs: GlassesStateInputs(
            isActive: true, currentRound: round, currentHole: hole, currentHoleShots: [],
            currentClub: nil, curatedCourseId: nil, latestLocation: nil,
            lastLocationReceivedAt: nil, locationUnavailable: false, batteryPercent: nil))
        XCTAssertEqual(state.clubs, ["Dr", "7i", "Pt"])
    }
}
