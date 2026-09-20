import CoreLocation
import Foundation

// Wire types — LOCKSTEP with golf-caddie-coursedata `src/schema.ts`. Any
// rename/type change there must mirror here and bump SCHEMA_VERSION. A
// payload whose schemaVersion we don't understand is rejected and the last
// good cache is kept (graceful degradation).
//
// Shared with the watch target: it caches the same catalog to compute
// yardages on the wrist (docs/WATCH_STANDALONE_SPIKE.md).

enum CuratedSchema {
    static let supportedVersion = 1
}

struct GeoPoint: Codable, Equatable {
    var lat: Double
    var lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct CuratedHole: Codable, Equatable {
    var number: Int
    var par: Int
    var yards: Double?
    var strokeIndex: Int?
    var teeAnchor: GeoPoint?
    var greenAnchor: GeoPoint?
}

struct CuratedCourse: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var aliases: [String]
    var location: GeoPoint
    var holes: [CuratedHole]

    func hole(_ number: Int) -> CuratedHole? {
        holes.first { $0.number == number }
    }

    /// Yards from `coordinate` to the hole's green; nil without a green anchor.
    func yardsToGreen(from coordinate: CLLocationCoordinate2D, holeNumber: Int) -> Int? {
        guard let green = hole(holeNumber)?.greenAnchor else { return nil }
        return Int(Distance.yards(fromMeters: Distance.meters(from: coordinate, to: green.coordinate)).rounded())
    }
}

struct CourseDataFile: Codable {
    var schemaVersion: Int
    var courses: [CuratedCourse]
}

enum CourseCatalog {
    /// Raw URL of the PUBLIC golf-caddie-coursedata `data/courses.json`.
    /// Public by decision: course par/yardage is public info, so the raw URL
    /// is unauthenticated — no secret in the app binary.
    static let url = URL(
        string: "https://raw.githubusercontent.com/moisesvargasjr/golf-caddie-coursedata/main/data/courses.json"
    )

    /// Same radius the phone uses to link a round to a curated course.
    static let nearestRadiusMeters: CLLocationDistance = 3000

    /// Nearest course whose centroid is within `within` metres of the
    /// coordinate, or nil. Tiny dataset → in-Swift haversine is fine.
    static func nearest(
        in courses: [CuratedCourse],
        to coord: CLLocationCoordinate2D,
        within: CLLocationDistance = nearestRadiusMeters
    ) -> CuratedCourse? {
        courses
            .map { (course: $0, d: Distance.meters(from: coord, to: $0.location.coordinate)) }
            .filter { $0.d <= within }
            .min { $0.d < $1.d }?
            .course
    }
}
