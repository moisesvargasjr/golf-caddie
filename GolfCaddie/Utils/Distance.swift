import CoreLocation
import Foundation

enum Distance {
    private static let metersPerYard = 1.0936132983
    private static let metersPerFoot = 3.2808398950

    static func meters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let aLoc = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let bLoc = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return aLoc.distance(from: bLoc)
    }

    static func yards(fromMeters meters: Double) -> Double {
        meters * metersPerYard
    }

    static func feet(fromMeters meters: Double) -> Double {
        meters * metersPerFoot
    }

    /// Initial bearing in degrees (0–360, 0 = north, 90 = east) from `start`
    /// to `end`. Used to orient the active-round and hole-detail maps so the
    /// player's hitting direction points "up" — the camera heading equals the
    /// bearing from tee → green.
    static func bearingDegrees(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLng = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
