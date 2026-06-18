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
///   devicectl device simulate location coordinate -d <iphone> --latitude .. --longitude ..
/// then pull golfcaddie.sqlite and inspect the shot rows.
///
/// Launch-arg keys are read straight from UserDefaults (NSUserDefaults maps
/// `-Key Value` launch arguments automatically).
enum DebugHarness {
    @MainActor
    static func runIfRequested(controller: RoundController, location: LocationManager) {
        let d = UserDefaults.standard
        let count = d.integer(forKey: "DebugInjectSwings")
        let startRound = d.bool(forKey: "DebugStartRound")
        let seedBag = d.bool(forKey: "DebugSeedBag")
        guard startRound || count > 0 || seedBag else { return }

        NSLog("[DebugHarness] start (startRound=\(startRound) injectSwings=\(count))")
        // A fresh simulator has no saved bag, which gates the UI on Bag Setup.
        // Seed the recommended default so Home / the active round render.
        if (try? ClubConfigurationRepository.load().bag.isEmpty) ?? true {
            try? ClubConfigurationRepository.save(ClubConfiguration.recommendedDefault)
        }
        if startRound, !controller.isActive {
            let startHole = d.integer(forKey: "DebugStartHole")
            try? controller.startRound(startingHole: startHole > 0 ? startHole : 1)
        }
        guard count > 0 else { return }

        let gap = d.double(forKey: "DebugInjectGap") > 0 ? d.double(forKey: "DebugInjectGap") : 1.0
        let club = d.string(forKey: "DebugClub") ?? "7i"
        // Wait for a (simulated) breadcrumb so fusion has something to match.
        waitForBreadcrumb(controller: controller) {
            injectSequence(count: count, gap: gap, club: club)
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
