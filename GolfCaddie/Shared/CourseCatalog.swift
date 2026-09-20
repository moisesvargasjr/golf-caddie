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

/// A tee/green captured in-app on the phone for one hole. Local captures win
/// over the curated anchors (same precedence as the phone's
/// `GlassesStateMapper.greenCoordinate`). Kept SEPARATE from the public catalog
/// on the watch so a direct catalog refresh can't wipe them.
struct CourseAnchorOverride: Codable, Equatable {
    var courseId: String
    var holeNumber: Int
    var tee: GeoPoint?
    var green: GeoPoint?
}

/// Phone → watch `transferFile` payload: the phone's cached public catalog plus
/// its local anchor overrides, unmerged.
struct WatchCatalogPayload: Codable {
    var catalog: CourseDataFile
    var overrides: [CourseAnchorOverride]
}

/// The watch's catalog state: the public catalog (from the phone push OR the
/// watch's own direct fetch — same published file either way) and the
/// phone-provided overrides, stored apart. `courses` is always base + overrides,
/// so overrides keep precedence no matter which source refreshed the base last.
/// Every apply is soft-fail: a bad payload leaves the cache untouched.
struct WatchCatalogCache: Codable, Equatable {
    private(set) var base: [CuratedCourse] = []
    private(set) var overrides: [CourseAnchorOverride] = []
    /// False until a phone push lands — the watch asks the phone to (re)send
    /// while this is false (fresh install / reinstall).
    private(set) var hasPhonePush = false

    var courses: [CuratedCourse] { CourseCatalog.overlay(base, overrides: overrides) }

    @discardableResult
    mutating func applyPhonePush(_ data: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode(WatchCatalogPayload.self, from: data),
              payload.catalog.schemaVersion == CuratedSchema.supportedVersion else { return false }
        base = payload.catalog.courses
        overrides = payload.overrides
        hasPhonePush = true
        return true
    }

    /// A direct public-catalog refresh replaces ONLY the base.
    @discardableResult
    mutating func applyPublicCatalog(_ data: Data) -> Bool {
        guard let file = try? JSONDecoder().decode(CourseDataFile.self, from: data),
              file.schemaVersion == CuratedSchema.supportedVersion else { return false }
        base = file.courses
        return true
    }
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

    /// Apply local tee/green captures over the curated anchors, point by point.
    static func overlay(_ courses: [CuratedCourse], overrides: [CourseAnchorOverride]) -> [CuratedCourse] {
        guard !overrides.isEmpty else { return courses }
        var courses = courses
        for o in overrides {
            guard let c = courses.firstIndex(where: { $0.id == o.courseId }),
                  let h = courses[c].holes.firstIndex(where: { $0.number == o.holeNumber }) else { continue }
            if let tee = o.tee { courses[c].holes[h].teeAnchor = tee }
            if let green = o.green { courses[c].holes[h].greenAnchor = green }
        }
        return courses
    }
}
