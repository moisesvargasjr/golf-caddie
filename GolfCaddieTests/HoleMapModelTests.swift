import CoreLocation
import MapKit
import XCTest
@testable import GolfCaddie

/// HoleMap's pure pieces: drop snapping (via ShotPlacement.pinned), course
/// regions, VoiceOver labels and the controller's command routing.
@MainActor
final class HoleMapModelTests: XCTestCase {
    private let lon = -117.0
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func shot(_ holeID: UUID = UUID()) -> Shot {
        Shot(id: UUID(), holeID: holeID, sequenceNumber: 1, timestamp: t0, latitude: 33.0, longitude: lon,
             gpsAccuracy: 5, hadGPS: true, club: nil, source: .watchAuto, notes: nil)
    }

    private func point(_ lat: Double, _ source: TracePointSource? = .watch) -> TracePoint {
        TracePoint(id: UUID(), roundID: UUID(), timestamp: t0, latitude: lat, longitude: lon, accuracy: 4,
                   source: source)
    }

    // MARK: Snap on drop

    func testADropWithin8MetersOfTheWalkSnapsOntoIt() {
        let snapper = HoleMapShotSnapper(trail: { _ in [self.point(33.0000), self.point(33.0010)] })
        let dropped = CLLocationCoordinate2D(latitude: 33.00105, longitude: lon) // ~5.5 m off
        let result = snapper.snappedCoordinate(for: shot(), droppedAt: dropped)
        XCTAssertEqual(result.latitude, 33.0010, accuracy: 1e-9)
        XCTAssertEqual(result.longitude, lon, accuracy: 1e-9)
    }

    func testADropFurtherThan8MetersStaysWhereItWasDropped() {
        let snapper = HoleMapShotSnapper(trail: { _ in [self.point(33.0010)] })
        let dropped = CLLocationCoordinate2D(latitude: 33.00112, longitude: lon) // ~13 m off
        let result = snapper.snappedCoordinate(for: shot(), droppedAt: dropped)
        XCTAssertEqual(result.latitude, 33.00112, accuracy: 1e-9)
    }

    func testWatchPointsWinOverPhonePoints() {
        let snapper = HoleMapShotSnapper(trail: { _ in
            [self.point(33.0000, nil), self.point(33.0010, .watch)]
        })
        let nearCart = CLLocationCoordinate2D(latitude: 33.00003, longitude: lon) // 3 m from a phone point
        XCTAssertEqual(snapper.snappedCoordinate(for: shot(), droppedAt: nearCart).latitude, 33.00003,
                       accuracy: 1e-9, "a phone point may be the cart, not the golfer's path")
    }

    func testTheSnapperAsksForTheShotsOwnHolesTrail() {
        let hole = UUID()
        var asked: UUID?
        let snapper = HoleMapShotSnapper(trail: { asked = $0; return [] })
        _ = snapper.snappedCoordinate(for: shot(hole), droppedAt: .init(latitude: 33, longitude: lon))
        XCTAssertEqual(asked, hole)
    }

    func testTheLiveSnapperReadsTheDatabaseAndNeverBlocksADrop() throws {
        let queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
        defer { TestDatabase.restore() }
        let dropped = CLLocationCoordinate2D(latitude: 33.0005, longitude: lon)
        let result = HoleMapShotSnapper.live.snappedCoordinate(for: shot(), droppedAt: dropped)
        XCTAssertEqual(result.latitude, dropped.latitude, accuracy: 1e-9, "unknown hole: no trail, no snap")
    }

    // MARK: Course regions

    private func outline(_ number: Int, teeLat: Double, greenLat: Double, score: Int? = nil,
                         par: Int? = 4) -> CourseHoleOutline {
        CourseHoleOutline(number: number,
                          tee: .init(latitude: teeLat, longitude: lon),
                          green: .init(latitude: greenLat, longitude: lon + 0.001),
                          shots: [.init(latitude: (teeLat + greenLat) / 2, longitude: lon - 0.0005)],
                          score: score, par: par)
    }

    private func contains(_ region: MKCoordinateRegion, _ c: CLLocationCoordinate2D) -> Bool {
        abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && abs(c.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
    }

    func testRouteRunsTeeThenShotsThenGreen() {
        let hole = outline(1, teeLat: 33.0, greenLat: 33.004)
        let lats = hole.route.map(\.latitude)
        XCTAssertEqual(lats.count, 3)
        XCTAssertEqual(lats[0], 33.0, accuracy: 1e-9, "tee first")
        XCTAssertEqual(lats[1], 33.002, accuracy: 1e-9, "then the shots")
        XCTAssertEqual(lats[2], 33.004, accuracy: 1e-9, "green last")
        XCTAssertEqual(hole.badgeCoordinate?.latitude, 33.0)
        let noTee = CourseHoleOutline(number: 2, tee: nil, green: nil,
                                      shots: [.init(latitude: 33.1, longitude: lon)])
        XCTAssertEqual(noTee.badgeCoordinate?.latitude, 33.1)
    }

    func testOverParNeedsBothScoreAndPar() {
        XCTAssertTrue(outline(1, teeLat: 33, greenLat: 33.004, score: 5, par: 4).isOverPar)
        XCTAssertFalse(outline(1, teeLat: 33, greenLat: 33.004, score: 4, par: 4).isOverPar)
        XCTAssertFalse(outline(1, teeLat: 33, greenLat: 33.004, score: 6, par: nil).isOverPar)
    }

    func testAHolesRegionContainsItsWholeRouteWithPadding() throws {
        let hole = outline(3, teeLat: 33.0, greenLat: 33.004)
        let region = try XCTUnwrap(HoleFraming.holeRegion(hole))
        for c in hole.route { XCTAssertTrue(contains(region, c)) }
        XCTAssertEqual(region.center.latitude, 33.002, accuracy: 1e-9)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0.004, "padded beyond the route")
    }

    func testTheCourseRegionContainsEveryHole() throws {
        let holes = [outline(1, teeLat: 33.0, greenLat: 33.004),
                     outline(2, teeLat: 33.005, greenLat: 33.001),
                     outline(3, teeLat: 32.990, greenLat: 32.995)]
        let region = try XCTUnwrap(HoleFraming.courseRegion(holes))
        for hole in holes { for c in hole.route { XCTAssertTrue(contains(region, c), "hole \(hole.number)") } }
        XCTAssertNil(HoleFraming.courseRegion([]))
    }

    func testARegionNeverCollapsesBelowTheMinimumSpan() throws {
        let c = CLLocationCoordinate2D(latitude: 33, longitude: lon)
        let region = try XCTUnwrap(HoleFraming.boundingRegion(of: [c]))
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, HoleFraming.minimumRegionSpanDegrees)
        XCTAssertGreaterThanOrEqual(region.span.longitudeDelta, HoleFraming.minimumRegionSpanDegrees)
        XCTAssertNil(HoleFraming.boundingRegion(of: []))
    }

    // MARK: VoiceOver

    func testShotPinLabels() {
        XCTAssertEqual(HoleMapAccessibility.shotLabel(number: 2, club: "7i", selected: false), "Shot 2, 7i")
        XCTAssertEqual(HoleMapAccessibility.shotLabel(number: 2, club: "7i", selected: true),
                       "Shot 2, 7i, selected")
        XCTAssertEqual(HoleMapAccessibility.shotLabel(number: 3, club: nil, selected: false), "Shot 3")
        XCTAssertEqual(HoleMapAccessibility.shotLabel(number: 3, club: "  ", selected: false), "Shot 3")
    }

    func testHoleBadgeLabels() {
        XCTAssertEqual(HoleMapAccessibility.holeBadgeLabel(number: 7, score: 5), "Hole 7, score 5, tap to review")
        XCTAssertEqual(HoleMapAccessibility.holeBadgeLabel(number: 7, score: nil), "Hole 7, tap to review")
    }

    func testCompassButtonSaysHowFarTheMapIsTurned() {
        XCTAssertEqual(CompassResetButton.accessibilityValue(0.3), "Hole-up")
        XCTAssertEqual(CompassResetButton.accessibilityValue(30), "Turned 30 degrees right")
        XCTAssertEqual(CompassResetButton.accessibilityValue(-45.4), "Turned 45 degrees left")
        XCTAssertEqual(CompassResetButton.size, 44)
    }

    func testModeRules() {
        XCTAssertTrue(HoleMapMode.live.allowsPinDrag)
        XCTAssertTrue(HoleMapMode.hole.allowsPinDrag)
        XCTAssertFalse(HoleMapMode.course.allowsPinDrag)
        XCTAssertTrue(HoleMapMode.live.showsUser)
        XCTAssertFalse(HoleMapMode.hole.showsUser)
        XCTAssertFalse(HoleMapMode.course.showsUser)
    }

    // MARK: Controller

    @MainActor
    private final class SpyDriver: HoleMapDriving {
        var calls: [String] = []
        func holeMapResetToHoleUp(animated: Bool) { calls.append("reset") }
        func holeMapSelectHole(_ number: Int, animated: Bool) { calls.append("select \(number)") }
        func holeMapShowWholeCourse(animated: Bool) { calls.append("course") }
    }

    func testControllerRoutesCommandsToTheMap() {
        let controller = HoleMapController()
        let driver = SpyDriver()
        controller.driver = driver
        controller.selectHole(4)
        XCTAssertEqual(controller.selectedHole, 4)
        controller.showWholeCourse()
        XCTAssertNil(controller.selectedHole)
        controller.resetToHoleUp()
        XCTAssertEqual(driver.calls, ["select 4", "course", "reset"])
    }

    func testASelectionMadeBeforeTheMapAttachesIsKept() {
        let controller = HoleMapController()
        controller.selectHole(9)
        XCTAssertEqual(controller.selectedHole, 9, "the map applies it when it attaches")
    }

    func testRotationIsMeasuredFromHoleUp() {
        let controller = HoleMapController()
        controller.mapDidUpdateHoleUp(80)
        controller.mapDidRotate(to: 110)
        XCTAssertEqual(controller.rotationFromHoleUp, 30, accuracy: 1e-9)
        XCTAssertFalse(controller.isHoleUp)
        controller.mapDidRotate(to: 80.4)
        XCTAssertEqual(controller.heading, 80.4, accuracy: 1e-9)
        XCTAssertTrue(controller.isHoleUp)
    }

    func testAManualGestureStopsAutoFramingAndResetRestoresIt() {
        let controller = HoleMapController()
        XCTAssertTrue(controller.isAutoFraming)
        controller.mapDidStopAutoFraming()
        XCTAssertFalse(controller.isAutoFraming)
        controller.resetToHoleUp()
        XCTAssertTrue(controller.isAutoFraming)
    }
}
