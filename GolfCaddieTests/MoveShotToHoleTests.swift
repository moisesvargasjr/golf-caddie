import GRDB
import XCTest
@testable import GolfCaddie

/// `ShotRepository.moveToHole` — refiling a stroke logged on the wrong hole
/// (the phone slipped back to hole 9 and filed hole 10 swings under it).
final class MoveShotToHoleTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func assertContiguousAndTimeOrdered(_ shots: [Shot], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(shots.map(\.sequenceNumber), Array(1..<(shots.count + 1)),
                       "sequence numbers not contiguous", file: file, line: line)
        XCTAssertEqual(shots.map(\.timestamp), shots.map(\.timestamp).sorted(),
                       "strokes not in time order", file: file, line: line)
    }

    func testMoveKeepsBothHolesContiguousAndInTimeOrder() throws {
        let round = try TestDatabase.seedRound()
        let h9 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 9)
        let h10 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 10)
        // Hole 9 holds its own three strokes plus a hole-10 swing logged at 14m.
        try TestDatabase.seedShot(holeID: h9.id, sequence: 1, timestamp: at(0))
        try TestDatabase.seedShot(holeID: h9.id, sequence: 2, timestamp: at(3))
        let misfiled = try TestDatabase.seedShot(
            holeID: h9.id, sequence: 3, lat: 30.1, lng: -97.2, club: "7i", timestamp: at(14))
        try TestDatabase.seedShot(holeID: h9.id, sequence: 4, timestamp: at(6))
        // Hole 10 strokes on either side of it.
        try TestDatabase.seedShot(holeID: h10.id, sequence: 1, timestamp: at(12))
        try TestDatabase.seedShot(holeID: h10.id, sequence: 2, timestamp: at(17))

        let target = try ShotRepository.moveToHole(misfiled, holeNumber: 10)
        XCTAssertEqual(target.id, h10.id)

        let nine = try ShotRepository.shotsForHole(h9.id)
        XCTAssertEqual(nine.count, 3)
        XCTAssertEqual(nine.map(\.sequenceNumber), [1, 2, 3])

        let ten = try ShotRepository.shotsForHole(h10.id)
        XCTAssertEqual(ten.map(\.sequenceNumber), [1, 2, 3])
        assertContiguousAndTimeOrdered(ten)
        let moved = try XCTUnwrap(ten.first { $0.id == misfiled.id })
        XCTAssertEqual(moved.sequenceNumber, 2)
        // Location, club, source, timestamp unchanged.
        XCTAssertEqual(moved.latitude, 30.1)
        XCTAssertEqual(moved.longitude, -97.2)
        XCTAssertEqual(moved.club, "7i")
        XCTAssertEqual(moved.source, misfiled.source)
        XCTAssertEqual(moved.timestamp, misfiled.timestamp)
    }

    func testMoveFiveStrokesBuildsHoleInTimeOrder() throws {
        let round = try TestDatabase.seedRound()
        let h9 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 9)
        let h10 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 10)
        for i in 1...4 { try TestDatabase.seedShot(holeID: h9.id, sequence: i, timestamp: at(Double(i))) }
        let misfiled = try (1...5).map {
            try TestDatabase.seedShot(holeID: h9.id, sequence: 4 + $0, timestamp: at(10 + Double($0)))
        }
        // Move out of order to prove placement is by time, not by move order.
        for shot in misfiled.reversed() { try ShotRepository.moveToHole(shot, holeNumber: 10) }

        assertContiguousAndTimeOrdered(try ShotRepository.shotsForHole(h9.id))
        let ten = try ShotRepository.shotsForHole(h10.id)
        XCTAssertEqual(ten.map(\.id), misfiled.map(\.id))
        assertContiguousAndTimeOrdered(ten)
    }

    func testMoveIntoUnvisitedHoleCreatesIt() throws {
        let round = try TestDatabase.seedRound()
        let h9 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 9)
        try TestDatabase.seedShot(holeID: h9.id, sequence: 1, timestamp: at(0))
        let misfiled = try TestDatabase.seedShot(holeID: h9.id, sequence: 2, timestamp: at(12))
        XCTAssertNil(try HoleRepository.hole(forRound: round.id, number: 10))

        let target = try ShotRepository.moveToHole(misfiled, holeNumber: 10)

        let created = try XCTUnwrap(HoleRepository.hole(forRound: round.id, number: 10))
        XCTAssertEqual(created.id, target.id)
        XCTAssertNil(created.par)
        XCTAssertNil(created.confirmedAt)
        XCTAssertEqual(try ShotRepository.shotsForHole(created.id).map(\.id), [misfiled.id])
        XCTAssertEqual(try ShotRepository.shotsForHole(created.id).first?.sequenceNumber, 1)
        XCTAssertEqual(try ShotRepository.shotsForHole(h9.id).map(\.sequenceNumber), [1])
        // A second move to the same hole reuses the row, never duplicates it.
        let other = try TestDatabase.seedShot(holeID: h9.id, sequence: 2, timestamp: at(15))
        try ShotRepository.moveToHole(other, holeNumber: 10)
        XCTAssertEqual(try HoleRepository.holesForRound(round.id).filter { $0.holeNumber == 10 }.count, 1)
    }

    func testMoveOffAndBackRestoresOriginalPlacement() throws {
        let round = try TestDatabase.seedRound()
        let h9 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 9)
        let h10 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 10)
        for i in 1...5 { try TestDatabase.seedShot(holeID: h9.id, sequence: i, timestamp: at(Double(i))) }
        for i in 1...3 { try TestDatabase.seedShot(holeID: h10.id, sequence: i, timestamp: at(20 + Double(i))) }
        let before9 = try ShotRepository.shotsForHole(h9.id)
        let before10 = try ShotRepository.shotsForHole(h10.id)
        let stroke = before9[2]

        try ShotRepository.moveToHole(stroke, holeNumber: 10)
        let moved = try XCTUnwrap(ShotRepository.shotsForHole(h10.id).first { $0.id == stroke.id })
        try ShotRepository.moveToHole(moved, holeNumber: 9)

        XCTAssertEqual(try ShotRepository.shotsForHole(h9.id), before9)
        XCTAssertEqual(try ShotRepository.shotsForHole(h10.id), before10)
    }

    func testMoveToSameHoleIsNoOp() throws {
        let round = try TestDatabase.seedRound()
        let h9 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 9)
        let a = try TestDatabase.seedShot(holeID: h9.id, sequence: 1, timestamp: at(0))
        try TestDatabase.seedShot(holeID: h9.id, sequence: 2, timestamp: at(1))
        let before = try ShotRepository.shotsForHole(h9.id)
        XCTAssertEqual(try ShotRepository.moveToHole(a, holeNumber: 9).id, h9.id)
        XCTAssertEqual(try ShotRepository.shotsForHole(h9.id), before)
    }
}
