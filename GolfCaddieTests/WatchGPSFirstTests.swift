import CoreLocation
@testable import GolfCaddie
import GRDB
import XCTest

/// B35 "watch GPS first": every phone-side location read prefers the watch's
/// fix when usable, and each shot records which device it came from and how far
/// apart the two fixes were.
@MainActor
final class WatchGPSFirstTests: XCTestCase {
    private var queue: DatabaseQueue!

    // ~100 m apart: 0.0009 deg of latitude.
    private let cart = GeoFix(latitude: 33.0000, longitude: -117.0, horizontalAccuracy: 3, timestamp: 0)
    private let golfer = CLLocationCoordinate2D(latitude: 33.0009, longitude: -117.0)

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
        WatchFixStore.shared.reset()
    }

    override func tearDown() {
        WatchFixStore.shared.reset()
        TestDatabase.restore()
        queue = nil
    }

    private func freshWatchFix(accuracy: Double = 6, age: TimeInterval = 0) -> WatchFix {
        WatchFix(latitude: golfer.latitude, longitude: golfer.longitude, horizontalAccuracy: accuracy,
                 timestamp: Date().timeIntervalSince1970 - age)
    }

    private func controller(watch: WatchFix?, phone: GeoFix?) throws -> RoundController {
        let controller = RoundController(location: LocationManager())
        controller.watchFixProvider = { watch }
        controller.phoneFixProvider = { phone }
        try controller.startRound()
        return controller
    }

    // MARK: - WatchFixStore

    func testStoreKeepsOnlyTheNewestFix() {
        let store = WatchFixStore.shared
        store.update(WatchFix(latitude: 1, longitude: 1, horizontalAccuracy: 5, timestamp: 100))
        store.update(WatchFix(latitude: 2, longitude: 2, horizontalAccuracy: 5, timestamp: 90)) // out of order
        XCTAssertEqual(store.latest?.latitude, 1)
        store.update(WatchFix(latitude: 3, longitude: 3, horizontalAccuracy: 5, timestamp: 110))
        XCTAssertEqual(store.latest?.latitude, 3)
        store.update(nil)
        XCTAssertEqual(store.latest?.latitude, 3)
    }

    func testFixMessageFeedsTheStoreEvenBeforeAControllerIsAttached() {
        let coordinator = LiveShotCoordinator(steps: AlwaysWalked())
        let fix = freshWatchFix()
        coordinator.ingest(.fix(fix))
        XCTAssertEqual(WatchFixStore.shared.latest, fix)
    }

    // MARK: - Phone MARK / glasses

    func testPhoneMarkUsesTheWatchFixAndRecordsDisagreement() async throws {
        let controller = try controller(watch: freshWatchFix(), phone: cart)
        try await controller.markShot()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(try XCTUnwrap(shot.latitude), golfer.latitude, accuracy: 1e-7)
        XCTAssertEqual(shot.locationSource, .watch)
        XCTAssertEqual(try XCTUnwrap(shot.locationDisagreementMeters), 100, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(shot.gpsAccuracy), 6, accuracy: 0.01)
        XCTAssertTrue(shot.hadGPS)
    }

    func testPhoneMarkFallsBackToThePhoneWhenTheWatchFixIsStale() async throws {
        let controller = try controller(watch: freshWatchFix(age: 30), phone: cart)
        try await controller.markShot()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(try XCTUnwrap(shot.latitude), cart.latitude, accuracy: 1e-7)
        XCTAssertEqual(shot.locationSource, .phone)
        XCTAssertNil(shot.locationDisagreementMeters)
    }

    func testPhoneMarkWithNoFixAtAllLogsWithoutASource() async throws {
        let controller = try controller(watch: nil, phone: nil)
        try await controller.markShot()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertFalse(shot.hadGPS)
        XCTAssertNil(shot.locationSource)
        XCTAssertNil(shot.locationDisagreementMeters)
    }

    func testGlassesShotUsesTheWatchFix() throws {
        let controller = try controller(watch: freshWatchFix(), phone: cart)
        try controller.logShotFromGlasses()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(try XCTUnwrap(shot.latitude), golfer.latitude, accuracy: 1e-7)
        XCTAssertEqual(shot.locationSource, .watch)
        XCTAssertEqual(try XCTUnwrap(shot.locationDisagreementMeters), 100, accuracy: 2)
    }

    func testGlassesShotPhoneOnlyIsTaggedPhone() throws {
        let controller = try controller(watch: nil, phone: cart)
        try controller.logShotFromGlasses()
        XCTAssertEqual(controller.currentHoleShots.last?.locationSource, .phone)
    }

    // MARK: - Watch taps

    func testLiveWatchTapWithoutAnAttachedFixUsesTheStreamedWatchFix() throws {
        let controller = try controller(watch: freshWatchFix(), phone: cart)
        try controller.addShotFromWatch()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(try XCTUnwrap(shot.latitude), golfer.latitude, accuracy: 1e-7)
        XCTAssertEqual(shot.locationSource, .watch)
    }

    func testWatchPuttTapRecordsSourceAndDisagreement() throws {
        let controller = try controller(watch: nil, phone: cart)
        let coordinator = LiveShotCoordinator(steps: AlwaysWalked())
        coordinator.attach(controller: controller, location: LocationManager())
        let now = Date()
        let fix = WatchFix(latitude: golfer.latitude, longitude: golfer.longitude, horizontalAccuracy: 4,
                           timestamp: now.timeIntervalSince1970)
        coordinator.ingest(.command(.puttPlusOne, sentAt: now, fix: fix))
        let putt = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(putt.locationSource, .watch)
        XCTAssertEqual(try XCTUnwrap(putt.locationDisagreementMeters), 100, accuracy: 2)
    }

    func testWatchTapWithoutAFixFallsBackToThePhone() throws {
        let controller = try controller(watch: nil, phone: cart)
        let coordinator = LiveShotCoordinator(steps: AlwaysWalked())
        coordinator.attach(controller: controller, location: LocationManager())
        coordinator.ingest(.command(.addShot(clubShortName: nil), sentAt: Date()))
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.locationSource, .phone)
        XCTAssertEqual(try XCTUnwrap(shot.latitude), cart.latitude, accuracy: 1e-7)
    }

    func testDetectedSwingRecordsWatchSourceAndBreadcrumbDisagreement() async throws {
        let controller = try controller(watch: nil, phone: nil)
        let coordinator = LiveShotCoordinator(steps: AlwaysWalked(), debounceInterval: 0.05)
        coordinator.attach(controller: controller, location: LocationManager())
        let t = Date().addingTimeInterval(-600)
        let round = try XCTUnwrap(controller.currentRound)
        try TracePointRepository.insert(TracePoint(
            id: UUID(), roundID: round.id, timestamp: t,
            latitude: cart.latitude, longitude: cart.longitude, accuracy: 5))
        let fix = WatchFix(latitude: golfer.latitude, longitude: golfer.longitude, horizontalAccuracy: 5,
                           timestamp: t.timeIntervalSince1970)
        coordinator.ingest(.swing(SwingEvent(
            id: UUID(), watchWallClock: t.timeIntervalSince1970, watchUptime: 0, club: "7i",
            confidence: 1, source: .auto, impactPeakG: 12, arcGyro: 6, fix: fix)))
        try await Task.sleep(nanoseconds: 300_000_000)
        await coordinator.waitUntilIdle()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.locationSource, .watch)
        XCTAssertEqual(try XCTUnwrap(shot.locationDisagreementMeters), 100, accuracy: 2)
    }

    func testDetectedSwingWithoutWatchFixIsTaggedPhone() async throws {
        let controller = try controller(watch: nil, phone: nil)
        let coordinator = LiveShotCoordinator(steps: AlwaysWalked(), debounceInterval: 0.05)
        coordinator.attach(controller: controller, location: LocationManager())
        let t = Date().addingTimeInterval(-600)
        let round = try XCTUnwrap(controller.currentRound)
        try TracePointRepository.insert(TracePoint(
            id: UUID(), roundID: round.id, timestamp: t,
            latitude: cart.latitude, longitude: cart.longitude, accuracy: 5))
        coordinator.ingest(.swing(SwingEvent(
            id: UUID(), watchWallClock: t.timeIntervalSince1970, watchUptime: 0, club: "7i",
            confidence: 1, source: .auto, impactPeakG: 12, arcGyro: 6)))
        try await Task.sleep(nanoseconds: 300_000_000)
        await coordinator.waitUntilIdle()
        XCTAssertEqual(controller.currentHoleShots.last?.locationSource, .phone)
    }

    // MARK: - Manual + track provenance

    func testMapTapInsertIsTaggedManual() throws {
        let controller = try controller(watch: nil, phone: nil)
        try controller.insertMissingShot(at: golfer, club: nil)
        let stored = try XCTUnwrap(try ShotRepository.shotsForHole(XCTUnwrap(controller.currentHole).id).last)
        XCTAssertEqual(stored.locationSource, .manual)
        XCTAssertNil(stored.locationDisagreementMeters)
    }

    func testPlacingAHoleFromTheTrackTagsShotsTrack() async throws {
        let controller = try controller(watch: nil, phone: nil)
        try await controller.addCasualStroke()
        controller.placeCurrentHoleFromTrack()
        let hole = try XCTUnwrap(controller.currentHole)
        let shots = try ShotRepository.shotsForHole(hole.id)
        XCTAssertFalse(shots.isEmpty)
        XCTAssertTrue(shots.allSatisfy { $0.locationSource == .track })
        XCTAssertTrue(shots.allSatisfy { $0.locationDisagreementMeters == nil })
    }

    // MARK: - Yardage

    private func seedGreen(at lat: Double) throws -> String {
        let courseId = "gps-first-course"
        try TestDatabase.seedCuratedCourse(
            id: courseId,
            holes: [CuratedHole(number: 1, par: 4, yards: nil, strokeIndex: nil, teeAnchor: nil,
                                greenAnchor: GeoPoint(lat: lat, lng: -117.0))])
        return courseId
    }

    func testYardageUsesTheWatchFixEvenWhenThePhoneIsMoreAccurate() throws {
        let courseId = try seedGreen(at: 33.0018) // 200 m north of the cart, 100 m north of the golfer
        let yards = GlassesStateMapper.yardsToGreen(
            watchFix: freshWatchFix(accuracy: 12), phone: cart, courseId: courseId, holeNumber: 1, at: Date())
        XCTAssertEqual(try XCTUnwrap(yards), 109, accuracy: 3) // 100 m
    }

    func testYardageFallsBackToThePhoneWhenTheWatchFixIsStale() throws {
        let courseId = try seedGreen(at: 33.0018)
        let yards = GlassesStateMapper.yardsToGreen(
            watchFix: freshWatchFix(age: 60), phone: cart, courseId: courseId, holeNumber: 1, at: Date())
        XCTAssertEqual(try XCTUnwrap(yards), 219, accuracy: 3) // 200 m
    }

    func testYardageNilWithNoUsableFix() throws {
        let courseId = try seedGreen(at: 33.0018)
        XCTAssertNil(GlassesStateMapper.yardsToGreen(
            watchFix: nil, phone: nil, courseId: courseId, holeNumber: 1, at: Date()))
    }

    func testGlassesSnapshotDistanceUsesTheWatchFix() throws {
        let courseId = try seedGreen(at: 33.0018)
        let round = try TestDatabase.seedRound(curatedCourseId: courseId)
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let inputs = GlassesStateInputs(
            isActive: true, currentRound: round, currentHole: hole, currentHoleShots: [], currentClub: nil,
            curatedCourseId: courseId,
            latestLocation: CLLocation(coordinate: cart.coordinate, altitude: 0, horizontalAccuracy: 3,
                                       verticalAccuracy: 3, timestamp: Date()),
            lastLocationReceivedAt: Date(), locationUnavailable: false, batteryPercent: nil,
            watchFix: freshWatchFix())
        let yards = GlassesStateMapper.snapshot(inputs: inputs).hole?.distanceToGreenYards
        XCTAssertEqual(try XCTUnwrap(yards), 109, accuracy: 3)
    }

    func testWatchStatePublisherDistanceUsesTheWatchFix() throws {
        let courseId = try seedGreen(at: 33.0018)
        let round = try TestDatabase.seedRound(curatedCourseId: courseId)
        try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let controller = RoundController(location: LocationManager())
        try controller.restoreActiveRound()
        let publisher = WatchStatePublisher()
        publisher.bind(controller: controller, location: LocationManager())
        publisher.watchFixProvider = { [self] in freshWatchFix() }
        XCTAssertEqual(try XCTUnwrap(publisher.build().distanceToGreenYards), 109, accuracy: 3)
    }
}

private struct AlwaysWalked: StepCounting {
    func steps(from: Date, to: Date) async -> Int { .max }
}
