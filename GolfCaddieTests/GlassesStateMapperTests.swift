import CoreLocation
import GRDB
import XCTest
@testable import GolfCaddie

/// Pins the (RoundController, LocationManager, batteryPercent) → GolfState
/// mapping. Tests build `GlassesStateInputs` directly and seed the in-memory
/// DB for the parts the mapper reads (penalties, holes, club bag, anchors,
/// curated course).
@MainActor
final class GlassesStateMapperTests: XCTestCase {

    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    // MARK: - active / idle

    func test_idleInputs_returnsIdleState() {
        let inputs = makeInputs(isActive: false)
        let state = GlassesStateMapper.snapshot(inputs: inputs)
        XCTAssertFalse(state.active)
        XCTAssertNil(state.round)
        XCTAssertNil(state.hole)
    }

    func test_activeInputs_populatesRoundAndHoleDTOs() throws {
        let round = try TestDatabase.seedRound(courseName: "Test Course")
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 5, par: 4)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole
        ))

        XCTAssertTrue(state.active)
        XCTAssertEqual(state.round?.courseName, "Test Course")
        XCTAssertEqual(state.hole?.number, 5)
        XCTAssertEqual(state.hole?.par, 4)
        XCTAssertEqual(state.hole?.shotCount, 0)
        XCTAssertEqual(state.hole?.penalties, 0)
        XCTAssertEqual(state.hole?.score, 0)
    }

    // MARK: - scoring

    func test_holeScore_isShotCountPlusPenaltyStrokes() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1, par: 4)
        let shot = try TestDatabase.seedShot(holeID: hole.id, sequence: 1, club: "driver")
        try TestDatabase.seedPenalty(holeID: hole.id, type: .obOrLost, strokeCount: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole, shots: [shot]
        ))

        XCTAssertEqual(state.hole?.shotCount, 1)
        XCTAssertEqual(state.hole?.penalties, 1)
        XCTAssertEqual(state.hole?.score, 2)
    }

    // MARK: - currentClub + clubs

    func test_currentClub_propagatesShortName() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole, currentClub: seedClub("sevenIron")
        ))

        XCTAssertEqual(state.currentClub, "7i")
    }

    func test_clubs_omittedWhenBagEmpty() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole
        ))

        // No bag seeded — clubs must be nil (not []).
        XCTAssertNil(state.clubs)
    }

    func test_clubs_presentWhenBagSeeded_inBagOrder() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try TestDatabase.seedBag(["driver", "sevenIron", "putter"])

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole
        ))

        XCTAssertEqual(state.clubs, ["Dr", "7i", "Pt"])
    }

    // MARK: - lastShot

    func test_lastShot_isMostRecentSwungClub() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let s1 = try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 0.000, lng: 0, club: "driver")
        let s2 = try TestDatabase.seedShot(holeID: hole.id, sequence: 2, lat: 0.001, lng: 0, club: "sevenIron")

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole, shots: [s1, s2]
        ))

        // lastShot.club is the MOST RECENTLY swung club (the 7i here), not the
        // prior one — and carries no distance (not knowable until the next shot).
        XCTAssertEqual(state.lastShot?.club, "7i")
        XCTAssertEqual(state.lastShot?.sequenceNumber, 2)
    }

    func test_lastShot_singleShotShowsThatClub() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        let s1 = try TestDatabase.seedShot(holeID: hole.id, sequence: 1, lat: 0.000, lng: 0, club: "driver")

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole, shots: [s1]
        ))

        XCTAssertEqual(state.lastShot?.club, "Dr")
        XCTAssertEqual(state.lastShot?.sequenceNumber, 1)
    }

    // MARK: - GPS

    func test_gps_staleTrue_whenLocationUnavailable() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            locationUnavailable: true
        ))

        XCTAssertEqual(state.gps?.stale, true)
    }

    func test_gps_staleTrue_whenLastReceivedOlderThan30s() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            latestLocation: makeLocation(accuracy: 5),
            lastLocationReceivedAt: Date().addingTimeInterval(-60)
        ))

        XCTAssertEqual(state.gps?.stale, true)
    }

    func test_gps_staleFalse_whenRecentFix() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            latestLocation: makeLocation(accuracy: 5),
            lastLocationReceivedAt: Date()
        ))

        XCTAssertEqual(state.gps?.stale, false)
        XCTAssertEqual(state.gps?.accuracyMeters, 5)
    }

    func test_gps_accuracyNil_whenNegative() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            latestLocation: makeLocation(accuracy: -1),
            lastLocationReceivedAt: Date()
        ))

        XCTAssertNil(state.gps?.accuracyMeters)
    }

    func test_gps_staleTrue_whenLastReceivedNil() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            latestLocation: makeLocation(accuracy: 5),
            lastLocationReceivedAt: nil
        ))

        XCTAssertEqual(state.gps?.stale, true)
    }

    // MARK: - distanceToGreen

    func test_distanceToGreen_nilWhenNoCuratedCourseId() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            curatedCourseId: nil,
            latestLocation: makeLocation(accuracy: 5)
        ))

        XCTAssertNil(state.hole?.distanceToGreenYards)
    }

    func test_distanceToGreen_usesLocalAnchorOverCurated() throws {
        // Curated says green is at (0.001, 0) ~= 111 m north of tee.
        // Local anchor says green is at (0.002, 0) ~= 222 m north of tee.
        // Local must win.
        let courseId = "test-course"
        try TestDatabase.seedCuratedCourse(
            id: courseId,
            holes: [CuratedHole(
                number: 1,
                par: 4,
                yards: nil,
                strokeIndex: nil,
                teeAnchor: nil,
                greenAnchor: GeoPoint(lat: 0.001, lng: 0)
            )]
        )
        try TestDatabase.seedLocalAnchor(
            courseId: courseId,
            holeNumber: 1,
            green: GeoPoint(lat: 0.002, lng: 0)
        )

        let round = try TestDatabase.seedRound(curatedCourseId: courseId)
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            curatedCourseId: courseId,
            latestLocation: makeLocation(lat: 0, lng: 0, accuracy: 5),
            lastLocationReceivedAt: Date()
        ))

        // 0.002° lat ≈ 222 m ≈ 243 yards. Local anchor (222 m) wins over curated (111 m).
        let yards = state.hole?.distanceToGreenYards
        XCTAssertNotNil(yards)
        XCTAssertEqual(yards!, 243, accuracy: 3)
    }

    func test_distanceToGreen_fallsBackToCurated_whenNoLocalAnchor() throws {
        let courseId = "test-course"
        try TestDatabase.seedCuratedCourse(
            id: courseId,
            holes: [CuratedHole(
                number: 1, par: 4, yards: nil, strokeIndex: nil,
                teeAnchor: nil,
                greenAnchor: GeoPoint(lat: 0.001, lng: 0)
            )]
        )

        let round = try TestDatabase.seedRound(curatedCourseId: courseId)
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole,
            curatedCourseId: courseId,
            latestLocation: makeLocation(lat: 0, lng: 0, accuracy: 5),
            lastLocationReceivedAt: Date()
        ))

        let yards = state.hole?.distanceToGreenYards
        XCTAssertNotNil(yards)
        XCTAssertEqual(yards!, 121, accuracy: 2)
    }

    // MARK: - holes / scoring summary

    func test_holes_trimsTrailingEmptyUnconfirmedHole() throws {
        let round = try TestDatabase.seedRound()
        let h1 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1, par: 4, confirmedAt: Date())
        try TestDatabase.seedShot(holeID: h1.id, sequence: 1, club: "driver")
        // Trailing unconfirmed hole with no shots/penalties — should be trimmed.
        _ = try TestDatabase.seedHole(roundID: round.id, holeNumber: 2)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: h1
        ))

        XCTAssertEqual(state.holes?.count, 1)
        XCTAssertEqual(state.holes?.first?.number, 1)
    }

    func test_holes_keepsTrailingHoleThatHasShots() throws {
        let round = try TestDatabase.seedRound()
        let h1 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1, par: 4, confirmedAt: Date())
        try TestDatabase.seedShot(holeID: h1.id, sequence: 1, club: "driver")
        let h2 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 2)
        try TestDatabase.seedShot(holeID: h2.id, sequence: 1, club: "driver")

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: h2
        ))

        XCTAssertEqual(state.holes?.count, 2)
    }

    func test_scoring_aggregatesOnlyConfirmedHoles() throws {
        let round = try TestDatabase.seedRound()
        let h1 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1, par: 4, confirmedAt: Date())
        try TestDatabase.seedShot(holeID: h1.id, sequence: 1, club: "driver")
        try TestDatabase.seedShot(holeID: h1.id, sequence: 2, club: "putter")
        let h2 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 2, par: 3, confirmedAt: Date())
        try TestDatabase.seedShot(holeID: h2.id, sequence: 1, club: "nineIron")
        try TestDatabase.seedShot(holeID: h2.id, sequence: 2, club: "putter")
        try TestDatabase.seedShot(holeID: h2.id, sequence: 3, club: "putter")
        // Trailing unconfirmed hole-in-progress with shots — counts as current
        // but is NOT confirmed, so it does NOT add to scoring totals.
        let h3 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 3, par: 4)
        try TestDatabase.seedShot(holeID: h3.id, sequence: 1, club: "driver")

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: h3
        ))

        XCTAssertEqual(state.scoring?.holesCompleted, 2)
        XCTAssertEqual(state.scoring?.totalStrokes, 2 + 3)
        XCTAssertEqual(state.scoring?.totalPar, 4 + 3)
        XCTAssertEqual(state.scoring?.toPar, (2 + 3) - (4 + 3))
    }

    func test_scoring_totalParOmitted_whenNoConfirmedHoleHasPar() throws {
        let round = try TestDatabase.seedRound()
        let h1 = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1, par: nil, confirmedAt: Date())
        try TestDatabase.seedShot(holeID: h1.id, sequence: 1, club: "driver")

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: h1
        ))

        XCTAssertNil(state.scoring?.totalPar)
        XCTAssertNil(state.scoring?.toPar)
        XCTAssertEqual(state.scoring?.totalStrokes, 1)
    }

    // MARK: - Battery

    func test_battery_propagates() throws {
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)

        let state = GlassesStateMapper.snapshot(inputs: makeInputs(
            isActive: true, round: round, hole: hole, batteryPercent: 73
        ))

        XCTAssertEqual(state.battery, 73)
    }

    // MARK: - helpers

    /// A seed-catalog Club row by id (the same rows v5 seeds into the DB).
    private func seedClub(_ id: String) -> Club {
        Club.seedCatalog.first { $0.id == id }!
    }

    private func makeInputs(
        isActive: Bool,
        round: Round? = nil,
        hole: Hole? = nil,
        shots: [Shot] = [],
        currentClub: Club? = nil,
        curatedCourseId: String? = nil,
        latestLocation: CLLocation? = nil,
        lastLocationReceivedAt: Date? = nil,
        locationUnavailable: Bool = false,
        batteryPercent: Int? = nil
    ) -> GlassesStateInputs {
        GlassesStateInputs(
            isActive: isActive,
            currentRound: round,
            currentHole: hole,
            currentHoleShots: shots,
            currentClub: currentClub,
            curatedCourseId: curatedCourseId,
            latestLocation: latestLocation,
            lastLocationReceivedAt: lastLocationReceivedAt,
            locationUnavailable: locationUnavailable,
            batteryPercent: batteryPercent
        )
    }

    private func makeLocation(
        lat: Double = 0,
        lng: Double = 0,
        accuracy: Double
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: Date()
        )
    }
}
