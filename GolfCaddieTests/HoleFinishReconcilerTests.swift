import CoreLocation
@testable import GolfCaddie
import GRDB
import XCTest

/// The watch "Finish Hole" check: the confirmed score is the truth, tracked
/// strokes are evidence.
@MainActor
final class HoleFinishReconcilerTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let holeID = UUID()

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDown() {
        TestDatabase.restore()
        queue = nil
    }

    private func shot(_ seq: Int, _ source: ShotSource = .watchAuto, lat: Double? = 33.0, putt: Bool = false) -> Shot {
        Shot(id: UUID(), holeID: holeID, sequenceNumber: seq, timestamp: Date(), latitude: lat,
             longitude: lat == nil ? nil : -117.0, gpsAccuracy: 5, hadGPS: lat != nil, club: nil,
             source: source, notes: nil, isPutt: putt)
    }

    // MARK: - Pure plan

    func testMatchingScoreChangesNothingButPutts() {
        let plan = HoleFinishReconciler.plan(shots: [shot(1), shot(2, lat: 33.002)], penaltyStrokes: 0, putts: 2, score: 4)
        XCTAssertEqual(plan, .init(puttsToAdd: 2))
    }

    func testMissedShotsAreAdded() {
        // Tracked a drive; golfer says 5 with 2 putts and a penalty → 2 full shots, one missing.
        let plan = HoleFinishReconciler.plan(shots: [shot(1)], penaltyStrokes: 1, putts: 2, score: 5)
        XCTAssertEqual(plan, .init(puttsToAdd: 2, fullShotsToAdd: 1))
    }

    func testPracticeSwingIsThePhantomNotTheRealShotAfterIt() {
        let practice = shot(1, lat: 33.00000)
        let real = shot(2, lat: 33.00001) // ~1 m away: same spot, swung again
        let approach = shot(3, lat: 33.00150) // ~165 m on
        let plan = HoleFinishReconciler.plan(shots: [practice, real, approach], penaltyStrokes: 0, putts: 2, score: 4)
        XCTAssertEqual(plan.excludeIDs, [practice.id], "the EARLIER of a same-spot pair is the practice swing")
        XCTAssertEqual(plan.puttsToAdd, 2)
    }

    func testUnplacedAutoShotGoesFirstAndHandLoggedNever() {
        let marked = shot(1, .watchManual)
        let unplaced = shot(2, .watchAuto, lat: nil)
        let placed = shot(3, .watchAuto, lat: 33.002)
        let one = HoleFinishReconciler.plan(shots: [marked, unplaced, placed], penaltyStrokes: 0, putts: 1, score: 3)
        XCTAssertEqual(one.excludeIDs, [unplaced.id])

        // Told there are 3 phantoms but only 2 auto shots exist: the MARK stays.
        let many = HoleFinishReconciler.plan(shots: [marked, unplaced, placed], penaltyStrokes: 0, putts: 0, score: 0)
        XCTAssertEqual(Set(many.excludeIDs), [unplaced.id, placed.id])
        XCTAssertEqual(many.unresolvedExtra, 1)
    }

    func testSurplusPuttTapsDropNewestFirst() {
        let p1 = shot(2, .watchManual, putt: true), p2 = shot(3, .watchManual, putt: true), p3 = shot(4, .watchManual, putt: true)
        let plan = HoleFinishReconciler.plan(shots: [shot(1), p1, p2, p3], penaltyStrokes: 0, putts: 1, score: 2)
        XCTAssertEqual(plan.excludeIDs, [p2.id, p3.id])
    }

    // MARK: - Applied through the watch command

    func testFinishHoleFromTheWatchReconcilesExcludesAndAdvances() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator(debounceInterval: 0.05)
        coordinator.attach(controller: controller, location: location)
        let round = try XCTUnwrap(controller.currentRound)

        // Tracked: practice swing + real tee shot (same spot), then one PUTT tap.
        let here = CLLocationCoordinate2D(latitude: 33.0, longitude: -117.0)
        let practice = try controller.ingestAutoShot(at: here, accuracy: 5, club: nil, timestamp: Date().addingTimeInterval(-300))
        _ = try controller.ingestAutoShot(at: here, accuracy: 5, club: nil, timestamp: Date().addingTimeInterval(-280))
        coordinator.ingest(.command(.puttPlusOne))

        // Par-3: one shot on, two putts → 3.
        let wire = try WatchToPhoneMessage.decode(WatchToPhoneMessage.command(.finishHole(putts: 2, score: 3)).encoded())
        coordinator.ingest(wire)
        await coordinator.waitUntilIdle()

        let holes = try HoleRepository.holesForRound(round.id)
        let first = try XCTUnwrap(holes.first { $0.holeNumber == 1 })
        let active = try ShotRepository.shotsForHole(first.id)
        XCTAssertEqual(active.filter { !$0.isPutt }.count, 1)
        XCTAssertEqual(active.filter(\.isPutt).count, 2, "the second putt was added")
        XCTAssertEqual(try ShotRepository.count(forHole: first.id), 3, "the scorecard counts what was confirmed")
        XCTAssertNotNil(first.confirmedAt)

        // Excluded, not deleted: still there, with its location, restorable.
        let excluded = try ShotRepository.excludedShotsForHole(first.id)
        XCTAssertEqual(excluded.map(\.id), [practice])
        XCTAssertNotNil(excluded.first?.latitude)
        try ShotRepository.setExcluded([practice], at: nil)
        XCTAssertEqual(try ShotRepository.count(forHole: first.id), 4)

        XCTAssertEqual(controller.currentHole?.holeNumber, 2)
        XCTAssertTrue(controller.currentHoleShots.isEmpty)
    }

    func testExcludedShotsStayOutOfRoundReads() throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let round = try XCTUnwrap(controller.currentRound)
        let id = try controller.ingestAutoShot(at: nil, accuracy: nil, club: nil, timestamp: Date())
        try ShotRepository.setExcluded([id], at: Date())
        XCTAssertTrue(try ShotRepository.shotsForRound(round.id).isEmpty)
    }
}
