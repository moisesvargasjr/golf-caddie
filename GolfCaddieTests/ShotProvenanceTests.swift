import GRDB
import XCTest
@testable import GolfCaddie

/// B3 — honest shot provenance + model fields. Verifies the v4 migration adds
/// the columns, that the new fields/sources round-trip through GRDB, and that
/// each watch/phone entry point tags `source`/`isPutt` truthfully.
final class ShotProvenanceTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    // MARK: - Migration + persistence

    func testV4AddsPuttAndConfidenceColumns() throws {
        let columns = try queue.read { db in try db.columns(in: "shot").map(\.name) }
        XCTAssertTrue(columns.contains("isPutt"))
        XCTAssertTrue(columns.contains("confidence"))
    }

    func testNewFieldsAndSourcesRoundTrip() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let shot = Shot(
            id: UUID(), holeID: hole.id, sequenceNumber: 1, timestamp: Date(),
            latitude: nil, longitude: nil, gpsAccuracy: nil, hadGPS: false,
            club: .putter, source: .reconstructed, notes: nil,
            isPutt: true, confidence: 0.42
        )
        try ShotRepository.insert(shot)

        let fetched = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.source, .reconstructed)
        XCTAssertEqual(fetched.first?.isPutt, true)
        XCTAssertEqual(try XCTUnwrap(fetched.first?.confidence), 0.42, accuracy: 1e-9)
    }

    func testExistingRowsDefaultToNonPuttNilConfidence() throws {
        // seedShot() does not set isPutt/confidence — it must persist the defaults.
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1)
        let fetched = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(fetched.first?.isPutt, false)
        XCTAssertNil(fetched.first?.confidence)
    }

    // MARK: - Entry-point provenance (the actual B3 bug fix)

    @MainActor
    func testWatchManualAddTaggedWatchManual() throws {
        let controller = makeActiveController()
        try controller.addShotFromWatch()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.source, .watchManual, "a deliberate watch tap is not .watchAuto")
        XCTAssertFalse(shot.isPutt)
    }

    @MainActor
    func testWatchPuttTaggedWatchManualPutter() throws {
        let controller = makeActiveController()
        try controller.addPuttFromWatch()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.source, .watchManual)
        XCTAssertEqual(shot.club, .putter)
        XCTAssertTrue(shot.isPutt)
    }

    @MainActor
    func testAutoDetectedShotStaysWatchAuto() throws {
        let controller = makeActiveController()
        try controller.ingestAutoShot(at: nil, accuracy: nil, club: nil, timestamp: Date())
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.source, .watchAuto, "the detector path is unchanged")
        XCTAssertFalse(shot.isPutt)
    }

    @MainActor
    private func makeActiveController() -> RoundController {
        let controller = RoundController(location: LocationManager())
        try? controller.startRound()
        return controller
    }
}
