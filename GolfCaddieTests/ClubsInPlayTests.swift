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
