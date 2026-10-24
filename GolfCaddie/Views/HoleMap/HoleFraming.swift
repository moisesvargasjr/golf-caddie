import CoreLocation
import MapKit
import UIKit

/// Where the camera goes: the coordinate under the map view's CENTRE, the
/// heading at the top of the screen, and the zoom as metres per point.
/// Pure value; turned into an `MKMapCamera` once the live map has told us how
/// camera distance relates to metres per point (`camera(distanceFactor:)`).
struct HoleFrame: Equatable {
    var center: CLLocationCoordinate2D
    var heading: CLLocationDirection
    var metersPerPoint: Double

    /// `distanceFactor` = camera distance ÷ metres per point for this map
    /// view (it depends on the view's height; HoleMap measures it).
    func camera(distanceFactor: Double) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: center, fromDistance: metersPerPoint * distanceFactor,
                    pitch: 0, heading: heading)
    }

    /// The frame whose camera centre is what THIS frame shows at
    /// `windowCentre + offset` — for a map that draws its camera centre
    /// `offset` points away from the view's centre (measured on the live map).
    func recentered(forCameraCentreOffset offset: CGVector, windowSize: CGSize) -> HoleFrame {
        guard offset.dx != 0 || offset.dy != 0 else { return self }
        let point = CGPoint(x: windowSize.width / 2 + offset.dx, y: windowSize.height / 2 + offset.dy)
        let centre = HoleFraming.coordinate(at: point, frame: self, windowSize: windowSize)
        return HoleFrame(center: centre, heading: heading, metersPerPoint: metersPerPoint)
    }

    static func == (a: HoleFrame, b: HoleFrame) -> Bool {
        a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude
            && a.heading == b.heading && a.metersPerPoint == b.metersPerPoint
    }
}

/// Pure framing math for `HoleMap` (Duo v2, Architecture A): fit tee, green
/// and shots into the part of the window the controls leave free
/// (`SafeChrome.unobstructedRect`), at any heading. The map stays full-window;
/// the camera centre is offset so the hole sits in the middle of the free rect.
///
/// Coordinates: `windowSize` is the map view's size and `unobstructedRect` is
/// in the same space (origin top-left). Geography uses a local flat-earth
/// projection, which is exact enough for anything the size of a golf course.
enum HoleFraming {
    /// Gap kept between the framed points and the edge of the free rect.
    static let padding: CGFloat = 32
    /// Extra gap above the framed points: the green's marker balloon draws
    /// upward from its coordinate (about 40 pt), so a uniform gap let it
    /// touch the top chrome.
    static let markerHeadroom: CGFloat = 24
    /// Never zoom in closer than this across the free rect's short side.
    static let minimumSpanMeters: Double = 120
    /// Floor for `boundingRegion` spans (~55 m).
    static let minimumRegionSpanDegrees: Double = 0.0005
    /// A tee→green shorter than this has no useful direction.
    static let minimumBearingMeters: Double = 5

    private static let earthRadius: Double = 6_371_000
    private static let radians = Double.pi / 180

    // MARK: Rects and insets

    /// A free rect narrower or shorter than this (or a quarter of the window
    /// side, if smaller) is treated as no rect (the whole window): framing
    /// into a sliver would zoom out to the county.
    static let minimumUsableSide: CGFloat = 64

    /// `rect` clipped to the window; the whole window when nothing usable is left.
    static func usableRect(_ rect: CGRect, in windowSize: CGSize) -> CGRect {
        let window = CGRect(origin: .zero, size: windowSize)
        let clipped = rect.intersection(window)
        // The floor is relative on small windows (a quarter of the side).
        let minWidth = max(1, min(minimumUsableSide, windowSize.width / 4))
        let minHeight = max(1, min(minimumUsableSide, windowSize.height / 4))
        guard !clipped.isNull, clipped.width >= minWidth, clipped.height >= minHeight else {
            return window
        }
        return clipped
    }

    /// Edge insets = window minus the unobstructed rect.
    static func edgeInsets(unobstructedRect rect: CGRect, in windowSize: CGSize) -> UIEdgeInsets {
        let usable = usableRect(rect, in: windowSize)
        return UIEdgeInsets(top: usable.minY, left: usable.minX,
                            bottom: windowSize.height - usable.maxY,
                            right: windowSize.width - usable.maxX)
    }

    // MARK: Fit

    /// Frame tee, green and shots inside `unobstructedRect` (padded), at
    /// `heading`. nil when there is nothing to frame or no window.
    static func fitHole(tee: CLLocationCoordinate2D?, green: CLLocationCoordinate2D?,
                        shots: [CLLocationCoordinate2D] = [],
                        unobstructedRect: CGRect, in windowSize: CGSize,
                        heading: CLLocationDirection, padding: CGFloat = HoleFraming.padding) -> HoleFrame? {
        let points = [tee].compactMap { $0 } + shots + [green].compactMap { $0 }
        return fit(points: points, unobstructedRect: unobstructedRect, in: windowSize,
                   heading: heading, padding: padding)
    }

    /// Frame any set of points (the live map adds "you"; course mode every hole).
    static func fit(points: [CLLocationCoordinate2D], unobstructedRect: CGRect, in windowSize: CGSize,
                    heading: CLLocationDirection, padding: CGFloat = HoleFraming.padding) -> HoleFrame? {
        let valid = points.filter(CLLocationCoordinate2DIsValid)
        guard let origin = valid.first, windowSize.width > 0, windowSize.height > 0 else { return nil }
        let target = withHeadroom(padded(usableRect(unobstructedRect, in: windowSize), by: padding))

        let screen = valid.map { screenMeters(of: $0, origin: origin, heading: heading) }
        let xs = screen.map { $0.x }, us = screen.map { $0.u }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minU = us.min() ?? 0, maxU = us.max() ?? 0

        let floor = minimumSpanMeters / Double(min(target.width, target.height))
        let metersPerPoint = max((maxX - minX) / Double(target.width),
                                 (maxU - minU) / Double(target.height), floor)

        // The bounding box's centre must land on the target's centre; the
        // camera centre is whatever then sits at the window's centre.
        let dx = Double(target.midX - windowSize.width / 2) * metersPerPoint
        let dy = Double(target.midY - windowSize.height / 2) * metersPerPoint
        let cameraX = (minX + maxX) / 2 - dx
        let cameraU = (minU + maxU) / 2 + dy // screen y grows down, u grows up
        let center = coordinate(fromScreenX: cameraX, u: cameraU, origin: origin, heading: heading)
        return HoleFrame(center: center, heading: normalizedHeading(heading), metersPerPoint: metersPerPoint)
    }

    /// Where `coordinate` appears in a view of `windowSize` showing `frame`.
    static func project(_ coordinate: CLLocationCoordinate2D, frame: HoleFrame, windowSize: CGSize) -> CGPoint {
        let s = screenMeters(of: coordinate, origin: frame.center, heading: frame.heading)
        return CGPoint(x: windowSize.width / 2 + CGFloat(s.x / frame.metersPerPoint),
                       y: windowSize.height / 2 - CGFloat(s.u / frame.metersPerPoint))
    }

    /// Inverse of `project`: the coordinate shown at `point`.
    static func coordinate(at point: CGPoint, frame: HoleFrame, windowSize: CGSize) -> CLLocationCoordinate2D {
        let x = Double(point.x - windowSize.width / 2) * frame.metersPerPoint
        let u = -Double(point.y - windowSize.height / 2) * frame.metersPerPoint
        return coordinate(fromScreenX: x, u: u, origin: frame.center, heading: frame.heading)
    }

    // MARK: Heading

    /// Hole-up: the camera heading that puts the green straight above the tee.
    /// Falls back to first shot → green, then first → last shot; nil when
    /// there is nothing to orient by (the map then stays as it is / north-up).
    static func holeUpHeading(tee: CLLocationCoordinate2D?, green: CLLocationCoordinate2D?,
                              shots: [CLLocationCoordinate2D] = []) -> CLLocationDirection? {
        let start = tee ?? shots.first
        let end = green ?? (shots.count >= 2 ? shots.last : nil)
        guard let start, let end else { return nil }
        guard Distance.meters(from: start, to: end) > minimumBearingMeters else { return nil }
        return Distance.bearingDegrees(from: start, to: end)
    }

    /// A free rect at least this much wider than tall lays the hole on its side.
    static let sidewaysAspect: CGFloat = 1.4

    /// The heading at the top of the screen for a hole whose hole-up heading
    /// is `holeUp`, framed into a free rect of `freeRect`: hole-up, unless
    /// the rect is clearly landscape — then the hole runs tee-left → green-right
    /// along the long side (canvas iPhone-Landscape).
    static func screenHeading(holeUp: CLLocationDirection, freeRect: CGSize) -> CLLocationDirection {
        guard freeRect.height > 0, freeRect.width >= freeRect.height * sidewaysAspect else {
            return normalizedHeading(holeUp)
        }
        return normalizedHeading(holeUp - 90)
    }

    /// Signed turn from `holeUp` to `heading`, in (-180, 180].
    static func rotation(from holeUp: CLLocationDirection, to heading: CLLocationDirection) -> Double {
        let delta = normalizedHeading(heading - holeUp)
        return delta > 180 ? delta - 360 : delta
    }

    /// Any angle folded into [0, 360).
    static func normalizedHeading(_ degrees: Double) -> Double {
        let folded = degrees.truncatingRemainder(dividingBy: 360)
        return folded < 0 ? folded + 360 : folded
    }

    // MARK: Regions (north-up)

    /// North-up region around `coordinates`, padded by `paddingFraction` of the
    /// span on every side and never smaller than `minimumRegionSpanDegrees`.
    static func boundingRegion(of coordinates: [CLLocationCoordinate2D],
                               paddingFraction: Double = 0.15) -> MKCoordinateRegion? {
        let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard !valid.isEmpty else { return nil }
        let lats = valid.map(\.latitude), lngs = valid.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let grow = 1 + 2 * max(0, paddingFraction)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * grow, minimumRegionSpanDegrees),
            longitudeDelta: max((maxLng - minLng) * grow, minimumRegionSpanDegrees))
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        return MKCoordinateRegion(center: center, span: span)
    }

    /// One hole's bounding region (tee, shots, green).
    static func holeRegion(_ hole: CourseHoleOutline, paddingFraction: Double = 0.15) -> MKCoordinateRegion? {
        boundingRegion(of: hole.route, paddingFraction: paddingFraction)
    }

    /// The whole course: every hole's route.
    static func courseRegion(_ holes: [CourseHoleOutline], paddingFraction: Double = 0.1) -> MKCoordinateRegion? {
        boundingRegion(of: holes.flatMap(\.route), paddingFraction: paddingFraction)
    }

    // MARK: Projection helpers

    /// `rect` less `markerHeadroom` off the top, unless that leaves too little.
    private static func withHeadroom(_ rect: CGRect) -> CGRect {
        guard rect.height > markerHeadroom * 2 else { return rect }
        return CGRect(x: rect.minX, y: rect.minY + markerHeadroom,
                      width: rect.width, height: rect.height - markerHeadroom)
    }

    private static func padded(_ rect: CGRect, by padding: CGFloat) -> CGRect {
        let inset = rect.insetBy(dx: padding, dy: padding)
        guard !inset.isNull, inset.width >= 1, inset.height >= 1 else { return rect }
        return inset
    }

    /// Metres east/north of `origin`.
    private static func eastNorth(of c: CLLocationCoordinate2D,
                                  origin: CLLocationCoordinate2D) -> (east: Double, north: Double) {
        let north = (c.latitude - origin.latitude) * radians * earthRadius
        let east = (c.longitude - origin.longitude) * radians * earthRadius * cos(origin.latitude * radians)
        return (east, north)
    }

    /// Metres right (`x`) and up (`u`) of `origin` on a screen whose top
    /// points along `heading`.
    private static func screenMeters(of c: CLLocationCoordinate2D, origin: CLLocationCoordinate2D,
                                     heading: CLLocationDirection) -> (x: Double, u: Double) {
        let en = eastNorth(of: c, origin: origin)
        let h = heading * radians
        return (en.east * cos(h) - en.north * sin(h), en.east * sin(h) + en.north * cos(h))
    }

    private static func coordinate(fromScreenX x: Double, u: Double, origin: CLLocationCoordinate2D,
                                   heading: CLLocationDirection) -> CLLocationCoordinate2D {
        let h = heading * radians
        let east = x * cos(h) + u * sin(h)
        let north = -x * sin(h) + u * cos(h)
        let lat = origin.latitude + north / (earthRadius * radians)
        let lng = origin.longitude + east / (earthRadius * radians * cos(origin.latitude * radians))
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
