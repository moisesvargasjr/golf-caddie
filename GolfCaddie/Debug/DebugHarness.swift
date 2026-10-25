#if DEBUG
import CoreLocation
import Foundation

/// Headless on-device test harness, driven entirely by launch arguments so it
/// is inert on a normal launch (and excluded from Release/TestFlight via the
/// DEBUG guard). Lets the dev machine exercise the live auto-log pipeline —
/// breadcrumb fusion + step-gated reconciliation → `.watchAuto` shots — without
/// a real watch swing, by injecting synthetic SwingEvents through the SAME
/// LiveShotCoordinator path the watch uses.
///
/// Invoked via Xcode 27 `devicectl`:
///   devicectl device process launch -d <iphone> com.moisesvargasjr.golfcaddie \
///     -DebugStartRound 1 -DebugInjectSwings 3 -DebugInjectGap 1.0 -DebugClub 7i
///     [-DebugClubsLeftOut threeWood,lobWedge]
///   devicectl device simulate location coordinate -d <iphone> --latitude .. --longitude ..
/// then pull golfcaddie.sqlite and inspect the shot rows.
///
/// Launch-arg keys are read straight from UserDefaults (NSUserDefaults maps
/// `-Key Value` launch arguments automatically).
enum DebugHarness {
    /// `-DebugOpen review|card|roundcard|review-round|bag|course|logbook|settings|home|casual|casual-finish`
    /// — opens one screen on launch so simulator screenshots don't need taps.
    /// `card` is the live round's scorecard (with `-DebugStartRound 1`; add
    /// `-DebugStartHole 7` for ADD holes); `roundcard` is a finished round's
    /// card from Home (seeds one if there is none; see `DebugScorecardSeed`);
    /// `review-round` opens that round's review on the map, on hole
    /// `-DebugReviewHole N` (default: its first hole). `home` lands on Home
    /// itself (the idle screen) with a seeded bag, so a fresh simulator skips
    /// Bag Setup.
    static var openScreen: String? { UserDefaults.standard.string(forKey: "DebugOpen") }

    /// `-DebugOpen casual` (or `casual-finish`, which also opens the score
    /// grid): launch straight into a casual round.
    static var opensCasual: Bool { openScreen?.hasPrefix("casual") ?? false }

    /// The canvas round (Casual boards): par, strokes, putts for holes 1–7.
    static let casualSample: [(par: Int, strokes: Int, putts: Int)] = [
        (4, 4, 2), (5, 6, 2), (3, 3, 1), (4, 5, 2), (4, 4, 2), (3, 4, 2), (4, 5, 2),
    ]
    /// Par for the live hole after the sample (canvas hole 8).
    static let casualLivePar = 4

    /// `-DebugSeedBag 1` (or any harness flag): save the recommended bag when
    /// none is saved. Idempotent; RootView calls it before loading the bag.
    static func seedBagIfRequested() {
        let d = UserDefaults.standard
        let requested = d.bool(forKey: "DebugSeedBag") || d.bool(forKey: "DebugStartRound")
            || d.integer(forKey: "DebugInjectSwings") > 0 || opensCasual || openScreen == "home"
        guard requested else { return }
        if (try? ClubConfigurationRepository.load().bag.isEmpty) ?? true {
            try? ClubConfigurationRepository.save(ClubConfiguration.recommendedDefault)
        }
    }

    @MainActor
    static func runIfRequested(controller: RoundController, location: LocationManager) {
        let d = UserDefaults.standard
        let count = d.integer(forKey: "DebugInjectSwings")
        let startRound = d.bool(forKey: "DebugStartRound")
        let seedBag = d.bool(forKey: "DebugSeedBag")
        if opensCasual {
            seedBagIfRequested()
            startCasualRound(controller: controller)
        }
        guard startRound || count > 0 || seedBag else { return }

        NSLog("[DebugHarness] start (startRound=\(startRound) injectSwings=\(count))")
        // A fresh simulator has no saved bag, which gates the UI on Bag Setup.
        // Seed the recommended default so Home / the active round render.
        seedBagIfRequested()
        // `-DebugFreshRound 1`: end a round restored from an earlier run first,
        // so UI tests always start on a fresh tracking hole.
        if startRound, d.bool(forKey: "DebugFreshRound"), controller.isActive {
            try? controller.endRound()
            controller.clearMostRecentlyEndedRound()
        }
        if startRound, !controller.isActive {
            let startHole = d.integer(forKey: "DebugStartHole")
            // Comma-separated bag ids left home, e.g. -DebugClubsLeftOut threeWood,lobWedge
            let leftOut = (d.string(forKey: "DebugClubsLeftOut") ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            try? controller.startRound(startingHole: startHole > 0 ? startHole : 1,
                                       clubsLeftOut: leftOut)
        }
        guard count > 0 else { return }

        let gap = d.double(forKey: "DebugInjectGap") > 0 ? d.double(forKey: "DebugInjectGap") : 1.0
        let club = d.string(forKey: "DebugClub") ?? "7i"
        // Wait for a (simulated) breadcrumb so fusion has something to match.
        waitForBreadcrumb(controller: controller) {
            injectSequence(count: count, gap: gap, club: club)
        }
    }

    /// `-DebugOpen casual`: a casual round with the first holes already
    /// scored (`-DebugCasualHoles N`, default 4, max 7) so the round-so-far
    /// list has content. An active round is switched to casual instead.
    @MainActor
    private static func startCasualRound(controller: RoundController) {
        if controller.isActive {
            if !controller.isCasualMode { controller.setCasualMode(true) }
            return
        }
        let d = UserDefaults.standard
        let requested = d.object(forKey: "DebugCasualHoles") == nil ? 4 : d.integer(forKey: "DebugCasualHoles")
        let holes = min(max(requested, 0), casualSample.count)
        do {
            try controller.startRound(startingHole: 1, mode: .casual)
            for sample in casualSample.prefix(holes) {
                try controller.setHandScoreOnCurrentHole(strokes: sample.strokes, putts: sample.putts)
                try controller.confirmHoleAndAdvance(par: sample.par)
            }
            let livePar = holes < casualSample.count ? casualSample[holes].par : casualLivePar
            if let hole = controller.currentHole { try controller.setPar(livePar, forHole: hole.id) }
            NSLog("[DebugHarness] casual round started, \(holes) holes pre-scored")
        } catch {
            NSLog("[DebugHarness] casual round failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func waitForBreadcrumb(controller: RoundController, attempts: Int = 0,
                                          _ done: @escaping () -> Void) {
        let roundID = controller.currentRound?.id
        let n = roundID.flatMap { try? TracePointRepository.count(forRound: $0) } ?? 0
        if n > 0 || attempts >= 40 {
            NSLog("[DebugHarness] breadcrumbs=\(n) after \(attempts) polls; injecting")
            done()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            waitForBreadcrumb(controller: controller, attempts: attempts + 1, done)
        }
    }

    @MainActor
    private static func injectSequence(count: Int, gap: Double, club: String) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) {
                let event = SwingEvent(
                    id: UUID(),
                    watchWallClock: Date().timeIntervalSince1970,
                    watchUptime: ProcessInfo.processInfo.systemUptime,
                    club: club,
                    confidence: 0.9,
                    source: .auto,
                    impactPeakG: 12,
                    arcGyro: 20
                )
                LiveShotCoordinator.shared.receive(.swing(event))
                NSLog("[DebugHarness] injected swing \(i + 1)/\(count) club=\(club)")
            }
        }
    }
}
#endif
