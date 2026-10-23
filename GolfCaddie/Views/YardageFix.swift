import CoreLocation

/// The fix the on-screen yardage is measured from, plus where it came from.
struct YardageFix: Equatable {
    let coordinate: CLLocationCoordinate2D
    /// "WATCH GPS" / "PHONE GPS" — the yardage card's source stamp.
    let sourceLabel: String

    static func == (lhs: YardageFix, rhs: YardageFix) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.sourceLabel == rhs.sourceLabel
    }
}

/// Yardage follows the "watch GPS first" policy (B35): the round's
/// `LocationChoice` (`RoundController.currentLocationChoice`, streamed-watch
/// 10 s gate) picks the watch fix when fresh, else the phone's.
enum YardageFixAdapter {
    static func current(choice: LocationChoice) -> YardageFix? {
        guard let fix = choice.fix else { return nil }
        switch choice.source {
        case .watch: return YardageFix(coordinate: fix.coordinate, sourceLabel: "WATCH GPS")
        case .phone: return YardageFix(coordinate: fix.coordinate, sourceLabel: "PHONE GPS")
        case .none: return nil
        }
    }
}

/// Where the map's dotted walked trail comes from. One seam so the trail
/// follows Track B's watch-first source (`TracePointRepository.preferredTrail`,
/// branch feat/watch-trail) with a one-line change once it lands; today it is
/// the phone breadcrumbs.
enum HoleTrailSource {
    // B38: switch to TracePointRepository.preferredTrail (watch-first trail).
    static func coordinates(roundID: UUID, since: Date) -> [CLLocationCoordinate2D] {
        let points = (try? TracePointRepository.pointsForRound(roundID)) ?? []
        return points.filter { $0.timestamp >= since }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
