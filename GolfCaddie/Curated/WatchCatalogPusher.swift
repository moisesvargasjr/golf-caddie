import CryptoKit
import Foundation
import WatchConnectivity

/// Pushes the cached course catalog to the watch so the wrist can compute its
/// own yardages with the phone away (docs/WATCH_STANDALONE_SPIKE.md). In-app
/// captured local anchors are overlaid first — they win over curated on the
/// phone (`GlassesStateMapper.greenCoordinate`), so the watch must see the same
/// greens. `transferFile` is queued and survives disconnects; a content hash
/// keeps an unchanged catalog from being re-sent. Soft-fail everywhere — the
/// watch's direct catalog fetch is the fallback.
enum WatchCatalogPusher {
    private static let lastHashKey = "watchCatalogPusher.lastHash"

    /// Safe from any context: hops through a plain GCD main-queue block so the
    /// synchronous GRDB reads are legal (see `allCoursesFromAsyncContext`).
    static func pushIfChanged() {
        DispatchQueue.main.async { push() }
    }

    private static func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let courses = try? CourseDataRepository.allCourses(), !courses.isEmpty else { return }

        let merged = courses
            .sorted { $0.id < $1.id }
            .map { overlay($0, anchors: (try? LocalAnchorRepository.anchorsForCourse($0.id)) ?? []) }
        let file = CourseDataFile(schemaVersion: CuratedSchema.supportedVersion, courses: merged)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys // stable bytes → stable hash
        guard let data = try? encoder.encode(file) else { return }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash != UserDefaults.standard.string(forKey: lastHashKey) else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-courses.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        session.transferFile(url, metadata: [ShotContract.fileKindKey: ShotContract.courseCatalogKind])
        UserDefaults.standard.set(hash, forKey: lastHashKey)
    }

    /// Local tee/green captures replace the curated anchors hole-by-hole.
    static func overlay(_ course: CuratedCourse, anchors: [LocalCourseAnchor]) -> CuratedCourse {
        guard !anchors.isEmpty else { return course }
        var course = course
        for anchor in anchors {
            guard let idx = course.holes.firstIndex(where: { $0.number == anchor.holeNumber }) else { continue }
            if let tee = anchor.tee { course.holes[idx].teeAnchor = tee }
            if let green = anchor.green { course.holes[idx].greenAnchor = green }
        }
        return course
    }
}
