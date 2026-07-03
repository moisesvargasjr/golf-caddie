import GRDB
import XCTest
@testable import GolfCaddie

/// B2 — transport idempotency on watch→phone commands. Covers the pure
/// recently-applied-id set, the wire contract carrying a stable id, and the
/// coordinator applying a redelivered command exactly once.
final class WatchCommandIdempotencyTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    // MARK: - RecentIDSet (the dedup primitive)

    func testRecentIDSetInsertReturnsTrueOnceThenFalse() {
        var set = RecentIDSet()
        let id = UUID()
        XCTAssertTrue(set.insert(id), "first sight of an id is new")
        XCTAssertFalse(set.insert(id), "second sight of the same id is a duplicate")
        XCTAssertTrue(set.contains(id))
    }

    func testRecentIDSetDistinctIDsAreIndependent() {
        var set = RecentIDSet()
        XCTAssertTrue(set.insert(UUID()))
        XCTAssertTrue(set.insert(UUID()))
        XCTAssertTrue(set.insert(UUID()))
    }

    func testRecentIDSetEvictsOldestBeyondCapacity() {
        var set = RecentIDSet(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertTrue(set.insert(a))
        XCTAssertTrue(set.insert(b))
        XCTAssertFalse(set.insert(a), "a is still within capacity")
        XCTAssertTrue(set.insert(c), "c is new and evicts the oldest (a)")
        XCTAssertFalse(set.contains(a), "a was evicted past capacity")
        XCTAssertTrue(set.contains(b))
        XCTAssertTrue(set.contains(c))
        XCTAssertTrue(set.insert(a), "an evicted id is treated as new again")
    }

    // MARK: - Wire contract

    func testCommandCarriesStableIDThroughEncoding() throws {
        let id = UUID()
        let msg = WatchToPhoneMessage.command(.advanceHole, id: id)
        let decoded = try WatchToPhoneMessage.decode(msg.encoded())
        XCTAssertEqual(decoded.kind, .command)
        XCTAssertEqual(decoded.command?.id, id)
        XCTAssertEqual(decoded.command?.command, .advanceHole)
    }

    func testEachCommandSendGetsADistinctID() {
        let a = WatchToPhoneMessage.command(.puttPlusOne)
        let b = WatchToPhoneMessage.command(.puttPlusOne)
        XCTAssertNotNil(a.command?.id)
        XCTAssertNotEqual(a.command?.id, b.command?.id,
                          "two separate user actions are distinct, not deduped")
    }

    func testEditStrokeClubRoundTripsThroughEncoding() throws {
        let id = UUID()
        let msg = WatchToPhoneMessage.command(.editStrokeClub(id: "abc", clubShortName: "Pt"), id: id)
        let decoded = try WatchToPhoneMessage.decode(msg.encoded())
        XCTAssertEqual(decoded.command?.id, id)
        XCTAssertEqual(decoded.command?.command, .editStrokeClub(id: "abc", clubShortName: "Pt"))
    }

    // MARK: - Coordinator end-to-end (re-send same id → one effect)

    @MainActor
    func testDuplicateCommandIDAppliesEffectOnce() throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator()
        coordinator.attach(controller: controller, location: location)

        let id = UUID()
        let command = WatchToPhoneMessage.command(.addShot(clubShortName: "7i"), id: id)
        coordinator.ingest(command)
        coordinator.ingest(command) // at-least-once redelivery of the same command
        XCTAssertEqual(controller.currentHoleShots.count, 1, "duplicate id must not double-log")

        // A genuinely separate tap (fresh id) still applies.
        coordinator.ingest(WatchToPhoneMessage.command(.addShot(clubShortName: "7i")))
        XCTAssertEqual(controller.currentHoleShots.count, 2)
    }

    /// B25 watch club edit end-to-end: applies once per command id, and the
    /// B31 derivation rides along — editing to the putter sets `isPutt`,
    /// editing back to an iron clears it.
    @MainActor
    func testEditStrokeClubAppliesOnceAndDerivesIsPutt() throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator()
        coordinator.attach(controller: controller, location: location)

        coordinator.ingest(WatchToPhoneMessage.command(.addShot(clubShortName: "7i")))
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(shot.club, .sevenIron)
        XCTAssertFalse(shot.isPutt)

        let editID = UUID()
        let edit = WatchToPhoneMessage.command(
            .editStrokeClub(id: shot.id.uuidString, clubShortName: "Pt"), id: editID)
        coordinator.ingest(edit)
        coordinator.ingest(edit) // redelivery of the same command id — no double apply
        XCTAssertEqual(controller.currentHoleShots.count, 1)
        var edited = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(edited.club, .putter)
        XCTAssertTrue(edited.isPutt, "edit to putter derives isPutt (B31)")

        coordinator.ingest(WatchToPhoneMessage.command(
            .editStrokeClub(id: shot.id.uuidString, clubShortName: "7i")))
        edited = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(edited.club, .sevenIron)
        XCTAssertFalse(edited.isPutt, "edit back to an iron clears the stale putt flag")

        // The DB row matches the in-memory list (the publisher reads the list,
        // the reconstructor reads the DB — they must agree).
        let persisted = try XCTUnwrap(try ShotRepository.shotsForHole(edited.holeID).first)
        XCTAssertEqual(persisted.club, .sevenIron)
        XCTAssertFalse(persisted.isPutt)
    }
}
