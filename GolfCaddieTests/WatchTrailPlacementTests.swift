import CoreLocation
@testable import GolfCaddie
import GRDB
import XCTest

/// B38 after-hole placement: pins snap to the preferred trail, and Path B reads
/// the WATCH's walk instead of a phone sitting in the cart.
@MainActor
final class WatchTrailPlacementTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let t0 = Date().addingTimeInterval(-3_600)
    // 0.0001 deg of latitude is about 11 m.
    private let cartLat = 33.0000
    private let teeLat = 33.0010
    private let ballLat = 33.0030
    private let lon = -117.0

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDown() {
        TestDatabase.restore()
        queue = nil
    }

    private func trace(_ round: UUID, _ offset: Double, lat: Double, _ source: TracePointSource?) throws {
        try TracePointRepository.insert(TracePoint(
            id: UUID(), roundID: round, timestamp: t0.addingTimeInterval(offset),
            latitude: lat, longitude: lon, accuracy: 4, source: source))
    }

    /// The phone sits at the cart for the whole hole (one long dwell at the cart).
    private func seedCartPhoneTrail(_ round: UUID, from start: Int = 35, seconds: Int = 330) throws {
        for s in stride(from: start, to: start + seconds, by: 5) { try trace(round, Double(s), lat: cartLat, nil) }
    }

    /// The watch: dwell at the tee, walk, dwell at the ball. Returned as a batch.
    private func watchWalk(tee: Double = 30, ball: Double = 330) -> WatchTrailBatch {
        var fixes: [WatchFix] = []
        func add(_ offset: Double, _ lat: Double) {
            fixes.append(WatchFix(latitude: lat, longitude: lon, horizontalAccuracy: 4,
                                  timestamp: t0.timeIntervalSince1970 + offset))
        }
        for s in stride(from: tee, through: tee + 40, by: 4) { add(s, teeLat) } // tee dwell
        for (i, s) in stride(from: tee + 50, to: ball, by: 10).enumerated() {
            add(s, teeLat + Double(i + 1) * 0.0002) // walking, ~22 m per step
        }
        for s in stride(from: ball, through: ball + 40, by: 4) { add(s, ballLat) } // ball dwell
        return WatchTrailBatch(batchId: UUID(), fixes: fixes)
    }

    private func meters(_ lat: Double, _ to: Double) -> Double {
        Distance.meters(from: .init(latitude: lat, longitude: lon), to: .init(latitude: to, longitude: lon))
    }

    // MARK: snap (pure)

    private func tp(_ lat: Double) -> TracePoint {
        TracePoint(id: UUID(), roundID: UUID(), timestamp: t0, latitude: lat, longitude: lon, accuracy: 4)
    }

    func testATapWithin15MetersSnapsToTheNearestTrailPoint() {
        let trail = [tp(33.0000), tp(33.0010)]
        let tap = CLLocationCoordinate2D(latitude: 33.00105, longitude: lon) // ~5.5 m from the 2nd point
        let result = TrailSnap.snap(tap, to: trail)
        XCTAssertTrue(result.snapped)
        XCTAssertEqual(result.coordinate.latitude, 33.0010, accuracy: 1e-9)
    }

    func testATapBeyond15MetersStaysWhereItWasTapped() {
        let tap = CLLocationCoordinate2D(latitude: 33.0005, longitude: lon) // ~55 m from both
        let result = TrailSnap.snap(tap, to: [tp(33.0000), tp(33.0010)])
        XCTAssertFalse(result.snapped)
        XCTAssertEqual(result.coordinate.latitude, 33.0005, accuracy: 1e-9)
    }

    func testSnapRadiusIsFifteenMetersAndAnEmptyTrailNeverSnaps() {
        XCTAssertEqual(TrailSnap.radiusMeters, 15)
        let tap = CLLocationCoordinate2D(latitude: 33.0, longitude: lon)
        XCTAssertFalse(TrailSnap.snap(tap, to: []).snapped)
    }

    // MARK: DB-backed pinning

    private func seedHoleWithTrail(shots: Int = 2) throws -> (Round, Hole, [Shot]) {
        let round = try TestDatabase.seedRound(startedAt: t0.addingTimeInterval(-60))
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let seeded = try (1...shots).map {
            try TestDatabase.seedShot(holeID: hole.id, sequence: $0, hadGPS: false, timestamp: t0.addingTimeInterval(400 + Double($0) * 20))
        }
        return (round, hole, seeded)
    }

    func testPinningNearTheWatchTrailSnapsAndTagsTrack() throws {
        let (round, _, shots) = try seedHoleWithTrail()
        try seedCartPhoneTrail(round.id)
        _ = try TraceIngest.ingest(watchWalk())
        let tap = CLLocationCoordinate2D(latitude: ballLat + 0.00003, longitude: lon) // ~3 m off the ball dwell
        let pinned = ShotPlacement.pinned(shots[0], at: tap)
        XCTAssertEqual(pinned.locationSource, .track)
        XCTAssertEqual(pinned.latitude ?? 0, ballLat, accuracy: 1e-6)
        XCTAssertTrue(pinned.hadGPS)
        XCTAssertNil(pinned.gpsAccuracy)
        XCTAssertNil(pinned.locationDisagreementMeters)
    }

    func testPinningAwayFromTheTrailIsManual() throws {
        let (round, _, shots) = try seedHoleWithTrail()
        try seedCartPhoneTrail(round.id)
        _ = try TraceIngest.ingest(watchWalk())
        let tap = CLLocationCoordinate2D(latitude: ballLat, longitude: lon + 0.001) // ~93 m east
        let pinned = ShotPlacement.pinned(shots[0], at: tap)
        XCTAssertEqual(pinned.locationSource, .manual)
        XCTAssertEqual(pinned.longitude ?? 0, lon + 0.001, accuracy: 1e-9)
    }

    func testPinningNearTheCartDoesNotSnapToThePhoneTrailWhereTheWatchWalked() throws {
        let (round, _, shots) = try seedHoleWithTrail()
        try seedCartPhoneTrail(round.id, from: 35, seconds: 330) // only while the watch was walking
        _ = try TraceIngest.ingest(watchWalk())
        // Right at the cart: the phone's points there are inside the watch span, so ignored.
        let pinned = ShotPlacement.pinned(shots[0], at: CLLocationCoordinate2D(latitude: cartLat, longitude: lon))
        XCTAssertEqual(pinned.locationSource, .manual)
    }

    func testPinningWithoutAnyTrailIsManual() throws {
        let (_, _, shots) = try seedHoleWithTrail()
        let pinned = ShotPlacement.pinned(shots[0], at: .init(latitude: 33.0, longitude: lon))
        XCTAssertEqual(pinned.locationSource, .manual)
    }

    func testMissingShotSheetInsertSnapsToTheTrail() throws {
        let (controller, round, _) = try activeControllerWithPlacedHole()
        controller.phoneFixProvider = { nil }
        try trace(round.id, 100, lat: 33.0010, .watch)
        try trace(round.id, 104, lat: 33.0010, .watch)
        try controller.insertMissingShot(at: .init(latitude: 33.00103, longitude: lon), club: nil)
        XCTAssertEqual(controller.currentHoleShots.last?.locationSource, .track)
        XCTAssertEqual(try XCTUnwrap(controller.currentHoleShots.last?.latitude), 33.0010, accuracy: 1e-9)
        try controller.insertMissingShot(at: .init(latitude: 33.01, longitude: lon), club: nil)
        XCTAssertEqual(controller.currentHoleShots.last?.locationSource, .manual)
    }

    // MARK: Path B on the watch trail

    func testStopsComeFromTheWatchWalkNotTheCartPhone() throws {
        let (round, hole, _) = try seedHoleWithTrail()
        try seedCartPhoneTrail(round.id)
        var holeRow = hole
        holeRow.confirmedAt = t0.addingTimeInterval(500)
        try HoleRepository.update(holeRow)

        let cartOnly = try TrackSegmenter.stops(forHole: holeRow, in: round)
        XCTAssertEqual(cartOnly.count, 1, "phone alone sees one long dwell at the cart")
        XCTAssertEqual(cartOnly[0].latitude, cartLat, accuracy: 1e-6)

        _ = try TraceIngest.ingest(watchWalk())
        let stops = try TrackSegmenter.stops(forHole: holeRow, in: round)
        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops[0].latitude, teeLat, accuracy: 1e-5)
        XCTAssertEqual(stops[1].latitude, ballLat, accuracy: 1e-5)
    }

    private func activeControllerWithPlacedHole() throws -> (RoundController, Round, Hole) {
        let round = try TestDatabase.seedRound(startedAt: t0.addingTimeInterval(-60))
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        for i in 1...2 { try TestDatabase.seedShot(holeID: hole.id, sequence: i, hadGPS: false) }
        let controller = RoundController(location: LocationManager())
        try controller.restoreActiveRound()
        return (controller, round, hole)
    }

    func testPlaceFromTrackLandsOnTheWatchWalkWhenThePhoneSatInTheCart() throws {
        let (controller, round, hole) = try activeControllerWithPlacedHole()
        try seedCartPhoneTrail(round.id)
        _ = try TraceIngest.ingest(watchWalk())
        controller.placeCurrentHoleFromTrack()
        let shots = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(shots.count, 2)
        XCTAssertTrue(shots.allSatisfy { $0.locationSource == .track })
        XCTAssertLessThan(meters(shots[0].latitude ?? 0, teeLat), 15)
        XCTAssertGreaterThan(meters(shots[0].latitude ?? 0, cartLat), 50, "not at the cart")
    }

    // MARK: re-run when late data arrives

    func testLateWatchBatchesReplaceTheCartPlacementForSystemPlacedStrokes() throws {
        let (controller, round, hole) = try activeControllerWithPlacedHole()
        try seedCartPhoneTrail(round.id)
        controller.placeCurrentHoleFromTrack() // user opened review away from the cart: cart path only
        let before = try ShotRepository.shotsForHole(hole.id)
        XCTAssertTrue(before.allSatisfy { meters($0.latitude ?? 0, cartLat) < 15 })

        let result = try TraceIngest.ingest(watchWalk())
        controller.watchTrailArrived(inRounds: result.roundIDs)

        let after = try ShotRepository.shotsForHole(hole.id)
        XCTAssertTrue(after.allSatisfy { $0.locationSource == .track })
        XCTAssertLessThan(meters(after[0].latitude ?? 0, teeLat), 15)
        XCTAssertEqual(controller.currentHoleShots.map(\.latitude), after.map(\.latitude), "live list refreshed")
    }

    func testHandPlacedStrokesAreNeverMovedByLateData() throws {
        let (controller, round, hole) = try activeControllerWithPlacedHole()
        try seedCartPhoneTrail(round.id)
        controller.placeCurrentHoleFromTrack()
        var shots = try ShotRepository.shotsForHole(hole.id)
        shots[0].latitude = 33.0100
        shots[0].locationSource = .manual
        try ShotRepository.update(shots[0])

        let result = try TraceIngest.ingest(watchWalk())
        controller.watchTrailArrived(inRounds: result.roundIDs)

        let after = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(after[0].latitude ?? 0, 33.0100, accuracy: 1e-9)
        XCTAssertEqual(after[1].latitude, shots[1].latitude, "the whole hole is left alone once any pin is hand-placed")
    }

    func testWatchFixLocatedStrokesAreNeverMovedByLateData() throws {
        let (controller, round, hole) = try activeControllerWithPlacedHole()
        try seedCartPhoneTrail(round.id)
        controller.placeCurrentHoleFromTrack()
        var shots = try ShotRepository.shotsForHole(hole.id)
        shots[1].locationSource = .watch
        try ShotRepository.update(shots[1])
        let result = try TraceIngest.ingest(watchWalk())
        controller.watchTrailArrived(inRounds: result.roundIDs)
        let after = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(after.map(\.latitude), shots.map(\.latitude))
    }

    func testRerunIsIdempotentAndIgnoresHolesThatWereNeverPlaced() throws {
        let (controller, round, hole) = try activeControllerWithPlacedHole()
        try seedCartPhoneTrail(round.id)
        // Never placed: the strokes are plain phone strokes, not system-placed.
        let result = try TraceIngest.ingest(watchWalk())
        controller.watchTrailArrived(inRounds: result.roundIDs)
        XCTAssertTrue(try ShotRepository.shotsForHole(hole.id).allSatisfy { $0.latitude == nil })

        controller.placeCurrentHoleFromTrack()
        let once = try ShotRepository.shotsForHole(hole.id).map(\.latitude)
        controller.watchTrailArrived(inRounds: [round.id])
        controller.watchTrailArrived(inRounds: [round.id])
        XCTAssertEqual(try ShotRepository.shotsForHole(hole.id).map(\.latitude), once)
    }
}
