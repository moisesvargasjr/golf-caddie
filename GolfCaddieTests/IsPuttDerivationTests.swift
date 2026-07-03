import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// B31 — `isPutt` is derived from the club on every write/edit path (the B28
/// family rule at write time: putter ⇒ putt, any other known club ⇒ not a
/// putt). The field bug: putter shots added via the manual-add sheet carried
/// `isPutt = false`, so they displayed as full shots in the hole split (FT6
/// DB scan, 2026-07-02: 4 such rows).
final class IsPuttDerivationTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    // MARK: - The helper itself

    func testDerivedIsPuttTruthTable() {
        XCTAssertTrue(Shot.derivedIsPutt(club: .putter))
        XCTAssertTrue(Shot.derivedIsPutt(club: .putter, explicit: false))
        XCTAssertFalse(Shot.derivedIsPutt(club: .sevenIron, explicit: true),
                       "a known non-putter club clears an explicit flag (B28 rule)")
        XCTAssertTrue(Shot.derivedIsPutt(club: nil, explicit: true),
                      "unknown club keeps the caller's flag")
        XCTAssertFalse(Shot.derivedIsPutt(club: nil, explicit: false))
    }

    // MARK: - Manual-add path (the FT6 offender)

    @MainActor
    func testInsertMissingShotWithPutterFlagsPutt() throws {
        let controller = makeActiveController()
        try controller.insertMissingShot(at: CLLocationCoordinate2D(latitude: 33.02, longitude: -117.06),
                                         club: .putter)
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.source, .manual)
        XCTAssertTrue(shot.isPutt)
    }

    @MainActor
    func testInsertMissingShotWithIronStaysFullShot() throws {
        let controller = makeActiveController()
        try controller.insertMissingShot(at: CLLocationCoordinate2D(latitude: 33.02, longitude: -117.06),
                                         club: .sevenIron)
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertFalse(shot.isPutt)
    }

    // MARK: - Watch add with putter as the carried club

    @MainActor
    func testWatchAddShotWithPutterClubFlagsPutt() throws {
        let controller = makeActiveController()
        controller.setCurrentClub(.putter)
        try controller.addShotFromWatch() // sends isPutt=false today — must derive
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.club, .putter)
        XCTAssertTrue(shot.isPutt)
    }

    @MainActor
    private func makeActiveController() -> RoundController {
        let controller = RoundController(location: LocationManager())
        try? controller.startRound()
        return controller
    }
}
