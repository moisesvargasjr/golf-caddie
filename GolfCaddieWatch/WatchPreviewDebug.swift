#if DEBUG
import Foundation

/// Simulator-only preview seeding. Launch the watch app in a watchOS simulator
/// with `-WatchPreview 1` and it forces the play screens with mock phone state,
/// so the UI/layout can be screenshotted via `simctl io … screenshot` without a
/// paired phone, a workout session, or real motion. Inert otherwise.
enum WatchPreviewDebug {
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "WatchPreview") }
    /// Initial play page for screenshots (0 Yardage / 1 Strokes / 2 Score).
    /// `-WatchPreviewActions 1` opens the Actions page (tag −1; a negative launch
    /// argument value doesn't parse).
    static var initialPage: Int {
        guard isActive else { return 0 }
        if UserDefaults.standard.bool(forKey: "WatchPreviewActions") { return -1 }
        return UserDefaults.standard.integer(forKey: "WatchPreviewPage")
    }
    /// Force the club selector into its armed (crown-active) state for screenshots.
    static var armClub: Bool { isActive && UserDefaults.standard.bool(forKey: "WatchPreviewArmClub") }
    /// `-WatchPreviewFinish 1` opens the Finish Hole sheet at PUTTS?; `2` at the
    /// score confirm (2 putts chosen). Use with `-WatchPreviewActions 1`.
    static var finishStep: Int { isActive ? UserDefaults.standard.integer(forKey: "WatchPreviewFinish") : 0 }
    /// Force the wrist-down (always-on) glance for screenshots.
    static var dim: Bool { isActive && UserDefaults.standard.bool(forKey: "WatchPreviewDim") }

    @MainActor
    static func apply(controller: LiveSessionController) {
        guard isActive else { return }
        // `-WatchPreviewWatchOnly 1`: no phone round (the watch-only layouts).
        if !UserDefaults.standard.bool(forKey: "WatchPreviewWatchOnly") {
            WatchSession.shared.debugSetPhoneState(mockState)
        }
        controller.debugEnterPreview()
    }

    static let mockState = PhoneStateUpdate(
        isActive: true,
        courseName: "Welk Oaks G.C.",
        holeNumber: 3,
        par: 4,
        distanceToGreenYards: 137,
        currentClubShortName: "7i",
        clubEpoch: 1,
        clubs: [
            WatchClub(short: "Dr", name: "Driver", avgYards: 235),
            WatchClub(short: "3W", name: "3 Wood", avgYards: 215),
            WatchClub(short: "5H", name: "5 Hybrid", avgYards: 195),
            WatchClub(short: "5i", name: "5 Iron", avgYards: 175),
            WatchClub(short: "6i", name: "6 Iron", avgYards: 165),
            WatchClub(short: "7i", name: "7 Iron", avgYards: 150),
            WatchClub(short: "8i", name: "8 Iron", avgYards: 138),
            WatchClub(short: "9i", name: "9 Iron", avgYards: 125),
            WatchClub(short: "PW", name: "P. Wedge", avgYards: 110),
            WatchClub(short: "SW", name: "Sand Wedge", avgYards: 80),
            WatchClub(short: "Pt", name: "Putter", avgYards: 12, isPutter: true),
        ],
        strokes: [
            WatchStroke(id: "1", clubShort: "Dr", clubName: "Driver", lie: "Tee", fromYards: 412, time: "2:41", manual: false),
            WatchStroke(id: "2", clubShort: "7i", clubName: "7 Iron", lie: "Fairway", fromYards: 196, time: "2:48", manual: false),
        ],
        scorecard: [
            WatchScoreRow(hole: 1, par: 4, strokes: 5),
            WatchScoreRow(hole: 2, par: 3, strokes: 3),
        ],
        holePenaltyStrokes: 1,
        holeFullShots: 2
    )
}
#endif
