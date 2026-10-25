import CoreLocation
import Foundation
import Observation

/// Commands the screen sends to the map (the live `HoleMap` coordinator).
@MainActor
protocol HoleMapDriving: AnyObject {
    func holeMapResetToHoleUp(animated: Bool)
    func holeMapSelectHole(_ number: Int, animated: Bool)
    func holeMapShowWholeCourse(animated: Bool)
}

/// The screen's handle on its `HoleMap`: imperative camera moves (compass
/// reset, course-mode hole glide) and what the map reports back (heading,
/// whether it is still auto-framing). Hold one per screen (`@State`) and pass
/// it to `HoleMap`; it survives the map moving between layouts.
@Observable
@MainActor
final class HoleMapController {
    /// Current camera heading (degrees, 0 = north up).
    private(set) var heading: CLLocationDirection = 0
    /// The heading that puts the hole's green straight up (nil = no anchors).
    private(set) var holeUpHeading: CLLocationDirection?
    /// True while the map frames the hole itself (follows "you" on the live
    /// hole, re-fits when the controls show/hide). A manual pan, zoom or
    /// rotate turns it off; `resetToHoleUp` turns it back on.
    private(set) var isAutoFraming = true
    /// Course mode: the hole the camera glided to (nil = whole course).
    private(set) var selectedHole: Int?

    /// Set by the map when it appears. Commands sent before then are kept as
    /// state (`selectedHole`) and applied when it attaches.
    @ObservationIgnored weak var driver: (any HoleMapDriving)?

    init() {}

    /// Degrees the map is turned away from hole-up, in (-180, 180]. Positive
    /// = the camera turned clockwise (the hole appears turned anticlockwise).
    var rotationFromHoleUp: Double {
        HoleFraming.rotation(from: holeUpHeading ?? 0, to: heading)
    }

    /// Within a degree of hole-up (the compass button can show "settled").
    var isHoleUp: Bool { abs(rotationFromHoleUp) < 1 }

    // MARK: Commands

    /// Compass button: turn back to hole-up and re-frame the hole.
    func resetToHoleUp(animated: Bool = true) {
        isAutoFraming = true
        driver?.holeMapResetToHoleUp(animated: animated)
    }

    /// Course mode: glide the camera to hole `number`'s bounds.
    func selectHole(_ number: Int, animated: Bool = true) {
        selectedHole = number
        isAutoFraming = true
        driver?.holeMapSelectHole(number, animated: animated)
    }

    /// Course mode: glide back out to the whole course ("COURSE MAP").
    func showWholeCourse(animated: Bool = true) {
        selectedHole = nil
        isAutoFraming = true
        driver?.holeMapShowWholeCourse(animated: animated)
    }

    // MARK: Map → controller (called by the HoleMap coordinator)

    func mapDidRotate(to newHeading: CLLocationDirection) {
        let next = HoleFraming.normalizedHeading(newHeading)
        // Small jitter during a pinch is not worth a SwiftUI update.
        guard abs(HoleFraming.rotation(from: heading, to: next)) >= 0.25 else { return }
        heading = next
    }

    func mapDidUpdateHoleUp(_ newHoleUp: CLLocationDirection?) {
        guard newHoleUp != holeUpHeading else { return }
        holeUpHeading = newHoleUp
    }

    func mapDidStopAutoFraming() {
        guard isAutoFraming else { return }
        isAutoFraming = false
    }

    func mapDidStartAutoFraming() {
        guard !isAutoFraming else { return }
        isAutoFraming = true
    }
}
