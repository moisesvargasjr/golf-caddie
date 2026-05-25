import Foundation
import GRDB
@testable import GolfCaddie

/// In-memory GRDB queue + Database.queue swap helpers for unit tests.
///
/// Pattern in each test class:
///
/// ```
/// override func setUpWithError() throws {
///     queue = try TestDatabase.makeInMemory()
///     TestDatabase.install(queue)
/// }
/// override func tearDownWithError() throws {
///     TestDatabase.restore()
/// }
/// ```
///
/// **Not parallel-test safe.** `Database.queue` is a single global; if anyone
/// flips `-parallel-testing-enabled YES` this seam races. XCTest is serial
/// within a process by default, so this is fine until that changes.
enum TestDatabase {

    /// A fresh in-memory queue with the production migrator applied.
    static func makeInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue)
        return queue
    }

    /// A fresh in-memory queue with the production migrator applied **only up
    /// to the named migration**. Used by `MigrationTests` to inspect schema
    /// state after each version.
    static func makeInMemory(upTo migration: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue, upTo: migration)
        return queue
    }

    /// Swap the production `Database.queue` for a test queue. Saves the
    /// previous value so `restore()` can put it back. Calling `install`
    /// twice without `restore` between is a programming error in tests but is
    /// not enforced here — `restore` always returns to the very first saved
    /// queue, which is what we want.
    static func install(_ queue: DatabaseQueue) {
        if savedQueue == nil { savedQueue = Database.queue }
        Database.queue = queue
    }

    /// Restore whatever was saved on the first `install` call. Safe to call
    /// even if `install` was never called (no-op).
    static func restore() {
        if let q = savedQueue {
            Database.queue = q
            savedQueue = nil
        }
    }

    private static var savedQueue: DatabaseQueue?

    // MARK: - Seed helpers

    @discardableResult
    static func seedRound(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        courseName: String? = nil,
        curatedCourseId: String? = nil
    ) throws -> Round {
        let round = Round(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            courseName: courseName,
            notes: nil,
            curatedCourseId: curatedCourseId
        )
        try RoundRepository.insert(round)
        return round
    }

    @discardableResult
    static func seedHole(
        roundID: UUID,
        holeNumber: Int,
        par: Int? = nil,
        confirmedAt: Date? = nil
    ) throws -> Hole {
        let hole = Hole(
            id: UUID(),
            roundID: roundID,
            holeNumber: holeNumber,
            par: par,
            confirmedAt: confirmedAt
        )
        try HoleRepository.insert(hole)
        return hole
    }

    @discardableResult
    static func seedShot(
        holeID: UUID,
        sequence: Int,
        lat: Double? = nil,
        lng: Double? = nil,
        club: ClubID? = nil,
        hadGPS: Bool = true,
        timestamp: Date = Date()
    ) throws -> Shot {
        let shot = Shot(
            id: UUID(),
            holeID: holeID,
            sequenceNumber: sequence,
            timestamp: timestamp,
            latitude: lat,
            longitude: lng,
            gpsAccuracy: hadGPS ? 5.0 : nil,
            hadGPS: hadGPS,
            club: club,
            source: .button,
            notes: nil
        )
        try ShotRepository.insert(shot)
        return shot
    }

    @discardableResult
    static func seedPenalty(
        holeID: UUID,
        type: PenaltyType = .obOrLost,
        strokeCount: Int = 1,
        timestamp: Date = Date()
    ) throws -> Penalty {
        let penalty = Penalty(
            id: UUID(),
            holeID: holeID,
            type: type,
            strokeCount: strokeCount,
            timestamp: timestamp,
            notes: nil
        )
        try PenaltyRepository.insert(penalty)
        return penalty
    }

    static func seedBag(_ clubs: [ClubID]) throws {
        try ClubConfigurationRepository.save(ClubConfiguration(bag: clubs))
    }

    @discardableResult
    static func seedCuratedCourse(
        id: String,
        name: String = "Test Course",
        center: GeoPoint = GeoPoint(lat: 0, lng: 0),
        holes: [CuratedHole] = []
    ) throws -> CuratedCourse {
        let course = CuratedCourse(
            id: id,
            name: name,
            aliases: [],
            location: center,
            holes: holes
        )
        try CourseDataRepository.replaceAll(with: [course], fetchedAt: Date())
        return course
    }

    static func seedLocalAnchor(
        courseId: String,
        holeNumber: Int,
        tee: GeoPoint? = nil,
        green: GeoPoint? = nil
    ) throws {
        if let tee {
            try LocalAnchorRepository.setPoint(
                courseId: courseId,
                holeNumber: holeNumber,
                which: .tee,
                point: tee
            )
        }
        if let green {
            try LocalAnchorRepository.setPoint(
                courseId: courseId,
                holeNumber: holeNumber,
                which: .green,
                point: green
            )
        }
    }
}
