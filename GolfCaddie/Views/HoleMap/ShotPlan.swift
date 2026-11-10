import CoreLocation
import Foundation

/// Shot preview: the line from where you play (the tee, or you once you're on
/// the hole) to the green, bent at a spot the player taps, with the distance
/// of each leg. Pure; `HoleMap` draws it and the screens own the spot.
enum ShotPlan {
    /// You count as on the hole while no further from the green than the tee
    /// is, plus this much (standing beside / behind the tee box).
    static let onHoleMarginMeters: CLLocationDistance = 40
    /// Without a tee anchor: on the hole within this of the green.
    static let noTeeReachMeters: CLLocationDistance = 600
    /// A tap within this many points of the spot clears it.
    static let clearRadiusPoints: Double = 22

    /// Where the line starts: you when `followsUser` (the live hole) and
    /// you're on the hole, else the tee. nil without a green or a start.
    static func start(tee: CLLocationCoordinate2D?, user: CLLocationCoordinate2D?,
                      green: CLLocationCoordinate2D?, followsUser: Bool) -> CLLocationCoordinate2D? {
        guard let green else { return nil }
        if followsUser, let user {
            let reach = tee.map { Distance.meters(from: $0, to: green) + onHoleMarginMeters } ?? noTeeReachMeters
            if Distance.meters(from: user, to: green) <= reach { return user }
        }
        return tee
    }

    /// start → spot → green, or start → green with no spot.
    static func route(start: CLLocationCoordinate2D, aim: CLLocationCoordinate2D?,
                      green: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        [start] + (aim.map { [$0] } ?? []) + [green]
    }

    /// Each leg of the route in yards.
    static func legs(start: CLLocationCoordinate2D, aim: CLLocationCoordinate2D?,
                     green: CLLocationCoordinate2D) -> [Int] {
        let points = route(start: start, aim: aim, green: green)
        return zip(points, points.dropFirst()).map { a, b in
            Int(Distance.yards(fromMeters: Distance.meters(from: a, to: b)).rounded())
        }
    }

    static func midpoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
    }

    /// What a tap on the map makes the spot: nil (cleared) on the spot
    /// itself, else where the tap landed.
    static func tapped(_ coordinate: CLLocationCoordinate2D, aim: CLLocationCoordinate2D?,
                       metersPerPoint: Double) -> CLLocationCoordinate2D? {
        if let aim, Distance.meters(from: coordinate, to: aim) <= clearRadiusPoints * metersPerPoint { return nil }
        return coordinate
    }

    // MARK: Text

    /// A leg's number on the map, in the player's units ("212").
    static func label(yards: Int, units: Units) -> String {
        String(units.format(yards: yards).value)
    }

    /// "TEE → SPOT 212 · SPOT → PIN 187 YD"; nil until a spot is placed.
    static func summary(legs: [Int], units: Units, fromYou: Bool) -> String? {
        guard legs.count == 2 else { return nil }
        let unit = units.format(yards: 0).unit.uppercased()
        return "\(fromYou ? "YOU" : "TEE") → SPOT \(label(yards: legs[0], units: units))"
            + " · SPOT → PIN \(label(yards: legs[1], units: units)) \(unit)"
    }

    static func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.latitude == b.latitude && a.longitude == b.longitude
        default: return false
        }
    }
}
