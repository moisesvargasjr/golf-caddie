import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// Covers per-club averaging, sample-count threshold, GPS-skip behavior, and
/// the manual `invalidate()` path.
///
/// **Not covered:** the 60-second cache TTL. Asserting that would require
/// clock injection, which isn't worth its weight on a solo pre-monetization
/// product. The `invalidate()` test below proves the recompute path works;
/// real-world TTL drift is a non-issue for an in-play overlay.
@MainActor
final class ClubAveragesTests: XCTestCase {

    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
        ClubAverages.shared.invalidate()
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        ClubAverages.shared.invalidate()
        queue = nil
    }

    func test_returnsNil_belowMinSamples() throws {
        // One pair of shots → one distance sample → below default minSamples=3.
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 0.0, lng: 0.0, club: nil)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 2, lat: 0.001, lng: 0.0, club: .driver)

        XCTAssertNil(ClubAverages.shared.average(for: .driver))
    }

    func test_returnsRoundedAverage_atMinSamples() throws {
        // Three pairs of shots, each ~111 m apart in latitude → ~121 yards each.
        // ClubAverages attributes each pair's distance to the *next* shot's club.
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 0.000, lng: 0.0, club: nil)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 2, lat: 0.001, lng: 0.0, club: .driver)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 3, lat: 0.002, lng: 0.0, club: .driver)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 4, lat: 0.003, lng: 0.0, club: .driver)

        let avg = ClubAverages.shared.average(for: .driver)
        XCTAssertNotNil(avg)
        // Each ~0.001° lat ≈ 111 m ≈ 121 yards. Allow ±2 yards for rounding/haversine.
        XCTAssertEqual(avg!, 121, accuracy: 2)
    }

    func test_perClubSeparation() throws {
        // Driver and 7-iron interleaved. Driver pairs are ~0.002° lat (~243 yd);
        // 7-iron pairs are ~0.001° lat (~121 yd).
        let round = try TestDatabase.seedRound()
        let driverHole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: driverHole.id, sequence: 1, lat: 0.000, lng: 0, club: nil)
        try TestDatabase.seedShot(holeID: driverHole.id, sequence: 2, lat: 0.002, lng: 0, club: .driver)
        try TestDatabase.seedShot(holeID: driverHole.id, sequence: 3, lat: 0.004, lng: 0, club: .driver)
        try TestDatabase.seedShot(holeID: driverHole.id, sequence: 4, lat: 0.006, lng: 0, club: .driver)

        let ironHole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 2)
        try TestDatabase.seedShot(holeID: ironHole.id, sequence: 1, lat: 0.000, lng: 0, club: nil)
        try TestDatabase.seedShot(holeID: ironHole.id, sequence: 2, lat: 0.001, lng: 0, club: .sevenIron)
        try TestDatabase.seedShot(holeID: ironHole.id, sequence: 3, lat: 0.002, lng: 0, club: .sevenIron)
        try TestDatabase.seedShot(holeID: ironHole.id, sequence: 4, lat: 0.003, lng: 0, club: .sevenIron)

        let driver = ClubAverages.shared.average(for: .driver)
        let iron = ClubAverages.shared.average(for: .sevenIron)

        XCTAssertNotNil(driver)
        XCTAssertNotNil(iron)
        XCTAssertEqual(driver!, 243, accuracy: 3)
        XCTAssertEqual(iron!, 121, accuracy: 2)
    }

    func test_skipsShotsWithoutGPS() throws {
        // Plant 3 pairs but mark the middle "next" shot as hadGPS=false with nil
        // lat/lng. Recompute should skip that pair entirely.
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 0.000, lng: 0, club: nil)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 2, lat: 0.001, lng: 0, club: .driver)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 3, lat: nil, lng: nil, club: .driver, hadGPS: false)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 4, lat: 0.003, lng: 0, club: .driver)

        // Only 1 valid pair remains for driver (1→2). minSamples=3 → nil.
        XCTAssertNil(ClubAverages.shared.average(for: .driver))
        // With minSamples=1, the surviving pair averages out.
        XCTAssertNotNil(ClubAverages.shared.average(for: .driver, minSamples: 1))
    }

    func test_invalidate_forcesRecompute() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 0.000, lng: 0, club: nil)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 2, lat: 0.001, lng: 0, club: .driver)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 3, lat: 0.002, lng: 0, club: .driver)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 4, lat: 0.003, lng: 0, club: .driver)

        let first = ClubAverages.shared.average(for: .driver)
        XCTAssertNotNil(first)

        // Mutate the seeded data: add another pair at double the distance, which
        // would shift the average upward IF the cache is bypassed.
        try TestDatabase.seedShot(holeID: hole.id, sequence: 5, lat: 0.005, lng: 0, club: .driver)

        // Without invalidate, cache returns stale value.
        XCTAssertEqual(ClubAverages.shared.average(for: .driver), first)

        ClubAverages.shared.invalidate()
        let after = ClubAverages.shared.average(for: .driver)
        XCTAssertNotNil(after)
        XCTAssertGreaterThan(after!, first!)
    }
}
