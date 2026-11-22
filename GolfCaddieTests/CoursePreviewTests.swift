import XCTest
@testable import GolfCaddie

/// Course preview: look through a course's holes without starting a round.
@MainActor
final class CoursePreviewTests: XCTestCase {
    private let tee1 = GeoPoint(lat: 33.0716, lng: -117.0537)
    private let green1 = GeoPoint(lat: 33.0695, lng: -117.0560)

    private func course(_ holes: [CuratedHole]) -> CuratedCourse {
        CuratedCourse(id: "vy", name: "The Vineyard", aliases: [], location: tee1, holes: holes)
    }

    func testHolesComeInNumberOrderWithCardYardsAndLocalAnchorsWinning() {
        let local = LocalCourseAnchor(id: "vy|2", courseId: "vy", holeNumber: 2, teeLat: 1, teeLng: 2,
                                      greenLat: nil, greenLng: nil, capturedAt: Date())
        let holes = CoursePreview.holes(course: course([
            CuratedHole(number: 2, par: 4, yards: 334, strokeIndex: 6, teeAnchor: tee1, greenAnchor: green1),
            CuratedHole(number: 1, par: 4, yards: 397.4, strokeIndex: 2, teeAnchor: tee1, greenAnchor: green1),
        ]), local: [local])
        XCTAssertEqual(holes.map(\.number), [1, 2])
        XCTAssertEqual(holes[0].yards, 397)
        XCTAssertEqual(holes[1].tee, GeoPoint(lat: 1, lng: 2), "a local tee capture wins")
        XCTAssertEqual(holes[1].green, green1, "the curated green stays where nothing local")
    }

    func testYardsFallBackToTheAnchorsWithoutACardYardage() {
        let holes = CoursePreview.holes(course: course([
            CuratedHole(number: 1, par: 4, yards: nil, strokeIndex: nil, teeAnchor: tee1, greenAnchor: green1),
            CuratedHole(number: 2, par: 3, yards: nil, strokeIndex: nil, teeAnchor: nil, greenAnchor: green1),
        ]), local: [])
        let expected = Int(Distance.yards(fromMeters: Distance.meters(from: tee1.coordinate,
                                                                      to: green1.coordinate)).rounded())
        XCTAssertEqual(holes[0].yards, expected)
        XCTAssertNil(holes[1].yards, "no tee: no length")
    }

    func testPagingWrapsThroughTheCoursesHoles() {
        let nine = (1...9).map { CuratedHole(number: $0, par: 4, yards: nil, strokeIndex: nil) }
        let holes = CoursePreview.holes(course: course(nine), local: [])
        XCTAssertEqual(CoursePreview.next(after: 3, in: holes), 4)
        XCTAssertEqual(CoursePreview.next(after: 9, in: holes), 1, "a nine wraps 9 → 1")
        XCTAssertEqual(CoursePreview.previous(before: 1, in: holes), 9)
        XCTAssertNil(CoursePreview.next(after: 1, in: []))
    }

    func testCaptions() {
        let hole = CoursePreviewHole(number: 7, par: 4, yards: 281, strokeIndex: 18, tee: nil, green: nil)
        XCTAssertEqual(CoursePreview.caption(hole, units: .yards), "PAR 4 · 281 YD · SI 18")
        XCTAssertEqual(CoursePreview.caption(hole, units: .meters), "PAR 4 · 257 M · SI 18")
        let bare = CoursePreviewHole(number: 1, par: nil, yards: nil, strokeIndex: nil, tee: nil, green: nil)
        XCTAssertEqual(CoursePreview.caption(bare, units: .yards), "PAR —")

        let holes = [
            CoursePreviewHole(number: 1, par: 4, yards: 397, strokeIndex: 2, tee: nil, green: nil),
            CoursePreviewHole(number: 2, par: 3, yards: 109, strokeIndex: 16, tee: nil, green: nil),
        ]
        XCTAssertEqual(CoursePreview.courseCaption(holes, units: .yards), "2 HOLES · PAR 7 · 506 YD")
    }

    func testOutlinesCarryParAndAnchorsForTheCourseMap() {
        let holes = [
            CoursePreviewHole(number: 1, par: 4, yards: 397, strokeIndex: 2, tee: tee1, green: green1),
            CoursePreviewHole(number: 2, par: 3, yards: nil, strokeIndex: nil, tee: nil, green: nil),
        ]
        let outlines = CoursePreview.outlines(holes)
        XCTAssertEqual(outlines.map(\.number), [1], "a hole with nothing to draw has no outline")
        XCTAssertEqual(outlines.first?.par, 4)
        XCTAssertNil(outlines.first?.score)
    }

    func testHoleIDsAreStablePerHoleNumber() {
        XCTAssertEqual(CoursePreview.mapID(course: "vy", hole: 3), CoursePreview.mapID(course: "vy", hole: 3))
        XCTAssertNotEqual(CoursePreview.mapID(course: "vy", hole: 3), CoursePreview.mapID(course: "vy", hole: 4))
    }
}
