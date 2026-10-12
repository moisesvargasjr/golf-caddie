import CoreLocation
import Foundation

/// The tee box is the one place on a hole we know a stroke came from. When the
/// hole's FIRST full shot lands within `radiusMeters` of the catalog tee point,
/// pin it to the tee — the GPS fix is noise around a known spot.
///
/// The radius comes from the 2026-09-21 Oaks at the Welk round: 14 of 17 first
/// shots landed within 10 m of the tee point; the two outliers (31 m, 64 m —
/// other markers, or a first detection that wasn't the tee shot) must NOT be
/// pulled in, so it's deliberately not generous. A tee point is one
/// coordinate, not the box's outline.
enum TeeSnap {
    static let radiusMeters: CLLocationDistance = 15

    /// The coordinate to store for a full shot, given whether it's the hole's
    /// first full shot and where the tee is. nil tee / not first / too far →
    /// the fix stands.
    static func snapped(
        _ coordinate: CLLocationCoordinate2D?, isFirstFullShot: Bool, tee: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        guard isFirstFullShot, let coordinate, let tee,
              Distance.meters(from: coordinate, to: tee) <= radiusMeters else { return coordinate }
        return tee
    }
}
