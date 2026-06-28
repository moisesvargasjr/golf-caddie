import GRDB
import XCTest
@testable import GolfCaddie

/// B5 — per-hole track segmentation + stop/dwell detection.
final class TrackSegmenterTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let config = StopDetectionConfig(minDwellSeconds: 8, radiusMeters: 5)

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    private func point(_ offset: TimeInterval, lat: Double, lng: Double = -105.0) -> TracePoint {
        TracePoint(id: UUID(), roundID: UUID(), timestamp: t0.addingTimeInterval(offset),
                   latitude: lat, longitude: lng, accuracy: 5)
    }

    // MARK: - detectStops (pure)

    func testTwoDwellsWithAWalkBetweenYieldTwoStops() {
        // Stand at A (lat 40.0000) for 12 s, walk away (points >5 m apart), then
        // stand at B (lat 40.0010 ≈ 111 m away) for 12 s.
        let pts = [
            point(0, lat: 40.0000), point(4, lat: 40.0000), point(8, lat: 40.0000), point(12, lat: 40.0000),
            point(20, lat: 40.0003), point(30, lat: 40.0006), // walking ≈ 33 m steps
            point(40, lat: 40.0010), point(44, lat: 40.0010), point(48, lat: 40.0010), point(52, lat: 40.0010),
        ]
        let stops = TrackSegmenter.detectStops(in: pts, config: config)
        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops[0].latitude, 40.0000, accuracy: 1e-6)
        XCTAssertEqual(stops[0].arrival, t0)
        XCTAssertEqual(stops[0].departure, t0.addingTimeInterval(12))
        XCTAssertEqual(stops[0].sampleCount, 4)
        XCTAssertEqual(stops[1].latitude, 40.0010, accuracy: 1e-6)
        // Returned in track (arrival) order.
        XCTAssertLessThan(stops[0].arrival, stops[1].arrival)
        // Prominence is monotonic in dwell (12 s / 60 s saturation).
        XCTAssertEqual(stops[0].prominence, 0.2, accuracy: 1e-9)
    }

    func testPureWalkHasNoStops() {
        // Every point > radius from the previous → no dwell ever forms.
        let pts = (0..<8).map { point(Double($0) * 10, lat: 40.0 + Double($0) * 0.0003) }
        XCTAssertTrue(TrackSegmenter.detectStops(in: pts, config: config).isEmpty)
    }

    func testDwellShorterThanThresholdIsNotAStop() {
        // Stood still, but only 6 s (< 8 s minimum).
        let pts = [point(0, lat: 40.0), point(3, lat: 40.0), point(6, lat: 40.0)]
        XCTAssertTrue(TrackSegmenter.detectStops(in: pts, config: config).isEmpty)
    }

    func testSingleDwellCentroidAndDwell() {
        let pts = [point(0, lat: 40.0), point(5, lat: 40.00001), point(10, lat: 40.0)]
        let stops = TrackSegmenter.detectStops(in: pts, config: config)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].sampleCount, 3)
        XCTAssertEqual(stops[0].dwellSeconds, 10)
        XCTAssertEqual(stops[0].latitude, 40.0000033, accuracy: 1e-6) // centroid of jitter
    }

    func testFewerThanTwoPointsYieldsNoStops() {
        XCTAssertTrue(TrackSegmenter.detectStops(in: [], config: config).isEmpty)
        XCTAssertTrue(TrackSegmenter.detectStops(in: [point(0, lat: 40)], config: config).isEmpty)
    }

    // MARK: - Per-hole windowing (pure)

    func testWindowBoundsByConfirmTimes() {
        let rid = UUID()
        let h1 = Hole(id: UUID(), roundID: rid, holeNumber: 1, par: nil,
                      confirmedAt: t0.addingTimeInterval(100))
        let h2 = Hole(id: UUID(), roundID: rid, holeNumber: 2, par: nil, confirmedAt: nil) // active
        let holes = [h1, h2]
        let now = t0.addingTimeInterval(200)

        let w1 = TrackSegmenter.timeWindow(forHole: h1, roundStart: t0, holes: holes, now: now)
        XCTAssertEqual(w1?.lowerBound, t0, "hole 1 starts at round start")
        XCTAssertEqual(w1?.upperBound, t0.addingTimeInterval(100))

        let w2 = TrackSegmenter.timeWindow(forHole: h2, roundStart: t0, holes: holes, now: now)
        XCTAssertEqual(w2?.lowerBound, t0.addingTimeInterval(100), "hole 2 starts at hole 1's confirm")
        XCTAssertEqual(w2?.upperBound, now, "active hole runs to now")
    }

    func testWindowUsesPlayOrderNotHoleNumber() {
        let rid = UUID()
        // Played H9 first (confirmed t0+100), then H8 (confirmed t0+200) — an
        // out-of-order confirm. The old holeNumber bound mis-windowed H8 to start
        // at the round start, swallowing H9's track.
        let h9 = Hole(id: UUID(), roundID: rid, holeNumber: 9, par: nil,
                      confirmedAt: t0.addingTimeInterval(100))
        let h8 = Hole(id: UUID(), roundID: rid, holeNumber: 8, par: nil,
                      confirmedAt: t0.addingTimeInterval(200))
        let holes = [h8, h9]
        let now = t0.addingTimeInterval(300)

        let w9 = TrackSegmenter.timeWindow(forHole: h9, roundStart: t0, holes: holes, now: now)
        XCTAssertEqual(w9?.lowerBound, t0, "first hole played starts at round start")
        XCTAssertEqual(w9?.upperBound, t0.addingTimeInterval(100))

        let w8 = TrackSegmenter.timeWindow(forHole: h8, roundStart: t0, holes: holes, now: now)
        XCTAssertEqual(w8?.lowerBound, t0.addingTimeInterval(100),
                       "H8 was played after H9, so its window starts at H9's confirm")
        XCTAssertEqual(w8?.upperBound, t0.addingTimeInterval(200))
    }

    func testWindowDegenerateBoundsReturnNil() {
        let rid = UUID()
        // confirmedAt earlier than the round start (clock weirdness) → no window.
        let h = Hole(id: UUID(), roundID: rid, holeNumber: 1, par: nil,
                     confirmedAt: t0.addingTimeInterval(-10))
        XCTAssertNil(TrackSegmenter.timeWindow(forHole: h, roundStart: t0, holes: [h], now: t0))
    }

    // MARK: - DB-backed stops(forHole:in:) slices per hole

    func testStopsAreAttributedToTheCorrectHole() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        let h1 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1,
                                           confirmedAt: t0.addingTimeInterval(100))
        let h2 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 2) // active

        // A dwell inside hole 1's window [t0, t0+100] and another inside hole 2's
        // window [t0+100, now]. Each should be attributed only to its own hole.
        let dwellH1: [(TimeInterval, Double)] = [(10, 40.0), (14, 40.0), (18, 40.0), (22, 40.0)]
        let dwellH2: [(TimeInterval, Double)] = [(110, 41.0), (114, 41.0), (118, 41.0), (122, 41.0)]
        for (off, lat) in dwellH1 + dwellH2 {
            try TracePointRepository.insert(
                TracePoint(id: UUID(), roundID: round.id, timestamp: t0.addingTimeInterval(off),
                           latitude: lat, longitude: -105.0, accuracy: 5)
            )
        }

        let now = t0.addingTimeInterval(300)
        let s1 = try TrackSegmenter.stops(forHole: h1, in: round, config: config, now: now)
        XCTAssertEqual(s1.count, 1)
        XCTAssertEqual(try XCTUnwrap(s1.first).latitude, 40.0, accuracy: 1e-6)

        let s2 = try TrackSegmenter.stops(forHole: h2, in: round, config: config, now: now)
        XCTAssertEqual(s2.count, 1)
        XCTAssertEqual(try XCTUnwrap(s2.first).latitude, 41.0, accuracy: 1e-6)
    }
}
