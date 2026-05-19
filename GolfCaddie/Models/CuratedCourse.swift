import Foundation
import GRDB

// Wire types — LOCKSTEP with golf-caddie-coursedata `src/schema.ts`. Any
// rename/type change there must mirror here and bump SCHEMA_VERSION. A
// payload whose schemaVersion we don't understand is rejected and the last
// good cache is kept (graceful degradation).

enum CuratedSchema {
    static let supportedVersion = 1
}

struct GeoPoint: Codable, Equatable {
    var lat: Double
    var lng: Double
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
}

struct CourseDataFile: Codable {
    var schemaVersion: Int
    var courses: [CuratedCourse]
}

/// On-device cache row. The full `CuratedCourse` is stored as JSON
/// (`payloadJSON`); `name`/`lat`/`lng` are denormalized so proximity + name
/// matching needs no decode.
struct CuratedCourseRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "curatedCourse"

    var id: String
    var name: String
    var lat: Double
    var lng: Double
    var payloadJSON: String
    var fetchedAt: Date

    func decoded() -> CuratedCourse? {
        try? JSONDecoder().decode(CuratedCourse.self, from: Data(payloadJSON.utf8))
    }

    static func from(_ course: CuratedCourse, fetchedAt: Date) -> CuratedCourseRecord? {
        guard let data = try? JSONEncoder().encode(course) else { return nil }
        return CuratedCourseRecord(
            id: course.id,
            name: course.name,
            lat: course.location.lat,
            lng: course.location.lng,
            payloadJSON: String(decoding: data, as: UTF8.self),
            fetchedAt: fetchedAt
        )
    }
}

/// Tee/green anchors captured in-app for a (course, hole). Local-only until
/// exported and merged into the curated catalog; once a curated anchor
/// exists it wins. Tee and green are independently optional.
struct LocalCourseAnchor: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "localCourseAnchor"

    var id: String
    var courseId: String
    var holeNumber: Int
    var teeLat: Double?
    var teeLng: Double?
    var greenLat: Double?
    var greenLng: Double?
    var capturedAt: Date

    static func makeID(courseId: String, holeNumber: Int) -> String {
        "\(courseId)|\(holeNumber)"
    }

    var tee: GeoPoint? {
        guard let teeLat, let teeLng else { return nil }
        return GeoPoint(lat: teeLat, lng: teeLng)
    }

    var green: GeoPoint? {
        guard let greenLat, let greenLng else { return nil }
        return GeoPoint(lat: greenLat, lng: greenLng)
    }
}

/// Anchor-export patch — what the app serializes for a course and the
/// coursedata `import-anchors` CLI merges into the curated catalog. Kept
/// simple and lockstep with that CLI.
struct AnchorExport: Codable {
    struct HoleAnchors: Codable {
        var holeNumber: Int
        var teeAnchor: GeoPoint?
        var greenAnchor: GeoPoint?
    }

    var courseId: String
    var anchors: [HoleAnchors]
}

/// Singleton sync-state row (mirrors the ClubConfiguration singleton pattern).
struct CuratedSyncMeta: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "curatedSyncMeta"

    var id: Int64 = 1
    var lastSyncAt: Date?
    var lastETag: String?
    var lastError: String?
}
