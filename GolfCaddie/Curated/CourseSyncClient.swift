import Foundation

/// Pulls the published curated course catalog and caches it on-device. This
/// is the app's FIRST outbound networking (everything else is the inbound
/// loopback GlassesServer + on-device MapKit). It is deliberately
/// soft-fail in every branch — offline, throttled, bad payload, unknown
/// schema all degrade to "keep the last good cache" and are never surfaced
/// (same philosophy as CourseDetector). Reads at the course always come from
/// the local cache; this only refreshes opportunistically when online.
///
/// The catalog is a single static file in the golf-caddie-coursedata repo —
/// no server. `catalogURL` is the raw URL of `data/courses.json`.
@MainActor
final class CourseSyncClient {
    static let shared = CourseSyncClient()
    private init() {}

    /// Raw URL of golf-caddie-coursedata `data/courses.json`.
    ///
    /// PENDING the repo-visibility decision: a PUBLIC repo gives an
    /// unauthenticated raw URL (no secret in the app — preferred, course par
    /// is public info). A PRIVATE repo would require an embedded token, which
    /// reintroduces the secret-in-binary problem we avoided elsewhere. Until
    /// the remote exists this stays nil and sync is a silent no-op (the app
    /// behaves exactly as today). Set to e.g.
    /// "https://raw.githubusercontent.com/moisesvargasjr/golf-caddie-coursedata/main/data/courses.json"
    private static let catalogURL: URL? = nil

    /// Skip if we refreshed within this window (ETag makes refetch cheap, but
    /// no need to even try more than this often).
    private static let minRefreshInterval: TimeInterval = 60 * 60

    private var inFlight = false

    /// Fire-and-forget from app launch. Never throws, never blocks.
    func syncIfStale() async {
        guard !inFlight, let url = Self.catalogURL else { return }
        inFlight = true
        defer { inFlight = false }

        var meta = (try? CourseDataRepository.loadSyncMeta()) ?? CuratedSyncMeta()
        if let last = meta.lastSyncAt,
           Date().timeIntervalSince(last) < Self.minRefreshInterval {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = meta.lastETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 304 {
                try? record(&meta) { $0.lastSyncAt = Date(); $0.lastError = nil }
                return
            }
            guard http.statusCode == 200 else {
                try? record(&meta) { $0.lastError = "HTTP \(http.statusCode)" }
                return
            }

            let file = try JSONDecoder().decode(CourseDataFile.self, from: data)
            guard file.schemaVersion == CuratedSchema.supportedVersion else {
                // Unknown schema → keep the last good cache untouched.
                try? record(&meta) {
                    $0.lastError = "unsupported schemaVersion \(file.schemaVersion)"
                }
                return
            }

            try CourseDataRepository.replaceAll(with: file.courses, fetchedAt: Date())
            let newETag = http.value(forHTTPHeaderField: "Etag")
            try? record(&meta) {
                $0.lastSyncAt = Date()
                $0.lastETag = newETag ?? $0.lastETag
                $0.lastError = nil
            }
        } catch {
            // Offline / timeout / decode failure — cache stays intact.
            try? record(&meta) { $0.lastError = "\(error)" }
        }
    }

    private func record(_ meta: inout CuratedSyncMeta, _ mutate: (inout CuratedSyncMeta) -> Void) throws {
        mutate(&meta)
        try CourseDataRepository.saveSyncMeta(meta)
    }
}
