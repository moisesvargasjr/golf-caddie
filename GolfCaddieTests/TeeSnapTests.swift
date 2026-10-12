import CoreLocation
@testable import GolfCaddie
import XCTest

final class TeeSnapTests: XCTestCase {
    private let tee = CLLocationCoordinate2D(latitude: 33.0, longitude: -117.0)
    private func near(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 33.0 + meters / 111_000, longitude: -117.0)
    }

    func testFirstFullShotNearTheTeeSnaps() throws {
        let out = try XCTUnwrap(TeeSnap.snapped(near(8), isFirstFullShot: true, tee: tee))
        XCTAssertEqual(out.latitude, tee.latitude, accuracy: 1e-9)
    }

    func testOutliersAndLaterShotsKeepTheirFix() throws {
        // Oaks 2026-09-21: 31 m and 64 m first shots were other markers — leave them.
        XCTAssertEqual(try XCTUnwrap(TeeSnap.snapped(near(31), isFirstFullShot: true, tee: tee)).latitude, near(31).latitude)
        XCTAssertEqual(try XCTUnwrap(TeeSnap.snapped(near(8), isFirstFullShot: false, tee: tee)).latitude, near(8).latitude)
        XCTAssertEqual(try XCTUnwrap(TeeSnap.snapped(near(8), isFirstFullShot: true, tee: nil)).latitude, near(8).latitude)
        XCTAssertNil(TeeSnap.snapped(nil, isFirstFullShot: true, tee: tee))
    }
}
