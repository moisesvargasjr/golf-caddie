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
}
