import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// `HoleSession` — one editor for the hole on screen. Live-hole writes route
/// to the round controller; past holes write through the store and then ask
/// the controller to refresh. Open sessions hold the hole in `HolesUnderEdit`.
@MainActor
final class HoleSessionTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let lon = -117.0
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    /// Records what the session asked the live round to do.
    @MainActor
    private final class FakeLive: LiveHoleEditing {
        var currentHole: Hole?
        var currentHoleShots: [Shot] = []
        var currentHolePenalties: [Penalty] = []
        private(set) var calls: [String] = []
        private(set) var refreshed: [Set<UUID>] = []

        init(currentHole: Hole?) { self.currentHole = currentHole }

        func updateShotClub(id: UUID, club: Club?) throws { calls.append("setClub") }
        func removeShot(id: UUID) throws { calls.append("removeShot") }
        func moveShotOnCurrentHole(id: UUID, to coordinate: CLLocationCoordinate2D) throws { calls.append("moveShot") }
        private(set) var insertAnchors: [HolePathAnchors] = []

        func insertShot(at coordinate: CLLocationCoordinate2D, club: Club?, anchors: HolePathAnchors) throws -> Shot {
            calls.append("insertShot")
            insertAnchors.append(anchors)
            return Shot(id: UUID(), holeID: currentHole?.id ?? UUID(), sequenceNumber: 1, timestamp: Date(),
                        latitude: coordinate.latitude, longitude: coordinate.longitude, gpsAccuracy: nil,
                        hadGPS: true, club: nil, source: .manual, notes: nil)
        }
        func addPenaltyToCurrentHole(type: PenaltyType, at timestamp: Date) throws { calls.append("addPenalty") }
        func removePenaltyFromCurrentHole(id: UUID) throws { calls.append("removePenalty") }
        func setPuttsOnCurrentHole(_ putts: Int) throws { calls.append("setPutts") }
        func setHandScoreOnCurrentHole(strokes: Int, putts: Int?) throws { calls.append("setHandScore") }
        func setPar(_ par: Int?, forHole holeID: UUID) throws {
            calls.append("setPar")
            try HoleRepository.setPar(holeID: holeID, par: par)
        }
        func refreshCurrentHoleShots(ifActiveHoleIn holeIDs: Set<UUID>) { refreshed.append(holeIDs) }
    }

    private func seedPlayedHole(_ number: Int, roundID: UUID) throws -> (Hole, [Shot]) {
        let hole = try TestDatabase.seedHole(roundID: roundID, holeNumber: number, par: 4, confirmedAt: t0)
        let shots = try [33.0000, 33.0010, 33.0020].enumerated().map { i, lat in
            try TestDatabase.seedShot(holeID: hole.id, sequence: i + 1, lat: lat, lng: lon, club: "driver",
                                      timestamp: t0.addingTimeInterval(Double(i) * 60))
        }
        return (hole, shots)
    }

    // MARK: - Routing

    func testLiveHoleWritesGoThroughTheController() throws {
        let round = try TestDatabase.seedRound()
        let (hole, shots) = try seedPlayedHole(1, roundID: round.id)
        let live = FakeLive(currentHole: hole)
        let session = HoleSession(hole: hole, live: live)
        XCTAssertTrue(session.isLive)

        try session.setClub(nil, forShot: shots[0].id)
        try session.moveShot(shots[0].id, to: CLLocationCoordinate2D(latitude: 33.0001, longitude: lon))
        try session.insertShot(at: CLLocationCoordinate2D(latitude: 33.0015, longitude: lon))
        try session.deleteShot(shots[1].id)
        try session.addPenalty(.water)
        try session.removePenalty(UUID())
        try session.setPutts(2)
        try session.setHandScore(strokes: 5, putts: 2)

        XCTAssertEqual(live.calls, ["setClub", "moveShot", "insertShot", "removeShot", "addPenalty",
                                    "removePenalty", "setPutts", "setHandScore"])
        XCTAssertEqual(try ShotRepository.shotsForHole(hole.id).count, 3, "the store wasn't written directly")
    }

    func testPastHoleWritesGoThroughTheStoreThenRefresh() throws {
        let round = try TestDatabase.seedRound()
        let (past, shots) = try seedPlayedHole(1, roundID: round.id)
        let current = try TestDatabase.seedHole(roundID: round.id, holeNumber: 2)
        let live = FakeLive(currentHole: current)
        let session = HoleSession(hole: past, live: live)
        XCTAssertFalse(session.isLive)

        try session.setClub(Club.seedCatalog.first { $0.id == Club.putterID }, forShot: shots[2].id)
        try session.addPenalty(.wrongBall)
        try session.moveShot(shots[1].id, to: CLLocationCoordinate2D(latitude: 33.0011, longitude: lon))

        XCTAssertTrue(live.calls.isEmpty, "a past hole never routes to the live controller")
        XCTAssertEqual(live.refreshed.count, 3)
        XCTAssertEqual(live.refreshed.last, [past.id])
        XCTAssertEqual(session.shots[2].isPutt, true)
        let moved = try XCTUnwrap(session.shots.first { $0.id == shots[1].id })
        XCTAssertEqual(moved.locationSource, .manual)
        XCTAssertEqual(moved.confidence, 1.0)
        XCTAssertEqual(try XCTUnwrap(moved.latitude), 33.0011, accuracy: 1e-9)
        XCTAssertEqual(try PenaltyRepository.penaltiesForHole(past.id).map(\.strokeCount), [2])
    }

    func testFinishedRoundWorksWithoutAController() throws {
        let round = try TestDatabase.seedRound(endedAt: t0)
        let (hole, shots) = try seedPlayedHole(3, roundID: round.id)
        let session = HoleSession(hole: hole, live: nil)
        try session.deleteShot(shots[0].id)
        XCTAssertEqual(session.shots.map(\.sequenceNumber), [1, 2])
        try session.setPar(5)
        XCTAssertEqual(session.par, 5)
    }

    func testRealControllerLiveRoute() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound(startingHole: 1, mode: .tracking)
        let hole = try XCTUnwrap(controller.currentHole)
        let session = HoleSession(hole: hole, live: controller)
        try session.insertShot(at: CLLocationCoordinate2D(latitude: 33.0, longitude: lon))
        try session.addPenalty(.wrongBall)
        XCTAssertEqual(controller.currentHoleShots.count, 1)
        XCTAssertEqual(session.shots.count, 1)
        XCTAssertEqual(session.score, 3, "1 stroke + wrong ball (2)")
        let penalty = try XCTUnwrap(session.penalties.first)
        try session.removePenalty(penalty.id)
        XCTAssertTrue(controller.currentHolePenalties.isEmpty)
        XCTAssertEqual(session.score, 1)
    }

    // MARK: - HolesUnderEdit

    func testOpenRegistersAndCloseUnregisters() throws {
        let round = try TestDatabase.seedRound()
        let (hole, _) = try seedPlayedHole(1, roundID: round.id)
        let session = HoleSession(hole: hole, live: nil)
        XCTAssertFalse(HolesUnderEdit.contains(hole.id))
        session.open()
        session.open() // idempotent
        XCTAssertTrue(HolesUnderEdit.contains(hole.id))
        session.close()
        XCTAssertFalse(HolesUnderEdit.contains(hole.id), "one open = one registration")
    }

    func testRowlessHoleRegistersOnceItsScoreIsEntered() throws {
        let round = try TestDatabase.seedRound()
        let session = HoleSession(roundID: round.id, holeNumber: 2, live: nil)
        session.open()
        XCTAssertNil(session.hole)
        try session.setHandScore(strokes: 4, putts: 1)
        let id = try XCTUnwrap(session.hole?.id)
        XCTAssertTrue(HolesUnderEdit.contains(id))
        session.close()
        XCTAssertFalse(HolesUnderEdit.contains(id))
    }

    // MARK: - Scores

    func testPenaltyStrokesInScore() throws {
        let round = try TestDatabase.seedRound()
        let (hole, _) = try seedPlayedHole(1, roundID: round.id)
        let session = HoleSession(hole: hole, live: nil)
        try session.addPenalty(.wrongBall)
        try session.addPenalty(.obOrLost)
        XCTAssertEqual(session.penaltyStrokes, 3)
        XCTAssertEqual(session.score, 6, "3 shots + 2 + 1")
    }

    func testLateStartHoleNeedsEntryUntilAHandScore() throws {
        var round = try TestDatabase.seedRound()
        round.startingHole = 4
        try RoundRepository.update(round)
        let session = HoleSession(roundID: round.id, holeNumber: 2, live: nil)
        XCTAssertTrue(session.needsEntry)
        XCTAssertFalse(session.isTracked)
        XCTAssertNil(session.score)
        XCTAssertNil(try HoleRepository.hole(forRound: round.id, number: 2), "opening creates no row")

        try session.setHandScore(strokes: 6, putts: 2)
        XCTAssertFalse(session.needsEntry)
        XCTAssertTrue(session.isHandScored)
        XCTAssertEqual(session.scoreSource, .hand)
        XCTAssertEqual(session.score, 6)
        XCTAssertEqual(session.putts, 2)

        try session.setPutts(3)
        XCTAssertEqual(session.putts, 3)
        XCTAssertEqual(session.score, 6, "putts on a hand-scored hole don't change its strokes")
    }

    func testTrackedPuttsOnAPastHole() throws {
        let round = try TestDatabase.seedRound()
        let (hole, _) = try seedPlayedHole(1, roundID: round.id)
        let session = HoleSession(hole: hole, live: nil)
        XCTAssertTrue(session.isTracked)
        try session.setPutts(2)
        XCTAssertEqual(session.putts, 2)
        XCTAssertEqual(session.score, 5)
    }

    // MARK: - Insert ordering through the session

    func testInsertShotOnAPastHoleIsNumberedAlongTheHole() throws {
        let round = try TestDatabase.seedRound()
        let (hole, shots) = try seedPlayedHole(1, roundID: round.id)
        let session = HoleSession(hole: hole, live: nil)
        let inserted = try session.insertShot(at: CLLocationCoordinate2D(latitude: 33.0005, longitude: lon))
        XCTAssertEqual(session.shots.map(\.id), [shots[0].id, inserted.id, shots[1].id, shots[2].id])
        XCTAssertEqual(session.shots.map(\.sequenceNumber), [1, 2, 3, 4])
        XCTAssertEqual(inserted.source, .manual)
    }

    func testACourseRelinkOnTheSameHoleOrdersNewShotsByTheNewCourse() throws {
        // Course A's tee/green, then the round is re-linked to course B while
        // hole 1 stays on screen: hold-to-add must use B's anchors.
        let round = try TestDatabase.seedRound()
        let (hole, _) = try seedPlayedHole(1, roundID: round.id)
        let live = FakeLive(currentHole: hole)
        let courseA = HolePathAnchors(tee: CLLocationCoordinate2D(latitude: 33.0, longitude: lon),
                                      green: CLLocationCoordinate2D(latitude: 33.003, longitude: lon))
        let courseB = HolePathAnchors(tee: CLLocationCoordinate2D(latitude: 34.0, longitude: lon),
                                      green: CLLocationCoordinate2D(latitude: 34.003, longitude: lon))
        let session = HoleSession(hole: hole, live: live, anchors: courseA)
        session.anchors = courseB
        _ = try session.insertShot(at: CLLocationCoordinate2D(latitude: 34.001, longitude: lon))
        XCTAssertEqual(live.insertAnchors.map(\.tee?.latitude), [34.0])
        XCTAssertEqual(live.insertAnchors.map(\.green?.latitude), [34.003])
    }
}
