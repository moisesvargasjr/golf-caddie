import CoreLocation
import XCTest
@testable import GolfCaddie

final class DistanceTests: XCTestCase {

    // MARK: - meters / yards / feet

    func test_meters_betweenSameCoord_isZero() {
        let p = CLLocationCoordinate2D(latitude: 33.1234, longitude: -117.0)
        XCTAssertEqual(Distance.meters(from: p, to: p), 0, accuracy: 0.001)
    }

    func test_meters_oneDegreeLatitude_isApprox111km() {
        // One degree of latitude is ~111 km regardless of longitude.
        let a = CLLocationCoordinate2D(latitude: 33.0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 34.0, longitude: 0)
        XCTAssertEqual(Distance.meters(from: a, to: b), 111_000, accuracy: 1_000)
    }

    func test_yards_fromMeters_knownValue() {
        // 1 mile = 1609.344 m = 1760 yd.
        XCTAssertEqual(Distance.yards(fromMeters: 1609.344), 1760, accuracy: 0.5)
    }

    func test_yards_fromMeters_zero() {
        XCTAssertEqual(Distance.yards(fromMeters: 0), 0)
    }

    func test_feet_fromMeters_knownValue() {
        // 1 m ≈ 3.2808 ft.
        XCTAssertEqual(Distance.feet(fromMeters: 1), 3.2808, accuracy: 0.001)
    }

    // MARK: - bearing

    func test_bearing_dueNorth_is0() {
        let start = CLLocationCoordinate2D(latitude: 33.0, longitude: 0)
        let end = CLLocationCoordinate2D(latitude: 34.0, longitude: 0)
        XCTAssertEqual(Distance.bearingDegrees(from: start, to: end), 0, accuracy: 0.01)
    }

    func test_bearing_dueEast_is90() {
        let start = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let end = CLLocationCoordinate2D(latitude: 0, longitude: 1)
        XCTAssertEqual(Distance.bearingDegrees(from: start, to: end), 90, accuracy: 0.01)
    }

    func test_bearing_dueSouth_is180() {
        let start = CLLocationCoordinate2D(latitude: 34.0, longitude: 0)
        let end = CLLocationCoordinate2D(latitude: 33.0, longitude: 0)
        XCTAssertEqual(Distance.bearingDegrees(from: start, to: end), 180, accuracy: 0.01)
    }

    func test_bearing_dueWest_is270() {
        let start = CLLocationCoordinate2D(latitude: 0, longitude: 1)
        let end = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertEqual(Distance.bearingDegrees(from: start, to: end), 270, accuracy: 0.01)
    }

    func test_bearing_NEdiagonal_isApproximately45() {
        // At the equator, NE diagonal is approx 45°; small spherical-projection
        // bias means we allow 1° of slop.
        let start = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let end = CLLocationCoordinate2D(latitude: 0.01, longitude: 0.01)
        XCTAssertEqual(Distance.bearingDegrees(from: start, to: end), 45, accuracy: 1.0)
    }

    func test_bearing_returnsRangeZeroTo360() {
        // Many random pairs — bearing must always be in [0, 360).
        let coords: [(Double, Double)] = [
            (33.0, -117.0), (-45.0, 100.0), (60.0, -50.0),
            (10.0, 10.0), (-10.0, -10.0), (89.0, 179.0),
        ]
        for a in coords {
            for b in coords where a != b {
                let bearing = Distance.bearingDegrees(
                    from: CLLocationCoordinate2D(latitude: a.0, longitude: a.1),
                    to: CLLocationCoordinate2D(latitude: b.0, longitude: b.1)
                )
                XCTAssertGreaterThanOrEqual(bearing, 0)
                XCTAssertLessThan(bearing, 360)
            }
        }
    }
}
