import CoreLocation
import MapKit

/// Resolves a human-readable golf-course name from a GPS coordinate using
/// Apple's on-device Maps point-of-interest search (`.golf` category).
///
/// Deliberately NOT a networked third-party API: no API key, no new SPM
/// dependency, no `Info.plist`/ATS change, and no *new* off-device data
/// sharing — the coordinate stays within the user's existing OS-level Apple
/// Maps relationship (`MKLocalSearch` is a system framework). For the
/// course-only scope the facility name is the whole feature.
///
/// Returns the nearest golf facility's name, or `nil` on empty results /
/// error / timeout. Callers treat `nil` as "couldn't detect" and silently
/// leave the course unset (consistent with the app's soft-fail location
/// philosophy) — the manual override covers the miss.
///
/// If field testing shows Apple Maps misses real courses the user plays,
/// swapping in a keyed golf-data provider is localized to this one file.
@MainActor
enum CourseDetector {
    /// Search radius around the start fix. A golfer who just started a round
    /// is on or adjacent to the course; this comfortably covers a large
    /// 36-hole facility + clubhouse without pulling in a course a town over.
    private static let searchRadiusMeters: CLLocationDistance = 1500

    static func detectCourseName(near coordinate: CLLocationCoordinate2D) async -> String? {
        let request = MKLocalPointsOfInterestRequest(
            center: coordinate,
            radius: searchRadiusMeters
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.golf])

        let search = MKLocalSearch(request: request)
        // try? → any error (offline, throttled, cancelled) degrades to nil,
        // i.e. "couldn't detect" — never surfaced, never fatal.
        guard let response = try? await search.start() else { return nil }

        let origin = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Nearest named golf POI wins. At a multi-course facility this can
        // still pick a sibling course; that residual is why the name is
        // user-editable in the UI rather than silently authoritative.
        let nearest = response.mapItems
            .compactMap { item -> (name: String, distance: CLLocationDistance)? in
                guard let name = item.name, !name.isEmpty else { return nil }
                return (name, item.location.distance(from: origin))
            }
            .min { $0.distance < $1.distance }

        return nearest?.name
    }
}
