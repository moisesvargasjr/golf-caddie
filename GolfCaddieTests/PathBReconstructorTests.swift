import CoreLocation
import XCTest
@testable import GolfCaddie

/// B6 Path-B (phone-only) reconstruction — split estimation + dwell placement.
/// Real-data accuracy was validated in the R1 Python prototype against Emerald
/// Isle; these pin down the ported algorithm's behavior deterministically.
final class PathBReconstructorTests: XCTestCase {
    let tee = CLLocationCoordinate2D(latitude: 33.2000, longitude: -117.3327)
    let green = CLLocationCoordinate2D(latitude: 33.2132, longitude: -117.3327) // ~1470 m north of tee
    let cfg = PathBConfig() // green 25 m, merge 20 m

    // 1° lat ≈ 111_320 m; build a point `meters` north of the green.
    private func northOfGreen(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: green.latitude + meters / 111_320.0, longitude: green.longitude)
    }
    /// A dwell at `coord` lasting `dwell` seconds, arriving at t0 = base + `order`*60 s.
    private func stop(_ coord: CLLocationCoordinate2D, dwell: TimeInterval, order: Int) -> TrackStop {
        let arrival = Date(timeIntervalSince1970: 1_000_000 + Double(order) * 60)
        return TrackStop(latitude: coord.latitude, longitude: coord.longitude,
                         arrival: arrival, departure: arrival.addingTimeInterval(dwell),
                         sampleCount: Int(dwell), prominence: min(1.0, dwell / 60))
    }

    // MARK: - Split estimation

    func testSplitFromOffGreenDwells() {
        // 3 off-green dwells, score 5 → 3 full + 2 putts.
        let stops = [
            stop(northOfGreen(400), dwell: 20, order: 1),
            stop(northOfGreen(200), dwell: 20, order: 2),
            stop(northOfGreen(60),  dwell: 20, order: 3),
        ]
        let r = PathBReconstructor.reconstruct(score: 5, stops: stops, tee: tee, green: green, config: cfg)
        XCTAssertEqual(r.estimatedFullCount, 3)
        XCTAssertEqual(r.fullShotCount, 3)
        XCTAssertEqual(r.puttCount, 2)
        XCTAssertEqual(r.shots.count, 5)
        XCTAssertEqual(r.shots.map(\.sequenceNumber), [1, 2, 3, 4, 5])
    }

    func testEstFullCappedByScore() {
        // 5 off-green dwells but the golfer carded a 3 → only 3 full, 0 putts.
        let stops = (1...5).map { stop(northOfGreen(Double(600 - $0 * 100)), dwell: 20, order: $0) }
        let r = PathBReconstructor.reconstruct(score: 3, stops: stops, tee: tee, green: green, config: cfg)
        XCTAssertEqual(r.estimatedFullCount, 3)
        XCTAssertEqual(r.puttCount, 0)
        XCTAssertEqual(r.shots.count, 3)
    }

    func testOnGreenDwellsAreNotFullCandidates() {
        // A dwell 10 m from the green (within radius) shouldn't count as a full shot.
        let stops = [
            stop(northOfGreen(300), dwell: 20, order: 1), // off green
            stop(northOfGreen(10),  dwell: 30, order: 2), // on green (longer, but ignored)
        ]
        let r = PathBReconstructor.reconstruct(score: 4, stops: stops, tee: tee, green: green, config: cfg)
        XCTAssertEqual(r.estimatedFullCount, 1)
        XCTAssertEqual(r.puttCount, 3)
    }

    // MARK: - Placement

    func testFirstPinSnapsToTee() {
        let stops = [stop(northOfGreen(300), dwell: 20, order: 1),
                     stop(northOfGreen(120), dwell: 20, order: 2)]
        let r = PathBReconstructor.reconstruct(score: 3, stops: stops, tee: tee, green: green, config: cfg)
        XCTAssertEqual(r.shots.first?.latitude ?? 0, tee.latitude, accuracy: 1e-9)
        XCTAssertEqual(r.shots.first?.longitude ?? 0, tee.longitude, accuracy: 1e-9)
        XCTAssertTrue(r.shots.first?.placedFromDwell ?? false)
    }

    func testPuttsClusterOnGreen() {
        let stops = [stop(northOfGreen(300), dwell: 20, order: 1)]
        let r = PathBReconstructor.reconstruct(score: 3, stops: stops, tee: tee, green: green, config: cfg)
        let putts = r.shots.filter(\.isPutt)
        XCTAssertEqual(putts.count, 2)
        for p in putts {
            XCTAssertEqual(p.latitude, green.latitude, accuracy: 1e-9)
            XCTAssertEqual(p.longitude, green.longitude, accuracy: 1e-9)
        }
    }

    func testNoTrackPutsDriveOnTeeRestPutts() {
        // No dwells at all: 1 full (on the tee) + (score-1) putts on the green.
        let r = PathBReconstructor.reconstruct(score: 4, stops: [], tee: tee, green: green, config: cfg)
        XCTAssertEqual(r.estimatedFullCount, 1)
        XCTAssertEqual(r.shots.count, 4)
        XCTAssertFalse(r.shots[0].isPutt)
        XCTAssertEqual(r.shots[0].latitude, tee.latitude, accuracy: 1e-9)
        XCTAssertEqual(r.shots.filter(\.isPutt).count, 3)
    }

    func testChosenReturnedInTimeOrder() {
        // Strongest-by-dwell selection, but the pins must come back in play order.
        let stops = [
            stop(northOfGreen(400), dwell: 12, order: 1),
            stop(northOfGreen(250), dwell: 40, order: 2),
            stop(northOfGreen(90),  dwell: 25, order: 3),
        ]
        let r = PathBReconstructor.reconstruct(score: 5, stops: stops, tee: tee, green: green, config: cfg)
        // 3 fulls, shot 1 snapped to tee; shots 2 & 3 should be the order-2 then
        // order-3 dwells (north→south, descending latitude as we approach green).
        XCTAssertGreaterThan(r.shots[1].latitude, r.shots[2].latitude)
    }

    // MARK: - Merge

    func testMergeCombinesNearbyDwells() {
        let a = stop(northOfGreen(300), dwell: 15, order: 1)
        let b = stop(northOfGreen(295), dwell: 15, order: 2) // ~5 m away → merge
        let merged = PathBReconstructor.mergeStops([a, b], within: cfg.mergeRadiusMeters)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].dwellSeconds, 30, accuracy: 0.5) // summed dwell
    }

    func testMergeKeepsDistantDwellsSeparate() {
        let a = stop(northOfGreen(400), dwell: 15, order: 1)
        let b = stop(northOfGreen(200), dwell: 15, order: 2) // ~200 m apart → distinct
        XCTAssertEqual(PathBReconstructor.mergeStops([a, b], within: cfg.mergeRadiusMeters).count, 2)
    }

    // MARK: - Degenerate

    func testZeroScoreIsEmpty() {
        let r = PathBReconstructor.reconstruct(score: 0, stops: [], tee: tee, green: green, config: cfg)
        XCTAssertTrue(r.shots.isEmpty)
    }
}
