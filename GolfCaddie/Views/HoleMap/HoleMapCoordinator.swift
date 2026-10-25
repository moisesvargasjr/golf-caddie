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
    /// The frame an animated reframe is gliding to; checked (and snapped
    /// if MapKit ended a few points off) when the animation ends.
    private var animatingTo: HoleFrame?
    private var loupeTracker: LoupeTracker?
    /// Measured on this map at this size: camera distance ÷ metres-per-point,
    /// and where the camera centre is drawn relative to the view's centre.
    private var calibration: Calibration?

    private struct Calibration {
        let size: CGSize
        let factor: Double
        let centreOffset: CGVector
    }

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
        // A new hole (or course ⇄ hole) glides there; a soft change eases.
        let animated = hasFramed && !sizeChanged
        let glide = animated && hardChanged
        Task { @MainActor [weak self, weak map] in
            guard let self, let map else { return }
            self.reframe(map, animated: animated, glide: glide)
        }
    }

    func reframe(_ map: MKMapView, animated: Bool, resettingHeading: Bool = false, glide: Bool = false) {
        let fallback = resettingHeading ? 0 : map.camera.heading
        let fromWidth = glide ? (metersPerPoint(map) ?? 0) * Double(map.bounds.width) : 0
        guard let frame = currentFrame(map, fallbackHeading: fallback),
              var measured = calibration(map, near: frame) else { return }
        if parent.mode == .live { lastFrameUserCoord = userCoordinate(map) }
        hasFramed = true
        let size = map.bounds.size
        if glide {
            let target = camera(for: frame, measured, size: size)
            run(HoleGlide.plan(from: map.camera, fromWidth: fromWidth,
                               to: target, toWidth: frame.metersPerPoint * Double(size.width)),
                on: map, landingOn: frame)
            return
        }
        map.setCamera(camera(for: frame, measured, size: size), animated: animated)
        guard !animated else {
            animatingTo = frame
            logFrame(frame, map: map, animated: true)
            return
        }
        animatingTo = nil
        // Check the jump landed (the first measurement can come from a camera
        // MapKit hadn't applied yet); re-measure and correct once.
        for _ in 0..<2 {
            guard !landed(frame, on: map), let again = recalibrate(map) else { break }
            measured = again
            map.setCamera(camera(for: frame, measured, size: size), animated: false)
        }
        logFrame(frame, map: map)
    }

    /// Plays a glide's steps as timed camera animations; the last step's
    /// end is snapped onto `frame` when it lands (`settleAnimatedFrame`).
    private func run(_ glide: HoleGlide, on map: MKMapView, landingOn frame: HoleFrame) {
        var steps = glide.steps[...]
        func next() {
            guard let step = steps.popFirst() else { return }
            let isLast = steps.isEmpty
            animatingTo = isLast ? frame : nil
            let camera = MKMapCamera(lookingAtCenter: step.center, fromDistance: step.distance,
                                     pitch: 0, heading: step.heading)
            UIView.animate(withDuration: step.duration, delay: 0,
                           options: [isLast ? .curveEaseOut : .curveEaseIn, .allowUserInteraction]) {
                map.setCamera(camera, animated: false)
            } completion: { [weak self] finished in
                // A pan or pinch mid-glide stops it where the golfer took over.
                guard finished, let self, self.parent.controller.isAutoFraming else { return }
                next()
            }
        }
        logFrame(frame, map: map, animated: true)
        next()
    }

    private func camera(for frame: HoleFrame, _ measured: Calibration, size: CGSize) -> MKMapCamera {
        frame.recentered(forCameraCentreOffset: measured.centreOffset, windowSize: size)
            .camera(distanceFactor: measured.factor)
    }

    /// Whether the map now shows `frame`: its centre at the view's centre and
    /// the expected scale (within a couple of points / percent).
    private func landed(_ frame: HoleFrame, on map: MKMapView) -> Bool {
        let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let centre = map.convert(frame.center, toPointTo: map)
        guard abs(centre.x - mid.x) <= 2, abs(centre.y - mid.y) <= 2,
              let mpp = metersPerPoint(map) else { return false }
        return abs(mpp / frame.metersPerPoint - 1) <= 0.02
    }

    private func logFrame(_ frame: HoleFrame, map: MKMapView, animated: Bool = false) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "DebugMapFraming") else { return }
        let rect = unobstructedRectInMap(map)
        let tee = parent.tee.map { map.convert($0, toPointTo: map) }
        let green = parent.green.map { map.convert($0, toPointTo: map) }
        let message = "[HoleMap] animated=\(animated) bounds=\(map.bounds) rect=\(rect) mpp=\(frame.metersPerPoint) "
              + "measured=\(metersPerPoint(map) ?? -1) dist=\(map.camera.centerCoordinateDistance) "
              + "tee=\(tee.map { "\($0)" } ?? "-") green=\(green.map { "\($0)" } ?? "-") "
              + "offset=\(calibration?.centreOffset ?? .zero)"
        NSLog("%@", message)
        #endif
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
            guard let holeUp = HoleFraming.holeUpHeading(tee: parent.tee, green: parent.green,
                                                         shots: shotCoordinates) else { return nil }
            guard let map = mapView else { return holeUp }
            return HoleFraming.screenHeading(holeUp: holeUp, freeRect: unobstructedRectInMap(map).size)
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

    /// The unobstructed rect, already in the map's own coordinates (no
    /// UIWindow conversion: under DEBUG `-DebugWindowSize` the SwiftUI tree is
    /// scaled, so window coordinates don't match the map's bounds).
    private func unobstructedRectInMap(_ map: MKMapView) -> CGRect {
        let size = map.bounds.size
        guard let rect = parent.unobstructedRect else { return CGRect(origin: .zero, size: size) }
        return HoleFraming.usableRect(rect, in: size)
    }

    /// Camera distance per metre-per-point (and the camera-centre offset).
    /// Depends on the view's size, so it is cached per size; measured on a
    /// close camera because the default whole-country camera is too curved
    /// to measure.
    private func calibration(_ map: MKMapView, near frame: HoleFrame) -> Calibration? {
        if let calibration, calibration.size == map.bounds.size { return calibration }
        if map.camera.centerCoordinateDistance > Self.calibrationMaxDistance {
            let probe = MKMapCamera(lookingAtCenter: frame.center, fromDistance: Self.calibrationProbeDistance,
                                    pitch: 0, heading: frame.heading)
            map.setCamera(probe, animated: false)
        }
        return recalibrate(map)
    }

    @discardableResult
    private func recalibrate(_ map: MKMapView) -> Calibration? {
        let size = map.bounds.size
        guard let metersPerPoint = metersPerPoint(map) else { return nil }
        let distance = map.camera.centerCoordinateDistance
        guard distance > 0, distance.isFinite else { return nil }
        let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let drawn = map.convert(map.camera.centerCoordinate, toPointTo: map)
        var offset = CGVector(dx: drawn.x - mid.x, dy: drawn.y - mid.y)
        if !offset.dx.isFinite || !offset.dy.isFinite || abs(offset.dx) > size.width / 2
            || abs(offset.dy) > size.height / 2 {
            offset = .zero
        }
        let measured = Calibration(size: size, factor: distance / metersPerPoint, centreOffset: offset)
        calibration = measured
        return measured
    }

    /// Metres per point at the view's centre, horizontally (nil before the
    /// map can convert).
    private func metersPerPoint(_ map: MKMapView) -> Double? {
        let size = map.bounds.size
        let step = min(100, size.width / 4)
        guard step >= 1, size.height >= 1 else { return nil }
        let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let a = map.convert(mid, toCoordinateFrom: map)
        let b = map.convert(CGPoint(x: mid.x + step, y: mid.y), toCoordinateFrom: map)
        guard CLLocationCoordinate2DIsValid(a), CLLocationCoordinate2DIsValid(b) else { return nil }
        let value = Distance.meters(from: a, to: b) / Double(step)
        return value > 0 && value.isFinite ? value : nil
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
        if isUserGesture(mapView) {
            animatingTo = nil
            parent.controller.mapDidStopAutoFraming()
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        parent.controller.mapDidRotate(to: mapView.camera.heading)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        parent.controller.mapDidRotate(to: mapView.camera.heading)
        if mapView.camera.centerCoordinateDistance <= Self.calibrationMaxDistance { recalibrate(mapView) }
        settleAnimatedFrame(mapView)
    }

    /// An animated glide can end a few points off (MapKit eases the camera
    /// centre and the safe-area offset together): snap it onto the target.
    private func settleAnimatedFrame(_ map: MKMapView) {
        guard let target = animatingTo else { return }
        animatingTo = nil
        guard parent.controller.isAutoFraming, draggingShotID == nil, !isUserGesture(map),
              !landed(target, on: map), let measured = recalibrate(map) else { return }
        map.setCamera(camera(for: target, measured, size: map.bounds.size), animated: false)
        logFrame(target, map: map)
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
            startLoupe(following: view, on: mapView)
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
        loupeTracker?.stop()
        loupeTracker = nil
    }

    /// Keeps the loupe on the dragged pin every frame (MapKit moves the pin
    /// view itself; its coordinate only updates when the drag ends).
    private func startLoupe(following view: MKAnnotationView, on map: MKMapView) {
        guard let host = map as? HoleMapView else { return }
        loupeTracker?.stop()
        loupeTracker = LoupeTracker(pin: view, host: host)
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

/// Drives `HoleMapLoupe` from a display link while a pin is dragged.
@MainActor
private final class LoupeTracker: NSObject {
    private weak var pin: MKAnnotationView?
    private weak var host: HoleMapView?
    private var link: CADisplayLink?

    init(pin: MKAnnotationView, host: HoleMapView) {
        self.pin = pin
        self.host = host
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        tick()
    }

    @objc private func tick() {
        guard let pin, let host, let container = pin.superview else { return stop() }
        // Pin views live in MapKit's annotation container: convert to the map.
        host.loupe.show(at: container.convert(pin.center, to: host), in: host)
    }

    func stop() {
        link?.invalidate()
        link = nil
        host?.loupe.hide()
    }
}

