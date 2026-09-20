import CoreLocation
@testable import GolfCaddie
import XCTest

/// Shared catalog helpers the watch's on-wrist yardage rests on, plus the
/// phone-side anchor overlay applied before the catalog is pushed to the watch.
final class CourseCatalogTests: XCTestCase {
    private func course(_ id: String, lat: Double, lng: Double, green: GeoPoint? = nil) -> CuratedCourse {
        CuratedCourse(
            id: id, name: id, aliases: [], location: GeoPoint(lat: lat, lng: lng),
            holes: [CuratedHole(number: 1, par: 4, yards: 380, strokeIndex: nil, teeAnchor: nil, greenAnchor: green)]
        )
    }

    func testNearestPicksClosestWithinRadius() {
        let near = course("near", lat: 33.0010, lng: -117.0)
        let nearer = course("nearer", lat: 33.0002, lng: -117.0)
        let here = CLLocationCoordinate2D(latitude: 33.0, longitude: -117.0)
        XCTAssertEqual(CourseCatalog.nearest(in: [near, nearer], to: here)?.id, "nearer")
    }

    func testNearestIsNilOutsideRadius() {
        let far = course("far", lat: 33.1, lng: -117.0) // ~11 km north
        let here = CLLocationCoordinate2D(latitude: 33.0, longitude: -117.0)
        XCTAssertNil(CourseCatalog.nearest(in: [far], to: here))
        XCTAssertNil(CourseCatalog.nearest(in: [], to: here))
    }

    func testYardsToGreen() throws {
        // 0.001° of latitude ≈ 111 m ≈ 121 yd.
        let c = course("c", lat: 33.0, lng: -117.0, green: GeoPoint(lat: 33.001, lng: -117.0))
        let here = CLLocationCoordinate2D(latitude: 33.0, longitude: -117.0)
        let yards = try XCTUnwrap(c.yardsToGreen(from: here, holeNumber: 1))
        XCTAssertEqual(Double(yards), 121, accuracy: 2)
        XCTAssertNil(c.yardsToGreen(from: here, holeNumber: 2), "unknown hole")
        XCTAssertNil(course("nogreen", lat: 33, lng: -117).yardsToGreen(from: here, holeNumber: 1))
    }

    func testOverlayLocalAnchorsWinPerPoint() {
        let curatedGreen = GeoPoint(lat: 33.001, lng: -117.0)
        let c = course("c", lat: 33.0, lng: -117.0, green: curatedGreen)
        let localGreen = LocalCourseAnchor(
            id: LocalCourseAnchor.makeID(courseId: "c", holeNumber: 1), courseId: "c", holeNumber: 1,
            teeLat: nil, teeLng: nil, greenLat: 33.002, greenLng: -117.001, capturedAt: Date()
        )
        let merged = WatchCatalogPusher.overlay(c, anchors: [localGreen])
        XCTAssertEqual(merged.holes[0].greenAnchor, GeoPoint(lat: 33.002, lng: -117.001))
        XCTAssertNil(merged.holes[0].teeAnchor, "a missing local tee leaves the curated tee alone")

        let otherHole = LocalCourseAnchor(
            id: LocalCourseAnchor.makeID(courseId: "c", holeNumber: 9), courseId: "c", holeNumber: 9,
            teeLat: 1, teeLng: 1, greenLat: 1, greenLng: 1, capturedAt: Date()
        )
        XCTAssertEqual(WatchCatalogPusher.overlay(c, anchors: [otherHole]), c)
    }

    func testPhoneStateDecodesWithoutCourseId() throws {
        // An old-phone payload has no curatedCourseId — must still decode (nil).
        var state = PhoneStateUpdate.inactive
        state.curatedCourseId = "c"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: state.encoded()) as? [String: Any])
        json.removeValue(forKey: "curatedCourseId")
        let decoded = try PhoneStateUpdate.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.curatedCourseId)
    }
}
