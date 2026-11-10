import CoreLocation
import MapKit
import UIKit

/// What `HoleMap` is asked to plan: the shot preview (`ShotPlan`). The screen
/// owns the spot; the map resolves the start (tee, or you on the live hole),
/// draws start → spot → green with a number on each leg, and reports taps.
struct HoleMapPlan: Equatable {
    /// The tapped spot; nil = the straight line, start → green.
    var aim: CLLocationCoordinate2D?
    /// Start from you once you're on the hole (the live hole).
    var followsUser = false
    /// A tap on the map moves the spot (false: the tap is the screen's, e.g.
    /// to bring hidden controls back).
    var tapsPlaceAim = true
    var units: Units = .yards

    static func == (lhs: HoleMapPlan, rhs: HoleMapPlan) -> Bool {
        ShotPlan.same(lhs.aim, rhs.aim) && lhs.followsUser == rhs.followsUser
            && lhs.tapsPlaceAim == rhs.tapsPlaceAim && lhs.units == rhs.units
    }
}

/// The spot the player tapped.
final class HoleMapAimAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

/// A leg's distance, at its midpoint.
final class HoleMapLegAnnotation: NSObject, MKAnnotation {
    let text: String
    let coordinate: CLLocationCoordinate2D

    init(text: String, coordinate: CLLocationCoordinate2D) {
        self.text = text
        self.coordinate = coordinate
        super.init()
    }
}

/// Ring on the spot. Not interactive: a tap on it reaches the map's tap
/// recognizer, which clears the spot (`ShotPlan.tapped`).
final class HoleMapAimView: MKAnnotationView {
    static let reuseID = "HoleMapAim"
    private static let size: CGFloat = 22

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        backgroundColor = HoleMapColors.ink.withAlphaComponent(0.35)
        layer.cornerRadius = Self.size / 2
        layer.borderColor = HoleMapColors.cream.cgColor
        layer.borderWidth = 3
        isUserInteractionEnabled = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
        accessibilityLabel = "Planned spot"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// "212" on a dark tag over the leg's middle.
final class HoleMapLegView: MKAnnotationView {
    static let reuseID = "HoleMapLeg"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        label.textColor = HoleMapColors.cream
        label.textAlignment = .center
        addSubview(label)
        backgroundColor = HoleMapColors.ink.withAlphaComponent(0.9)
        layer.borderColor = HoleMapColors.cream.cgColor
        layer.borderWidth = 1
        isUserInteractionEnabled = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ text: String) {
        label.text = text
        label.sizeToFit()
        let size = CGSize(width: label.bounds.width + 12, height: label.bounds.height + 6)
        frame = CGRect(origin: frame.origin, size: size)
        label.frame = CGRect(origin: .zero, size: size)
        accessibilityLabel = "\(text) to go"
    }
}

extension HoleMapCoordinator {
    /// Draw the plan for what the screen asked: line, spot, leg numbers.
    /// Diffed on the route and units, so a GPS fix inside `walkReframeMeters`
    /// (following you) or an unrelated update touches nothing.
    func syncPlan(_ map: MKMapView) {
        let route = planRoute(map)
        let units = parent.plan?.units ?? .yards
        let key = (route?.map { Self.key($0) } ?? []).joined(separator: ";") + "|\(units.rawValue)"
        guard key != lastPlanKey else { return }
        lastPlanKey = key
        removePlan(from: map)
        guard let route, let green = route.last else { return }
        map.addOverlay(HoleMapPlanLine(coordinates: route, count: route.count), level: .aboveRoads)
        let legs = ShotPlan.legs(start: route[0], aim: route.count == 3 ? route[1] : nil, green: green)
        var annotations: [MKAnnotation] = zip(route, route.dropFirst()).enumerated().map { index, pair in
            HoleMapLegAnnotation(text: ShotPlan.label(yards: legs[index], units: units),
                                 coordinate: ShotPlan.midpoint(pair.0, pair.1))
        }
        if route.count == 3 { annotations.append(HoleMapAimAnnotation(coordinate: route[1])) }
        map.addAnnotations(annotations)
    }

    func removePlan(from map: MKMapView) {
        let overlays = map.overlays.filter { $0 is HoleMapPlanLine }
        if !overlays.isEmpty { map.removeOverlays(overlays) }
        let annotations = map.annotations.filter { $0 is HoleMapLegAnnotation || $0 is HoleMapAimAnnotation }
        if !annotations.isEmpty { map.removeAnnotations(annotations) }
    }

    /// start → (spot) → green, or nil when there is nothing to plan.
    private func planRoute(_ map: MKMapView) -> [CLLocationCoordinate2D]? {
        guard let plan = parent.plan, parent.mode != .course, let green = parent.green else { return nil }
        let user = plan.followsUser ? planUser(map) : nil
        guard let start = ShotPlan.start(tee: parent.tee, user: user, green: green,
                                         followsUser: plan.followsUser) else { return nil }
        return ShotPlan.route(start: start, aim: plan.aim, green: green)
    }

    /// Your position for the plan, held until you walk `walkReframeMeters`.
    private func planUser(_ map: MKMapView) -> CLLocationCoordinate2D? {
        guard let here = userCoordinate(map) else { return lastPlanUser }
        if let last = lastPlanUser, Distance.meters(from: last, to: here) < Self.walkReframeMeters { return last }
        lastPlanUser = here
        return here
    }

    /// A tap on the map while planning: move the spot, or clear it when the
    /// tap is on the spot. False when the tap isn't the plan's.
    func handlePlanTap(at point: CGPoint, on map: MKMapView) -> Bool {
        guard let plan = parent.plan, plan.tapsPlaceAim, parent.mode != .course, parent.green != nil else {
            return false
        }
        let coordinate = map.convert(point, toCoordinateFrom: map)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        parent.onPlanAim(ShotPlan.tapped(coordinate, aim: plan.aim, metersPerPoint: metersPerPoint(map) ?? 0))
        return true
    }

    func planView(for annotation: MKAnnotation, on mapView: MKMapView) -> MKAnnotationView? {
        if annotation is HoleMapAimAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: HoleMapAimView.reuseID)
                ?? HoleMapAimView(annotation: annotation, reuseIdentifier: HoleMapAimView.reuseID)
            view.annotation = annotation
            return view
        }
        if let leg = annotation as? HoleMapLegAnnotation {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: HoleMapLegView.reuseID)
                as? HoleMapLegView) ?? HoleMapLegView(annotation: annotation, reuseIdentifier: HoleMapLegView.reuseID)
            view.annotation = annotation
            view.configure(leg.text)
            return view
        }
        return nil
    }
}
