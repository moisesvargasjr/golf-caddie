import CoreLocation
import XCTest
@testable import GolfCaddie

/// Shot preview: tap a spot between the start and the green, see both legs.
@MainActor
final class ShotPlanTests: XCTestCase {
    // A straight north–south hole, ~400 yd.
    private let tee = CLLocationCoordinate2D(latitude: 33.0700, longitude: -117.0500)
    private let green = CLLocationCoordinate2D(latitude: 33.0733, longitude: -117.0500)

    private func yards(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        Int(Distance.yards(fromMeters: Distance.meters(from: a, to: b)).rounded())
    }

    func testStartIsTheTeeOffTheHoleAndYouOnIt() {
        let fairway = CLLocationCoordinate2D(latitude: 33.0715, longitude: -117.0501)
        let carPark = CLLocationCoordinate2D(latitude: 33.0650, longitude: -117.0600)
        XCTAssertTrue(ShotPlan.same(ShotPlan.start(tee: tee, user: fairway, green: green, followsUser: true), fairway))
        XCTAssertTrue(ShotPlan.same(ShotPlan.start(tee: tee, user: carPark, green: green, followsUser: true), tee),
                      "further from the green than the tee (+ margin): not on the hole yet")
        XCTAssertTrue(ShotPlan.same(ShotPlan.start(tee: tee, user: fairway, green: green, followsUser: false), tee),
                      "a preview never follows you")
        XCTAssertTrue(ShotPlan.same(ShotPlan.start(tee: tee, user: nil, green: green, followsUser: true), tee))
        XCTAssertTrue(ShotPlan.same(ShotPlan.start(tee: nil, user: fairway, green: green, followsUser: true), fairway),
                      "no tee anchor: you, when near the green")
        XCTAssertNil(ShotPlan.start(tee: nil, user: carPark, green: green, followsUser: true))
        XCTAssertNil(ShotPlan.start(tee: tee, user: fairway, green: nil, followsUser: true))
    }

    func testRouteBendsAtTheAim() {
        let aim = CLLocationCoordinate2D(latitude: 33.0720, longitude: -117.0510)
        XCTAssertEqual(ShotPlan.route(start: tee, aim: nil, green: green).count, 2)
        let bent = ShotPlan.route(start: tee, aim: aim, green: green)
        XCTAssertEqual(bent.count, 3)
        XCTAssertTrue(ShotPlan.same(bent[1], aim))
    }

    func testLegsAreTheTwoDistancesInYards() {
        let aim = CLLocationCoordinate2D(latitude: 33.0720, longitude: -117.0510)
        let legs = ShotPlan.legs(start: tee, aim: aim, green: green)
        XCTAssertEqual(legs, [yards(tee, aim), yards(aim, green)])
        XCTAssertEqual(ShotPlan.legs(start: tee, aim: nil, green: green), [yards(tee, green)])
    }

    func testMidpointSitsBetween() {
        let mid = ShotPlan.midpoint(tee, green)
        XCTAssertEqual(mid.latitude, (tee.latitude + green.latitude) / 2, accuracy: 1e-9)
        XCTAssertEqual(mid.longitude, -117.05, accuracy: 1e-9)
    }

    func testText() {
        XCTAssertEqual(ShotPlan.label(yards: 212, units: .yards), "212")
        XCTAssertEqual(ShotPlan.label(yards: 212, units: .meters), "194")
        XCTAssertEqual(ShotPlan.summary(legs: [212, 187], units: .yards, fromYou: false), "TEE → SPOT 212 · SPOT → PIN 187 YD")
        XCTAssertEqual(ShotPlan.summary(legs: [150, 90], units: .meters, fromYou: true), "YOU → SPOT 137 · SPOT → PIN 82 M")
        XCTAssertNil(ShotPlan.summary(legs: [400], units: .yards, fromYou: false), "no spot: nothing to sum up")
    }

    func testTapNearTheSpotClearsIt() {
        let aim = CLLocationCoordinate2D(latitude: 33.0720, longitude: -117.0510)
        let nearby = CLLocationCoordinate2D(latitude: 33.07205, longitude: -117.0510) // ~5.5 m
        let far = CLLocationCoordinate2D(latitude: 33.0725, longitude: -117.0510)
        XCTAssertNil(ShotPlan.tapped(nearby, aim: aim, metersPerPoint: 0.5), "within ~22 pt of the spot: clear it")
        XCTAssertTrue(ShotPlan.same(ShotPlan.tapped(far, aim: aim, metersPerPoint: 0.5), far))
        XCTAssertTrue(ShotPlan.same(ShotPlan.tapped(far, aim: nil, metersPerPoint: 0.5), far))
    }
}
