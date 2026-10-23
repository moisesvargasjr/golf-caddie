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

/// Thin seam between the phone's yardage and the "watch GPS first" policy of
/// PR #18 (`LocationPreference.choose` + `WatchFixStore`). Until #18 merges it
/// uses the phone's live fix; after the merge only `current(phone:)` changes:
///
///     let choice = LocationPreference.choose(
///         watch: WatchFixStore.shared.latest,
///         phone: phone.map(GeoFix.init), at: Date())
///     guard let fix = choice.fix else { return nil }
///     return YardageFix(coordinate: fix.coordinate,
///                       sourceLabel: choice.source == .watch ? "WATCH GPS" : "PHONE GPS")
enum YardageFixAdapter {
    static func current(phone: CLLocation?) -> YardageFix? {
        guard let phone, phone.horizontalAccuracy > 0 else { return nil }
        return YardageFix(coordinate: phone.coordinate, sourceLabel: "PHONE GPS")
    }
}
