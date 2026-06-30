import GRDB
import XCTest
@testable import GolfCaddie

/// B8 — the phone Mark/putt path logs from the continuous `latestLocation` track
/// instead of a blocking `captureBestFix` ramp. These exercise the modified
/// `markShotInternal` path (and complete B3's deferred phone-putt `isPutt`
/// coverage, which B8's removal of the 5 s wait makes cheap to test).
final class LiveMarkPathTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    @MainActor
    func testMarkShotLogsButtonShotFromTrack() async throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound()
        try await controller.markShot()

        XCTAssertEqual(controller.currentHoleShots.count, 1)
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.source, .button)
        XCTAssertFalse(shot.isPutt)
        // No live fix in the sim → the shot still logs (graceful, hadGPS=false)
        // rather than stalling on a 5 s GPS ramp.
        XCTAssertFalse(shot.hadGPS)
    }

    @MainActor
    func testMarkPuttTagsPutterPuttFromPhonePath() async throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound()
        try await controller.markPutt()

        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.source, .button)
        XCTAssertEqual(shot.club, .putter)
        XCTAssertTrue(shot.isPutt)
    }

    /// Putts are commonly batch-logged a few rapid taps at a time after the fact
    /// (sink it, then catch up) — so consecutive same-spot putt taps must each
    /// log, with no tap-bounce dedup (field note 2026-06-30).
    @MainActor
    func testRapidPuttTapsEachLog() throws {
        let controller = RoundController(location: LocationManager())
        try controller.startRound()
        try controller.addPuttFromWatch()
        try controller.addPuttFromWatch()
        try controller.addPuttFromWatch()
        XCTAssertEqual(controller.currentHoleShots.count, 3)
        XCTAssertTrue(controller.currentHoleShots.allSatisfy { $0.isPutt })
    }
}
