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
        let green = CourseAnchorOverride(courseId: "c", holeNumber: 1, tee: nil, green: GeoPoint(lat: 33.002, lng: -117.001))
        let merged = CourseCatalog.overlay([c], overrides: [green])
        XCTAssertEqual(merged[0].holes[0].greenAnchor, GeoPoint(lat: 33.002, lng: -117.001))
        XCTAssertNil(merged[0].holes[0].teeAnchor, "a missing local tee leaves the curated tee alone")

        let otherHole = CourseAnchorOverride(courseId: "c", holeNumber: 9, tee: GeoPoint(lat: 1, lng: 1), green: nil)
        let otherCourse = CourseAnchorOverride(courseId: "x", holeNumber: 1, tee: nil, green: GeoPoint(lat: 1, lng: 1))
        XCTAssertEqual(CourseCatalog.overlay([c], overrides: [otherHole, otherCourse]), [c])
    }

    func testPusherMapsLocalAnchorsToOverrides() {
        let captured = LocalCourseAnchor(
            id: LocalCourseAnchor.makeID(courseId: "c", holeNumber: 1), courseId: "c", holeNumber: 1,
            teeLat: nil, teeLng: nil, greenLat: 33.002, greenLng: -117.001, capturedAt: Date()
        )
        let empty = LocalCourseAnchor(
            id: LocalCourseAnchor.makeID(courseId: "c", holeNumber: 2), courseId: "c", holeNumber: 2,
            teeLat: nil, teeLng: nil, greenLat: nil, greenLng: nil, capturedAt: Date()
        )
        XCTAssertEqual(
            WatchCatalogPusher.overrides(from: [captured, empty]),
            [CourseAnchorOverride(courseId: "c", holeNumber: 1, tee: nil, green: GeoPoint(lat: 33.002, lng: -117.001))]
        )
    }

    // MARK: - Watch cache: phone overrides survive a direct public refresh

    private func publicCatalog(_ courses: [CuratedCourse], schema: Int = CuratedSchema.supportedVersion) throws -> Data {
        try JSONEncoder().encode(CourseDataFile(schemaVersion: schema, courses: courses))
    }

    func testPhonePushThenPublicRefreshKeepsLocalOverrides() throws {
        let curated = course("c", lat: 33.0, lng: -117.0, green: GeoPoint(lat: 33.001, lng: -117.0))
        let localGreen = GeoPoint(lat: 33.002, lng: -117.001)
        let push = try JSONEncoder().encode(WatchCatalogPayload(
            catalog: CourseDataFile(schemaVersion: CuratedSchema.supportedVersion, courses: [curated]),
            overrides: [CourseAnchorOverride(courseId: "c", holeNumber: 1, tee: nil, green: localGreen)]
        ))
        var cache = WatchCatalogCache()
        XCTAssertFalse(cache.hasPhonePush)
        XCTAssertTrue(cache.applyPhonePush(push))
        XCTAssertTrue(cache.hasPhonePush)
        XCTAssertEqual(cache.courses[0].holes[0].greenAnchor, localGreen)

        // HTTP 200 public refresh: curated green moved, a new course published.
        var moved = curated
        moved.holes[0].greenAnchor = GeoPoint(lat: 33.0015, lng: -117.0)
        let added = course("new", lat: 34.0, lng: -118.0)
        XCTAssertTrue(cache.applyPublicCatalog(try publicCatalog([moved, added])))

        XCTAssertEqual(cache.courses.map(\.id), ["c", "new"], "base refreshed from the public file")
        XCTAssertEqual(cache.courses[0].holes[0].greenAnchor, localGreen, "phone override still wins")
        XCTAssertTrue(cache.hasPhonePush)
    }

    func testCacheRejectsBadPayloadsUntouched() throws {
        var cache = WatchCatalogCache()
        XCTAssertTrue(cache.applyPublicCatalog(try publicCatalog([course("c", lat: 33, lng: -117)])))
        let before = cache
        XCTAssertFalse(cache.applyPublicCatalog(Data("nope".utf8)))
        XCTAssertFalse(cache.applyPublicCatalog(try publicCatalog([], schema: 99)))
        XCTAssertFalse(cache.applyPhonePush(try publicCatalog([])), "a bare catalog is not a push payload")
        XCTAssertEqual(cache, before)
        XCTAssertFalse(cache.hasPhonePush, "a direct fetch alone never counts as a phone push")
    }

    // MARK: - Catalog push delivery tracking

    func testPushDecision() {
        typealias State = WatchCatalogPusher.DeliveryState
        // Never delivered (first push, or the last transfer FAILED so nothing was recorded) → send.
        XCTAssertEqual(State(deliveredHash: nil).decide(hash: "a", outstandingHashes: []), .send)
        // Confirmed delivered + unchanged → skip.
        XCTAssertEqual(State(deliveredHash: "a").decide(hash: "a", outstandingHashes: []), .skip)
        // Catalog changed → send.
        XCTAssertEqual(State(deliveredHash: "a").decide(hash: "b", outstandingHashes: []), .send)
        // Same bytes already queued → don't double-queue.
        XCTAssertEqual(State(deliveredHash: nil).decide(hash: "a", outstandingHashes: ["a"]), .skip)
        // A stale queued transfer doesn't block the new catalog.
        XCTAssertEqual(State(deliveredHash: "a").decide(hash: "b", outstandingHashes: ["a"]), .send)
    }

    /// PR #14 review (P2): delivered A → watch reinstalled, requests A → that
    /// transfer FAILS → every later retry (backoff, sync, reachability — none of
    /// them "forced") must still send the unchanged A until a delivery succeeds.
    func testResendIntentSurvivesAFailedTransfer() {
        var state = WatchCatalogPusher.DeliveryState()
        state.transferFinished(hash: "a", succeeded: true)
        XCTAssertEqual(state.decide(hash: "a", outstandingHashes: []), .skip, "precondition: A delivered")

        state.watchRequestedResend()
        XCTAssertEqual(state.decide(hash: "a", outstandingHashes: []), .send, "reinstall request resends A")
        XCTAssertEqual(state.decide(hash: "a", outstandingHashes: ["a"]), .skip, "…but not twice while queued")

        state.transferFinished(hash: "a", succeeded: false)
        XCTAssertEqual(state.decide(hash: "a", outstandingHashes: []), .send, "retry after failure still sends unchanged A")
        XCTAssertEqual(state.decide(hash: "a", outstandingHashes: []), .send, "…and keeps doing so on later retries")

        state.transferFinished(hash: "a", succeeded: true)
        XCTAssertEqual(state.decide(hash: "a", outstandingHashes: []), .skip, "only a confirmed delivery settles it")
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
