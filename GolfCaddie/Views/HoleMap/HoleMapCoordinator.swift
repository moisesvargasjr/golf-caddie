import CoreLocation
import MapKit
import UIKit

/// MKMapView delegate + gestures + camera for `HoleMap`. Content sync
/// (pins, lines, badges) lives in `HoleMapCoordinator+Content.swift`.
@MainActor
final class HoleMapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate, HoleMapDriving {
    /// Latest inputs; replaced on every `updateUIView`.
    var parent: HoleMap
    weak var mapView: MKMapView?

    // Content sync state (see +Content).
    var lastMode: HoleMapMode?
    var lastTrailKey: String?
    var lastShotLineKey: String?
    var lastCourseKey: String?
    var lastAimUserCoord: CLLocationCoordinate2D?
    var lastAimGreen: CLLocationCoordinate2D?
    var draggingShotID: UUID?
    private var dragOrigin: CLLocationCoordinate2D?

    // Framing state.
    private var lastHardFrameKey: String?
    private var lastSoftFrameKey: String?
    private var lastSizeKey: String?
    private var hasFramed = false
    private var lastFrameUserCoord: CLLocationCoordinate2D?
    /// Camera distance ÷ metres-per-point, measured on this map at this size.
    private var calibration: (size: CGSize, factor: Double)?

    private weak var tapRecognizer: UITapGestureRecognizer?
    private weak var pressRecognizer: UILongPressGestureRecognizer?

    /// Walking this far re-frames the live hole and redraws the aim line.
    static let walkReframeMeters: Double = 12
    /// Calibrate only on a close, flat camera (far out the globe curves).
    private static let calibrationMaxDistance: CLLocationDistance = 20_000
    private static let calibrationProbeDistance: CLLocationDistance = 1_000
    static let longPressDuration: TimeInterval = 0.5

    init(parent: HoleMap) {
        self.parent = parent
        super.init()
    }

    // MARK: Lifecycle

    func install(on map: MKMapView) {
        mapView = map
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        map.addGestureRecognizer(tap)
        tapRecognizer = tap
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        press.minimumPressDuration = Self.longPressDuration
        press.delegate = self
        map.addGestureRecognizer(press)
        pressRecognizer = press
        (map as? HoleMapView)?.onBoundsChange = { [weak self] map in
            self?.reframeIfNeeded(map)
        }
    }

    func uninstall(from map: MKMapView) {
        if parent.controller.driver === self { parent.controller.driver = nil }
        (map as? HoleMapView)?.onBoundsChange = nil
        map.delegate = nil
    }

    /// Called from `updateUIView`.
    func sync(_ map: MKMapView) {
        mapView = map
        if parent.controller.driver !== self { parent.controller.driver = self }
        let mode = parent.mode
        let modeChanged = lastMode != mode
        if modeChanged { enterMode(mode, on: map) }
        if mode == .course {
            syncCourse(map)
        } else {
            syncHoleContent(map)
        }
        lastMode = mode
        publishHoleUp()
        reframeIfNeeded(map)
    }

    // MARK: Framing

    /// Hard change (hole, anchors, mode) always re-frames and turns
    /// auto-framing back on. Soft change (map size, unobstructed rect, a new
    /// live shot) re-frames only while auto-framing — animated, so the hole
    /// glides when auto-hide shows or hides the controls.
    private func reframeIfNeeded(_ map: MKMapView) {
        let size = "\(Int(map.bounds.width))x\(Int(map.bounds.height))"
        let rect = parent.unobstructedRect.map {
            "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))"
        } ?? "-"
        let hard: String
        var soft = "\(size)|\(rect)"
        switch parent.mode {
        case .course:
            hard = "course|\(lastCourseKey ?? "")"
        case .live, .hole:
            hard = "\(parent.mode)|\(parent.holeID?.uuidString ?? "-")|"
                + "\(Self.key(parent.tee))|\(Self.key(parent.green))"
            if parent.mode == .live { soft += "|\(placedShots.count)" }
        }
        let hardChanged = hard != lastHardFrameKey
        guard hardChanged || soft != lastSoftFrameKey else { return }
        let sizeChanged = size != lastSizeKey
        lastHardFrameKey = hard
        lastSoftFrameKey = soft
        lastSizeKey = size

        let controller = parent.controller
        if hardChanged {
            Task { @MainActor in controller.mapDidStartAutoFraming() }
        } else if !controller.isAutoFraming {
            return
        }
        // After this layout pass, so the camera is fitted to the NEW bounds.
        let animated = hasFramed && !sizeChanged
        Task { @MainActor [weak self, weak map] in
            guard let self, let map else { return }
            self.reframe(map, animated: animated)
        }
    }

    func reframe(_ map: MKMapView, animated: Bool, resettingHeading: Bool = false) {
        let fallback = resettingHeading ? 0 : map.camera.heading
        guard let frame = currentFrame(map, fallbackHeading: fallback),
              let factor = distanceFactor(map, near: frame) else { return }
        if parent.mode == .live { lastFrameUserCoord = userCoordinate(map) }
        hasFramed = true
        map.setCamera(frame.camera(distanceFactor: factor), animated: animated)
    }

    private func currentFrame(_ map: MKMapView, fallbackHeading: CLLocationDirection) -> HoleFrame? {
        let size = map.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = unobstructedRectInMap(map)
        let heading = currentHoleUp() ?? fallbackHeading
        switch parent.mode {
        case .course:
            let points = selectedOutline()?.route ?? parent.courseHoles.flatMap(\.route)
            return HoleFraming.fit(points: points, unobstructedRect: rect, in: size, heading: heading)
        case .hole:
            return HoleFraming.fitHole(tee: parent.tee, green: parent.green, shots: shotCoordinates,
                                       unobstructedRect: rect, in: size, heading: heading)
        case .live:
            let points = [parent.tee].compactMap { $0 } + shotCoordinates
                + [parent.green, userCoordinate(map)].compactMap { $0 }
            return HoleFraming.fit(points: points, unobstructedRect: rect, in: size, heading: heading)
        }
    }

    /// Hole-up for what is on screen: the hole's tee → green; the course
    /// overview is north-up.
    func currentHoleUp() -> CLLocationDirection? {
        switch parent.mode {
        case .course:
            guard let hole = selectedOutline() else { return 0 }
            return hole.holeUpHeading ?? 0
        case .live, .hole:
            return HoleFraming.holeUpHeading(tee: parent.tee, green: parent.green, shots: shotCoordinates)
        }
    }

    private func selectedOutline() -> CourseHoleOutline? {
        guard let number = parent.controller.selectedHole else { return nil }
        return parent.courseHoles.first { $0.number == number }
    }

    private func publishHoleUp() {
        let holeUp = currentHoleUp()
        let controller = parent.controller
        guard holeUp != controller.holeUpHeading else { return }
        // Not during the SwiftUI update pass.
        Task { @MainActor in controller.mapDidUpdateHoleUp(holeUp) }
    }

    /// The unobstructed rect (window coordinates) in the map's own space.
    private func unobstructedRectInMap(_ map: MKMapView) -> CGRect {
        let bounds = map.bounds
        let local = CGRect(origin: .zero, size: bounds.size)
        guard let rect = parent.unobstructedRect, rect.width > 0, rect.height > 0 else { return local }
        let converted = map.window == nil ? rect : map.convert(rect, from: nil)
        let clipped = converted.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return local }
        return clipped.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
    }

    /// Camera distance per metre-per-point. Depends on the view's height, so
    /// it is cached per size; measured on a close camera because the default
    /// whole-country camera is too curved to measure.
    private func distanceFactor(_ map: MKMapView, near frame: HoleFrame) -> Double? {
        if let calibration, calibration.size == map.bounds.size { return calibration.factor }
        if map.camera.centerCoordinateDistance > Self.calibrationMaxDistance {
            let probe = MKMapCamera(lookingAtCenter: frame.center, fromDistance: Self.calibrationProbeDistance,
                                    pitch: 0, heading: frame.heading)
            map.setCamera(probe, animated: false)
        }
        return recalibrate(map)
    }

    @discardableResult
    private func recalibrate(_ map: MKMapView) -> Double? {
        let size = map.bounds.size
        let step = min(100, size.width / 4)
        guard step >= 1, size.height >= 1 else { return nil }
        let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let a = map.convert(mid, toCoordinateFrom: map)
        let b = map.convert(CGPoint(x: mid.x + step, y: mid.y), toCoordinateFrom: map)
        guard CLLocationCoordinate2DIsValid(a), CLLocationCoordinate2DIsValid(b) else { return nil }
        let metersPerPoint = Distance.meters(from: a, to: b) / Double(step)
        let distance = map.camera.centerCoordinateDistance
        guard metersPerPoint > 0, distance > 0, distance.isFinite else { return nil }
        let factor = distance / metersPerPoint
        calibration = (size, factor)
        return factor
    }

    // MARK: HoleMapDriving

    func holeMapResetToHoleUp(animated: Bool) {
        guard let map = mapView else { return }
        reframe(map, animated: animated, resettingHeading: true)
    }

    func holeMapSelectHole(_ number: Int, animated: Bool) {
        guard let map = mapView else { return }
        publishHoleUp()
        reframe(map, animated: animated)
    }

    func holeMapShowWholeCourse(animated: Bool) {
        guard let map = mapView else { return }
        publishHoleUp()
        reframe(map, animated: animated, resettingHeading: true)
    }

    // MARK: Gestures

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        parent.onTapMap()
    }

    @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, parent.mode != .course,
              let map = recognizer.view as? MKMapView else { return }
        let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        parent.onLongPress(coordinate)
    }

    /// Touches on a pin or badge belong to MapKit (select / drag), not to the
    /// map-tap or hold-to-add recognizers.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is MKAnnotationView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// A pan / pinch / rotate by the player (not our own tap / hold).
    private func isUserGesture(_ map: MKMapView) -> Bool {
        let ours: [UIGestureRecognizer?] = [tapRecognizer, pressRecognizer]
        let recognizers = (map.gestureRecognizers ?? []) + map.subviews.flatMap { $0.gestureRecognizers ?? [] }
        return recognizers.contains { recognizer in
            !ours.contains { $0 === recognizer } && (recognizer.state == .began || recognizer.state == .changed)
        }
    }

    // MARK: MKMapViewDelegate — camera

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        if isUserGesture(mapView) { parent.controller.mapDidStopAutoFraming() }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        parent.controller.mapDidRotate(to: mapView.camera.heading)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        parent.controller.mapDidRotate(to: mapView.camera.heading)
        if mapView.camera.centerCoordinateDistance <= Self.calibrationMaxDistance { recalibrate(mapView) }
    }

    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard parent.mode == .live else { return }
        syncAimLine(mapView)
        guard parent.controller.isAutoFraming, draggingShotID == nil,
              let here = userLocation.location?.coordinate, CLLocationCoordinate2DIsValid(here) else { return }
        if let last = lastFrameUserCoord, Distance.meters(from: last, to: here) < Self.walkReframeMeters { return }
        reframe(mapView, animated: true)
    }

    // MARK: MKMapViewDelegate — selection and drag

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        if let shot = annotation as? HoleMapShotAnnotation {
            // Stays selected in MapKit (a deselect could cancel a drag that is
            // starting); `syncMapKitSelection` clears it when the screen does.
            parent.onSelectShot(shot.shotID)
            return
        }
        if let badge = annotation as? HoleMapBadgeAnnotation {
            parent.onSelectHole(badge.holeNumber)
        } else {
            parent.onTapMap() // "you" or the flag: just a tap on the map
        }
        // So the same badge can be tapped again.
        Task { @MainActor [weak mapView] in mapView?.deselectAnnotation(annotation, animated: false) }
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                 didChange newState: MKAnnotationView.DragState,
                 fromOldState oldState: MKAnnotationView.DragState) {
        guard let annotation = view.annotation as? HoleMapShotAnnotation else { return }
        switch newState {
        case .starting:
            draggingShotID = annotation.shotID
            dragOrigin = annotation.coordinate
            view.dragState = .dragging
            parent.onDragChanged(true)
        case .ending:
            let snapped = parent.snapper.snappedCoordinate(for: annotation.shot, droppedAt: annotation.coordinate)
            annotation.coordinate = snapped
            view.dragState = .none
            endDrag()
            parent.onMoveShot(annotation.shotID, snapped)
        case .canceling:
            if let dragOrigin { annotation.coordinate = dragOrigin }
            view.dragState = .none
            endDrag()
        default:
            break
        }
    }

    private func endDrag() {
        draggingShotID = nil
        dragOrigin = nil
        parent.onDragChanged(false)
    }

    // MARK: Helpers

    func userCoordinate(_ map: MKMapView) -> CLLocationCoordinate2D? {
        guard map.showsUserLocation, let c = map.userLocation.location?.coordinate,
              CLLocationCoordinate2DIsValid(c) else { return nil }
        return c
    }

    static func key(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "-" }
        return String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }
}
