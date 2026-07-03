import GRDB
import XCTest
@testable import GolfCaddie

/// B33 — the data-driven club catalog: CRUD, the wire resolver, the
/// archive-vs-delete rule, the last-putter guard, and editor validation.
final class ClubRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDownWithError() throws {
        TestDatabase.restore()
        queue = nil
    }

    private func makeCustomClub(
        id: String = UUID().uuidString,
        name: String = "56 Wedge",
        short: String = "56",
        kind: ClubKind = .wedge
    ) -> Club {
        Club(id: id, name: name, shortName: short, kind: kind,
             defaultYards: Club.defaultYards(for: kind), sortOrder: 99)
    }

    // MARK: - CRUD + resolver

    func testSeedCatalogLoadsInOrder() throws {
        let all = try ClubRepository.all()
        XCTAssertEqual(all.count, 18)
        XCTAssertEqual(all.first?.id, "driver")
        XCTAssertEqual(all.last?.id, Club.putterID)
    }

    func testCreateRenameRoundTrip() throws {
        try ClubRepository.save(makeCustomClub(id: "custom-1"))
        var fetched = try XCTUnwrap(ClubRepository.club(id: "custom-1"))
        XCTAssertEqual(fetched.name, "56 Wedge")

        fetched.name = "56° Wedge"
        try ClubRepository.save(fetched)
        XCTAssertEqual(try ClubRepository.club(id: "custom-1")?.name, "56° Wedge")
    }

    func testRenameSeedClubKeepsIdentity() throws {
        var gap = try XCTUnwrap(ClubRepository.club(id: "gapWedge"))
        gap.name = "56 Wedge"
        gap.shortName = "56"
        try ClubRepository.save(gap)
        let renamed = try XCTUnwrap(ClubRepository.club(id: "gapWedge"))
        XCTAssertEqual(renamed.name, "56 Wedge")
        XCTAssertEqual(renamed.shortName, "56")
    }

    func testFromShortNameResolvesActiveAndIgnoresArchived() throws {
        try ClubRepository.save(makeCustomClub(id: "custom-56"))
        XCTAssertEqual(try ClubRepository.from(shortName: "56")?.id, "custom-56")

        // Archive it (reference it first so delete archives instead of removing).
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try seedShot(holeID: hole.id, clubID: "custom-56")
        try ClubRepository.delete(id: "custom-56")

        XCTAssertNil(try ClubRepository.from(shortName: "56"), "archived clubs are off the wire")
        XCTAssertEqual(try ClubRepository.club(id: "custom-56")?.isArchived, true)
    }

    func testActiveShortNameUniquenessIsEnforcedByIndex() throws {
        XCTAssertThrowsError(try ClubRepository.save(makeCustomClub(short: "GW"))) // collides with Gap Wedge
    }

    // MARK: - Delete rule

    func testDeleteUnreferencedHardDeletes() throws {
        try ClubRepository.save(makeCustomClub(id: "custom-x"))
        try ClubRepository.delete(id: "custom-x")
        XCTAssertNil(try ClubRepository.club(id: "custom-x"))
    }

    func testDeleteReferencedArchivesAndCatalogStillNamesIt() throws {
        try ClubRepository.save(makeCustomClub(id: "custom-y", name: "7 Wood", short: "7W", kind: .wood))
        let round = try TestDatabase.seedRound()
        let hole = try TestDatabase.seedHole(roundID: round.id, holeNumber: 1)
        try seedShot(holeID: hole.id, clubID: "custom-y")

        try ClubRepository.delete(id: "custom-y")

        let archived = try XCTUnwrap(ClubRepository.club(id: "custom-y"))
        XCTAssertTrue(archived.isArchived)
        XCTAssertFalse(try ClubRepository.all().contains { $0.id == "custom-y" })
        XCTAssertTrue(try ClubRepository.all(includeArchived: true).contains { $0.id == "custom-y" })
    }

    func testDeletingLastActivePutterThrows() throws {
        XCTAssertThrowsError(try ClubRepository.delete(id: Club.putterID)) { error in
            XCTAssertEqual(error as? ClubRepositoryError, .lastPutter)
        }
        // With a second putter in the catalog, deleting the seed one is fine.
        try ClubRepository.save(makeCustomClub(id: "custom-putter", name: "Blade", short: "Bl", kind: .putter))
        XCTAssertNoThrow(try ClubRepository.delete(id: Club.putterID))
    }

    // MARK: - Validation

    func testValidationRules() throws {
        let others = try ClubRepository.all()
        XCTAssertTrue(ClubValidation.problems(name: "56 Wedge", shortName: "56", others: others).isEmpty)
        XCTAssertEqual(
            ClubValidation.problems(name: "", shortName: "56", others: others),
            [.nameEmpty]
        )
        XCTAssertEqual(
            ClubValidation.problems(name: "X", shortName: "5678", others: others),
            [.shortNameTooLong]
        )
        XCTAssertEqual(
            ClubValidation.problems(name: "X", shortName: "gw", others: others),
            [.shortNameTaken(by: "Gap Wedge")],
            "shortName collisions are case-insensitive"
        )
        XCTAssertEqual(
            ClubValidation.problems(name: String(repeating: "x", count: 25), shortName: "", others: others),
            [.nameTooLong, .shortNameEmpty]
        )
    }

    // MARK: - helpers

    /// Raw insert: `Shot.club` is still `ClubID?` in this commit, so a custom
    /// club id can't ride the model — write the row directly. UUIDs bind
    /// natively (GRDB stores them as BLOBs; a text uuid would break the FK).
    private func seedShot(holeID: UUID, clubID: String) throws {
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO shot (id, holeID, sequenceNumber, timestamp, hadGPS, club, source)
                VALUES (?, ?, 1, ?, 0, ?, 'manual')
                """,
                arguments: [UUID(), holeID, Date(), clubID]
            )
        }
    }
}
