import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// Insert-at-coordinate (Duo v2 "hold the map to add a shot"): the new shot is
/// numbered by its position along the hole — nearest segment of the existing
/// located shot sequence, ties to the later slot.
final class ShotInsertOrderingTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let lon = -117.0
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    // A straight hole running north: shots every ~110 m.
    private func coord(_ lat: Double, _ dLon: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon + dLon)
    }

    private func shot(_ seq: Int, _ lat: Double?, putt: Bool = false) -> Shot {
        Shot(id: UUID(), holeID: UUID(), sequenceNumber: seq, timestamp: t0.addingTimeInterval(Double(seq) * 60),
             latitude: lat, longitude: lat == nil ? nil : lon, gpsAccuracy: nil, hadGPS: lat != nil,
             club: nil, source: .button, notes: nil, isPutt: putt)
    }

    private var threeShots: [Shot] { [shot(1, 33.0000), shot(2, 33.0010), shot(3, 33.0020)] }

    // MARK: - Pure ordering

    func testMiddleGoesBetweenItsNeighbours() {
        let pos = ShotInsertOrdering.position(for: coord(33.0015, 0.0001), among: threeShots)
        XCTAssertEqual(pos, 3, "between shot 2 and shot 3")
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0004, -0.0001), among: threeShots), 2)
    }

    func testEndGoesAfterTheLastShot() {
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0026), among: threeShots), 4)
    }

    func testEndWithGreenAnchor() {
        let anchors = HolePathAnchors(tee: nil, green: coord(33.0040))
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0030, 0.0001), among: threeShots,
                                                   anchors: anchors), 4)
    }

    func testStartGoesBeforeTheFirstShotWhenBehindIt() {
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(32.9994), among: threeShots), 1)
    }

    func testStartWithTeeAnchorCatchesAMissedTeeShot() {
        // The tee shot wasn't logged: shots start 110 m up the hole.
        let shots = [shot(1, 33.0010), shot(2, 33.0020)]
        let anchors = HolePathAnchors(tee: coord(33.0000), green: nil)
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0001), among: shots, anchors: anchors), 1)
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0015), among: shots, anchors: anchors), 2)
    }

    func testTieOnAnExistingShotGoesAfterIt() {
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0010), among: threeShots), 3,
                       "dropped exactly on shot 2 → numbered after it")
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0000), among: threeShots), 2,
                       "dropped on the tee shot → after it, never before")
    }

    func testTieBetweenTwoSegmentsGoesToTheLaterSlot() {
        // Equidistant from segment 1→2 and segment 2→3 (beside shot 2).
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0010, 0.0003), among: threeShots), 3)
    }

    func testUnlocatedPuttsStayAfterAShotBeyondTheLastLocatedOne() {
        let shots = [shot(1, 33.0000), shot(2, 33.0010), shot(3, nil, putt: true), shot(4, nil, putt: true)]
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0016), among: shots), 3)
    }

    func testNoLocatedShotsAppends() {
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0), among: []), 1)
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(33.0), among: [shot(1, nil), shot(2, nil)]), 3)
    }

    func testSingleLocatedShotWithoutAnchorsAppends() {
        XCTAssertEqual(ShotInsertOrdering.position(for: coord(32.999), among: [shot(1, 33.0)]), 2)
    }

    func testTimestampsKeepTheHoleInTimeOrder() {
        let shots = threeShots
        let mid = ShotInsertOrdering.timestamp(forPosition: 3, among: shots, now: nil)
        XCTAssertGreaterThan(mid, shots[1].timestamp)
        XCTAssertLessThan(mid, shots[2].timestamp)
        XCTAssertLessThan(ShotInsertOrdering.timestamp(forPosition: 1, among: shots, now: nil), shots[0].timestamp)
        XCTAssertGreaterThan(ShotInsertOrdering.timestamp(forPosition: 4, among: shots, now: nil), shots[2].timestamp)
    }

    // MARK: - Repository insert

    func testRepositoryInsertRenumbersAndSavesManual() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let seeded = try [33.0000, 33.0010, 33.0020].enumerated().map { i, lat in
            try TestDatabase.seedShot(holeID: hole.id, sequence: i + 1, lat: lat, lng: lon,
                                      timestamp: t0.addingTimeInterval(Double(i) * 60))
        }

        let inserted = try ShotRepository.insertShot(at: coord(33.0015), holeID: hole.id, club: nil)

        let shots = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(shots.map(\.sequenceNumber), [1, 2, 3, 4])
        XCTAssertEqual(shots.map(\.id), [seeded[0].id, seeded[1].id, inserted.id, seeded[2].id])
        XCTAssertEqual(inserted.source, .manual)
        XCTAssertEqual(inserted.locationSource, .manual)
        XCTAssertEqual(shots.map(\.timestamp), shots.map(\.timestamp).sorted())
    }

    func testRepositoryInsertsAtStartMiddleAndEnd() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 33.0010, lng: lon, timestamp: t0)
        try TestDatabase.seedShot(holeID: hole.id, sequence: 2, lat: 33.0030, lng: lon,
                                  timestamp: t0.addingTimeInterval(120))
        let anchors = HolePathAnchors(tee: coord(33.0000), green: nil)

        let end = try ShotRepository.insertShot(at: coord(33.0036), holeID: hole.id, club: nil, anchors: anchors)
        let start = try ShotRepository.insertShot(at: coord(33.0002), holeID: hole.id, club: nil, anchors: anchors)
        let middle = try ShotRepository.insertShot(at: coord(33.0020), holeID: hole.id, club: nil, anchors: anchors)

        let order = try ShotRepository.shotsForHole(hole.id)
        XCTAssertEqual(order.map(\.sequenceNumber), [1, 2, 3, 4, 5])
        XCTAssertEqual(order.first?.id, start.id)
        XCTAssertEqual(order[2].id, middle.id)
        XCTAssertEqual(order.last?.id, end.id)
    }
}
