import Foundation

/// The watch's own copy of the course catalog, so yardages work with the phone
/// away. Persists a `WatchCatalogCache` (public catalog + phone-provided anchor
/// overrides, kept apart) as one JSON file in Documents. Two sources, both
/// soft-fail (a bad payload never replaces the last good cache):
///   - the phone push (`WatchCatalogPusher`): catalog + overrides;
///   - fallback: a direct ETag fetch of the public catalog — refreshes the base
///     only, so the phone's overrides keep precedence.
@MainActor
final class WatchCourseStore: ObservableObject {
    static let shared = WatchCourseStore()

    @Published private(set) var courses: [CuratedCourse] = []

    private static let etagKey = "watchCourseStore.etag"
    private static let lastFetchKey = "watchCourseStore.lastFetchAt"
    private static let minFetchInterval: TimeInterval = 6 * 60 * 60

    private var cache = WatchCatalogCache()
    private var inFlight = false

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog-cache.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(WatchCatalogCache.self, from: data) {
            cache = saved
            courses = saved.courses
        }
    }

    /// True until a phone push has landed — the watch keeps asking for one.
    var needsPhonePush: Bool { !cache.hasPhonePush }

    func course(byId id: String) -> CuratedCourse? {
        courses.first { $0.id == id }
    }

    @discardableResult
    func installPhonePush(_ data: Data) -> Bool {
        guard cache.applyPhonePush(data) else { return false }
        persist()
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
        guard http.statusCode == 200, cache.applyPublicCatalog(data) else { return }
        persist()
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastFetchKey)
        if let etag = http.value(forHTTPHeaderField: "Etag") {
            defaults.set(etag, forKey: Self.etagKey)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
        courses = cache.courses
    }
}
