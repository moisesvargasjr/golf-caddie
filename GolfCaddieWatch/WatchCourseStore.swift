import Foundation

/// The watch's own copy of the curated course catalog — a single JSON file in
/// Documents, so yardages work with the phone away. Two sources, both
/// soft-fail (a bad payload never replaces the last good cache):
///   - the phone pushes the catalog via `transferFile` (WatchCatalogPusher),
///     with its locally captured anchors overlaid;
///   - fallback: a direct ETag fetch of the public catalog URL.
@MainActor
final class WatchCourseStore: ObservableObject {
    static let shared = WatchCourseStore()

    @Published private(set) var courses: [CuratedCourse] = []

    private static let etagKey = "watchCourseStore.etag"
    private static let lastFetchKey = "watchCourseStore.lastFetchAt"
    private static let minFetchInterval: TimeInterval = 6 * 60 * 60

    private var inFlight = false

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("courses.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let file = Self.decode(data) {
            courses = file.courses
        }
    }

    func course(byId id: String) -> CuratedCourse? {
        courses.first { $0.id == id }
    }

    /// Validate + persist a catalog payload. Returns false (cache untouched)
    /// on an undecodable payload or an unknown schema version.
    @discardableResult
    func install(_ data: Data) -> Bool {
        guard let file = Self.decode(data) else { return false }
        try? data.write(to: Self.fileURL, options: .atomic)
        courses = file.courses
        return true
    }

    /// Direct fetch — covers a fresh watch install the phone hasn't pushed to
    /// yet, and a watch-only day. Throttled unless the cache is empty.
    func fetchIfStale() async {
        guard !inFlight, let url = CourseCatalog.url else { return }
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: Self.lastFetchKey)
        if !courses.isEmpty, Date().timeIntervalSince1970 - last < Self.minFetchInterval { return }
        inFlight = true
        defer { inFlight = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !courses.isEmpty, let etag = defaults.string(forKey: Self.etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 304 {
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastFetchKey)
            return
        }
        guard http.statusCode == 200, install(data) else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastFetchKey)
        if let etag = http.value(forHTTPHeaderField: "Etag") {
            defaults.set(etag, forKey: Self.etagKey)
        }
    }

    private static func decode(_ data: Data) -> CourseDataFile? {
        guard let file = try? JSONDecoder().decode(CourseDataFile.self, from: data),
              file.schemaVersion == CuratedSchema.supportedVersion else { return nil }
        return file
    }
}
