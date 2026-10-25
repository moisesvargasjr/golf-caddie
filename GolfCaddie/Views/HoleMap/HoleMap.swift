import CoreLocation
import MapKit
import SwiftUI

/// The one round map (Duo v2, Architecture A): replaces the old live map
/// (follows "you", aim line) and `EditableHoleMap` (draggable pins, fixed
/// camera) and adds the course overview. `RoundMapScreen` keeps ONE of these
/// full-bleed behind every layout, so a posture change never rebuilds the
/// `MKMapView`.
///
/// The map never writes to the database. It reports:
/// - `onMoveShot(id, coordinate)` when a pin is dropped — already snapped to
///   the walking path within 8 m (`ShotPlacement.pinned`, watch points
///   first); the caller saves it as `.manual` (`HoleSession.moveShot`);
/// - `onLongPress(coordinate)` — hold the map to add a shot (not saved here);
/// - `onSelectShot(id)` for a pin tap, `onTapMap()` for a tap on empty map
///   (auto-hide brings the controls back), `onSelectHole(n)` for a course
///   badge tap, and `onDragChanged(isDragging)` (pause auto-hide with `.drag`).
///
/// Framing: tee and green are fitted into `unobstructedRect` — in the MAP
/// VIEW's own coordinates (origin top-left of the map; see
/// `ChromeFrames.unobstructedRect(display:frames:mapFrame:)`) — and re-fitted with
/// animation when it changes (auto-hide showing/hiding the controls), unless
/// the player has panned, zoomed or rotated by hand (`controller.isAutoFraming`).
struct HoleMap: UIViewRepresentable {
    var mode: HoleMapMode
    /// Commands (compass reset, course glide) and reported heading.
    var controller: HoleMapController
    /// The hole on screen; a change re-frames. nil in course mode.
    var holeID: UUID?
    var tee: CLLocationCoordinate2D?
    var green: CLLocationCoordinate2D?
    /// The hole's shots in playing order (unplaced ones are skipped).
    var shots: [Shot] = []
    /// Club tag under each pin, by shot id ("7i").
    var clubLabels: [UUID: String] = [:]
    var selectedShotID: UUID?
    /// Walked GPS breadcrumbs for the hole (`HoleTrailSource`), drawn dotted.
    var trail: [CLLocationCoordinate2D] = []
    /// Course mode: every hole's outline.
    var courseHoles: [CourseHoleOutline] = []
    /// Free area for framing, in the map's own coordinates; nil = the whole map.
    var unobstructedRect: CGRect?
    var snapper: HoleMapShotSnapper = .live

    var onMoveShot: (UUID, CLLocationCoordinate2D) -> Void = { _, _ in }
    var onLongPress: (CLLocationCoordinate2D) -> Void = { _ in }
    var onSelectShot: (UUID) -> Void = { _ in }
    var onTapMap: () -> Void = {}
    var onSelectHole: (Int) -> Void = { _ in }
    var onDragChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> HoleMapCoordinator {
        HoleMapCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> HoleMapView {
        let map = HoleMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKImageryMapConfiguration()
        map.showsCompass = false // CompassResetButton replaces it
        map.showsScale = false
        map.isRotateEnabled = true // pinch-rotate (rule 10)
        map.isPitchEnabled = false // framing math assumes a flat, top-down camera
        // Let a pinch go as close as the imagery allows (MapKit still stops
        // where Apple's satellite tiles end); the drag loupe covers the rest.
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: HoleMapLoupe.closestDistance)
        context.coordinator.install(on: map)
        return map
    }

    func updateUIView(_ map: HoleMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.sync(map)
    }

    static func dismantleUIView(_ map: HoleMapView, coordinator: HoleMapCoordinator) {
        coordinator.uninstall(from: map)
    }
}

/// MKMapView that reports size changes: SwiftUI does not call `updateUIView`
/// when only the frame changes (first layout, fold/unfold), and the hole must
/// be re-fitted to the new bounds.
final class HoleMapView: MKMapView {
    var onBoundsChange: ((MKMapView) -> Void)?
    private var lastLaidOutSize: CGSize = .zero
    /// Shown while a pin is dragged.
    private(set) lazy var loupe: HoleMapLoupe = {
        let loupe = HoleMapLoupe()
        addSubview(loupe)
        return loupe
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLaidOutSize else { return }
        lastLaidOutSize = bounds.size
        onBoundsChange?(self)
    }
}

/// Precision loupe for dragging a pin: a circle above the finger showing the
/// spot under the pin magnified, with a crosshair on the exact point, so the
/// finger never hides where the pin will land.
final class HoleMapLoupe: UIView {
    static let size: CGFloat = 128
    /// Times closer than the main map.
    static let magnification: Double = 3
    /// Camera distance floor (metres) for both maps.
    static let closestDistance: CLLocationDistance = 20
    /// Gap between the pin and the loupe's edge.
    static let lift: CGFloat = 56

    private let map = MKMapView()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isHidden = true
        isUserInteractionEnabled = false
        layer.cornerRadius = Self.size / 2
        layer.borderWidth = 3
        layer.borderColor = HoleMapColors.paper.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        map.frame = bounds
        map.layer.cornerRadius = Self.size / 2
        map.clipsToBounds = true
        map.preferredConfiguration = MKImageryMapConfiguration()
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: Self.closestDistance)
        addSubview(map)

        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)).cgPath
        ring.fillColor = nil
        ring.strokeColor = HoleMapColors.ink.cgColor
        ring.lineWidth = 1.5
        layer.addSublayer(ring)

        let cross = CAShapeLayer()
        let mid = Self.size / 2, arm: CGFloat = 10, gap: CGFloat = 3
        let path = UIBezierPath()
        path.move(to: CGPoint(x: mid - arm, y: mid)); path.addLine(to: CGPoint(x: mid - gap, y: mid))
        path.move(to: CGPoint(x: mid + gap, y: mid)); path.addLine(to: CGPoint(x: mid + arm, y: mid))
        path.move(to: CGPoint(x: mid, y: mid - arm)); path.addLine(to: CGPoint(x: mid, y: mid - gap))
        path.move(to: CGPoint(x: mid, y: mid + gap)); path.addLine(to: CGPoint(x: mid, y: mid + arm))
        cross.path = path.cgPath
        cross.strokeColor = HoleMapColors.flag.cgColor
        cross.lineWidth = 2
        layer.addSublayer(cross)
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Centre of the loupe for a pin at `pin` in a view of `bounds`: above
    /// the pin, or below it when there is no room above; kept inside.
    static func position(for pin: CGPoint, in bounds: CGRect) -> CGPoint {
        let half = size / 2
        let above = pin.y - lift - half
        let y = above - half >= bounds.minY + 8 ? above : pin.y + lift + half
        let x = min(max(pin.x, bounds.minX + half + 8), bounds.maxX - half - 8)
        return CGPoint(x: x, y: y)
    }

    /// Shows the loupe over `point` of `host`, looking at what is there.
    func show(at point: CGPoint, in host: MKMapView) {
        let coordinate = host.convert(point, toCoordinateFrom: host)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        center = Self.position(for: point, in: host.bounds)
        map.camera = MKMapCamera(
            lookingAtCenter: coordinate,
            fromDistance: max(Self.closestDistance, host.camera.centerCoordinateDistance / Self.magnification),
            pitch: 0, heading: host.camera.heading)
        if isHidden {
            superview?.bringSubviewToFront(self)
            isHidden = false
        }
    }

    func hide() { isHidden = true }
}

