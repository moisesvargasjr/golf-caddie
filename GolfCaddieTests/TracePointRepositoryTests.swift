import GRDB
import XCTest
@testable import GolfCaddie

final class TracePointRepositoryTests: XCTestCase {
    var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
    }

    private func seedPoint(roundID: UUID, secondsFromBase base: Date, _ offset: TimeInterval,
                           lat: Double, lng: Double) throws {
        try TracePointRepository.insert(
            TracePoint(id: UUID(), roundID: roundID, timestamp: base.addingTimeInterval(offset),
                       latitude: lat, longitude: lng, accuracy: 5)
        )
    }

    func testNearestPicksClosestInTime() throws {
        let round = try TestDatabase.seedRound()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try seedPoint(roundID: round.id, secondsFromBase: base, 0, lat: 1, lng: 1)
        try seedPoint(roundID: round.id, secondsFromBase: base, 10, lat: 2, lng: 2)
        try seedPoint(roundID: round.id, secondsFromBase: base, 20, lat: 3, lng: 3)

        // Target at +12 s → closest is the +10 s point (lat 2).
        let near = try TracePointRepository.nearest(toTimestamp: base.addingTimeInterval(12), inRound: round.id)
        XCTAssertEqual(near?.latitude, 2)

        // Exactly between +10 and +20 (i.e. +15): ties resolve to the earlier (before).
        let mid = try TracePointRepository.nearest(toTimestamp: base.addingTimeInterval(15), inRound: round.id)
        XCTAssertEqual(mid?.latitude, 2)
    }

    func testNearestHandlesOutOfRangeAndEmpty() throws {
        let round = try TestDatabase.seedRound()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // No points yet → nil (caller falls back to latestLocation).
        XCTAssertNil(try TracePointRepository.nearest(toTimestamp: base, inRound: round.id))

        try seedPoint(roundID: round.id, secondsFromBase: base, 100, lat: 9, lng: 9)
        // Target far before the only point → still returns it (after-only branch).
        let before = try TracePointRepository.nearest(toTimestamp: base, inRound: round.id)
        XCTAssertEqual(before?.latitude, 9)
        // Target far after → returns it (before-only branch).
        let after = try TracePointRepository.nearest(toTimestamp: base.addingTimeInterval(10_000), inRound: round.id)
        XCTAssertEqual(after?.latitude, 9)
    }

    func testNearestIsScopedToRound() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let roundA = try TestDatabase.seedRound()
        let roundB = try TestDatabase.seedRound()
        try seedPoint(roundID: roundA.id, secondsFromBase: base, 0, lat: 1, lng: 1)
        try seedPoint(roundID: roundB.id, secondsFromBase: base, 0, lat: 5, lng: 5)

        let near = try TracePointRepository.nearest(toTimestamp: base, inRound: roundB.id)
        XCTAssertEqual(near?.latitude, 5)
    }

    func testDeletingRoundCascadesBreadcrumbs() throws {
        let round = try TestDatabase.seedRound()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try seedPoint(roundID: round.id, secondsFromBase: base, 0, lat: 1, lng: 1)
        try seedPoint(roundID: round.id, secondsFromBase: base, 1, lat: 2, lng: 2)
        XCTAssertEqual(try TracePointRepository.count(forRound: round.id), 2)

        try RoundRepository.delete(round)
        XCTAssertEqual(try TracePointRepository.count(forRound: round.id), 0)
    }
}
