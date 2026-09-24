import CoreLocation
@testable import GolfCaddie
import GRDB
import XCTest

/// `transferUserInfo` queues while the phone is unreachable; on reconnect whole
/// holes of watch traffic land within seconds. These pin that a late burst is
/// applied as it was played: swings on their own hole, late taps at their own
/// time and place.
@MainActor
final class WatchReplayOrderingTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDown() {
        TestDatabase.restore()
        queue = nil
    }

    /// Always "walked": never collapses two swings (the pedometer's fail-safe).
    private struct Walked: StepCounting {
        func steps(from: Date, to: Date) async -> Int { .max }
    }

    private func swing(at time: Date, club: String? = "7i") -> WatchToPhoneMessage {
        .swing(SwingEvent(
            id: UUID(), watchWallClock: time.timeIntervalSince1970, watchUptime: 0, club: club,
            confidence: 1, source: .auto, impactPeakG: 12, arcGyro: 6))
    }

    private func shots(onHole number: Int, of controller: RoundController) throws -> [Shot] {
        let round = try XCTUnwrap(controller.currentRound)
        let hole = try XCTUnwrap(try HoleRepository.holesForRound(round.id).first { $0.holeNumber == number })
        return try ShotRepository.shotsForHole(hole.id)
    }

    /// The bug: every queued Next Hole applied immediately while the swings sat
    /// in the debounce buffer, so all swings were logged to the LAST hole.
    func testLateBurstKeepsSwingsOnTheHoleTheyWerePlayed() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        // A long debounce: only the hole-change flush can commit the early swings.
        let coordinator = LiveShotCoordinator(steps: Walked(), debounceInterval: 0.3)
        coordinator.attach(controller: controller, location: location)

        let t0 = Date().addingTimeInterval(-3600)
        // Hole 1: drive, approach, two putts, Next Hole. Hole 2: tee shot, a putt.
        coordinator.ingest(swing(at: t0, club: "Dr"))
        coordinator.ingest(swing(at: t0.addingTimeInterval(300)))
        coordinator.ingest(.command(.puttPlusOne, sentAt: t0.addingTimeInterval(500)))
        coordinator.ingest(.command(.puttPlusOne, sentAt: t0.addingTimeInterval(520)))
        coordinator.ingest(.command(.advanceHole, sentAt: t0.addingTimeInterval(560)))
        coordinator.ingest(swing(at: t0.addingTimeInterval(700)))
        coordinator.ingest(.command(.puttPlusOne, sentAt: t0.addingTimeInterval(900)))

        try await Task.sleep(nanoseconds: 600_000_000) // let the trailing debounce fire
        await coordinator.waitUntilIdle()

        let first = try shots(onHole: 1, of: controller)
        let second = try shots(onHole: 2, of: controller)
        XCTAssertEqual(first.filter { !$0.isPutt }.count, 2, "both hole-1 swings stay on hole 1")
        XCTAssertEqual(first.filter(\.isPutt).count, 2)
        XCTAssertEqual(second.filter { !$0.isPutt }.count, 1, "the hole-2 swing lands on hole 2")
        XCTAssertEqual(second.filter(\.isPutt).count, 1, "a putt queued behind the advance lands on hole 2")
        XCTAssertEqual(controller.currentHole?.holeNumber, 2)
    }

    /// A late tap is stamped when it happened, and never gets the phone's
    /// current position (there's no breadcrumb from then in this test → no GPS).
    func testLatePuttKeepsItsOwnTimeAndNoWrongLocation() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator(steps: Walked(), debounceInterval: 0.05)
        coordinator.attach(controller: controller, location: location)

        let tapped = Date().addingTimeInterval(-1800)
        coordinator.ingest(.command(.puttPlusOne, sentAt: tapped))
        await coordinator.waitUntilIdle()

        let putt = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(putt.timestamp.timeIntervalSince1970, tapped.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(putt.latitude)
    }

    /// Live behaviour is unchanged: a fresh tap is "now", applied synchronously.
    func testLiveTapStillAppliesImmediately() throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator(steps: Walked())
        coordinator.attach(controller: controller, location: location)

        coordinator.ingest(.command(.puttPlusOne))
        let putt = try XCTUnwrap(controller.currentHoleShots.last, "applied before ingest returns")
        XCTAssertEqual(putt.timestamp.timeIntervalSinceNow, 0, accuracy: 5)

        // An old watch build sends no sentAt → treated as live.
        coordinator.ingest(.command(.puttPlusOne, sentAt: nil))
        XCTAssertEqual(controller.currentHoleShots.count, 2)
    }

    /// The exact device path for a watch MARK: encoded on the watch, decoded by
    /// the WC delegate, handed to `receive` (a background thread → main).
    func testMarkFromTheWatchLogsAShotThroughReceive() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator(steps: Walked())
        coordinator.attach(controller: controller, location: location)

        let wire = try WatchToPhoneMessage.command(.addShot(clubShortName: nil)).encoded()
        let decoded = try WatchToPhoneMessage.decode(wire)
        await Task.detached { coordinator.receive(decoded) }.value
        try await Task.sleep(nanoseconds: 200_000_000)
        await coordinator.waitUntilIdle()

        XCTAssertEqual(controller.currentHoleShots.count, 1)
        XCTAssertEqual(controller.currentHoleShots.first?.source, .watchManual)
    }

    // MARK: - Watch penalties

    func testWatchPenaltyKindsMatchThePhonePenaltyTypes() {
        XCTAssertEqual(Set(WatchPenaltyKind.allCases.map(\.rawValue)), Set(PenaltyType.allCases.map(\.rawValue)))
    }

    func testWatchPenaltyAddsAStrokeOnceAndUndoRemovesIt() throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator(steps: Walked())
        coordinator.attach(controller: controller, location: location)

        let penalty = WatchToPhoneMessage.command(.addPenalty(kind: WatchPenaltyKind.water.rawValue))
        let wire = try WatchToPhoneMessage.decode(penalty.encoded())
        coordinator.ingest(wire)
        coordinator.ingest(wire) // at-least-once redelivery
        XCTAssertEqual(controller.currentHolePenalties.map(\.type), [.water])
        XCTAssertEqual(controller.currentHolePenaltyStrokes, 1)

        // An unknown kind (mismatched builds) still costs a stroke.
        coordinator.ingest(.command(.addPenalty(kind: "meteor")))
        XCTAssertEqual(controller.currentHolePenalties.last?.type, .other)

        // The watch's UNDO is "remove the newest shot or penalty".
        coordinator.ingest(.command(.removeStroke(id: nil)))
        XCTAssertEqual(controller.currentHolePenalties.map(\.type), [.water])
    }

    /// A penalty queued behind a Next Hole lands on the new hole, and a late one
    /// keeps the time it was tapped.
    func testLatePenaltyKeepsItsHoleAndTime() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        let coordinator = LiveShotCoordinator(steps: Walked(), debounceInterval: 0.3)
        coordinator.attach(controller: controller, location: location)

        let t0 = Date().addingTimeInterval(-3600)
        coordinator.ingest(swing(at: t0, club: "Dr"))
        coordinator.ingest(.command(.addPenalty(kind: "obOrLost"), sentAt: t0.addingTimeInterval(60)))
        coordinator.ingest(.command(.advanceHole, sentAt: t0.addingTimeInterval(600)))
        coordinator.ingest(.command(.addPenalty(kind: "water"), sentAt: t0.addingTimeInterval(900)))
        await coordinator.waitUntilIdle()

        let round = try XCTUnwrap(controller.currentRound)
        let holes = try HoleRepository.holesForRound(round.id)
        let first = try XCTUnwrap(holes.first { $0.holeNumber == 1 })
        let second = try XCTUnwrap(holes.first { $0.holeNumber == 2 })
        XCTAssertEqual(try PenaltyRepository.penaltiesForHole(first.id).map(\.type), [.obOrLost])
        let late = try XCTUnwrap(try PenaltyRepository.penaltiesForHole(second.id).first)
        XCTAssertEqual(late.type, .water)
        XCTAssertEqual(late.timestamp.timeIntervalSince1970, t0.addingTimeInterval(900).timeIntervalSince1970, accuracy: 1)
    }

    func testSentAtIsOptionalOnTheWire() throws {
        let legacy = Data(#"{"kind":"command","command":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","command":{"puttPlusOne":{}}}}"#.utf8)
        let decoded = try WatchToPhoneMessage.decode(legacy)
        XCTAssertNil(decoded.command?.sentAt)
        XCTAssertEqual(decoded.command?.command, .puttPlusOne)
    }
}
