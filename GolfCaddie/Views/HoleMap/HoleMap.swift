import CoreLocation
import MapKit
import SwiftUI

/// The one round map (Duo v2, Architecture A): merges `ActiveRoundMap` (live,
/// follows "you", aim line) and `EditableHoleMap` (draggable pins, fixed
/// camera) and adds the course overview. Put ONE of these in the screen's
/// `.roundStageRole(.map)` slot of `AdaptiveRoundLayout`; the layout moves the
/// same `MKMapView` between postures, never rebuilds it.
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
/// Framing: tee and green are fitted into `unobstructedRect` — WINDOW
/// coordinates, as `SafeChrome.unobstructedRect` returns — and re-fitted with
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
    /// Free area for framing, in window coordinates; nil = the whole map.
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLaidOutSize else { return }
        lastLaidOutSize = bounds.size
        onBoundsChange?(self)
    }
}
