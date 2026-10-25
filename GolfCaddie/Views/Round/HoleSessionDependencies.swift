import CoreLocation
import Foundation

/// The live round's hole editing, as `HoleSession` needs it. `RoundController`
/// conforms; tests can pass a recording fake to check routing.
@MainActor
protocol LiveHoleEditing: AnyObject {
    var currentHole: Hole? { get }
    var currentHoleShots: [Shot] { get }
    var currentHolePenalties: [Penalty] { get }
    func updateShotClub(id: UUID, club: Club?) throws
    func removeShot(id: UUID) throws
    func moveShotOnCurrentHole(id: UUID, to coordinate: CLLocationCoordinate2D) throws
    @discardableResult
    func insertShot(at coordinate: CLLocationCoordinate2D, club: Club?, anchors: HolePathAnchors) throws -> Shot
    func addPenaltyToCurrentHole(type: PenaltyType, at timestamp: Date) throws
    func removePenaltyFromCurrentHole(id: UUID) throws
    func setPuttsOnCurrentHole(_ putts: Int) throws
    func setHandScoreOnCurrentHole(strokes: Int, putts: Int?) throws
    func setPar(_ par: Int?, forHole holeID: UUID) throws
    func refreshCurrentHoleShots(ifActiveHoleIn holeIDs: Set<UUID>)
}

extension RoundController: LiveHoleEditing {}

/// Reads and writes for a hole that isn't the live one (past in this round, or
/// in a finished round). `RepositoryHoleStore` is the GRDB-backed default.
@MainActor
protocol HoleStore {
    func round(id: UUID) throws -> Round?
    func hole(roundID: UUID, number: Int) throws -> Hole?
    func shots(holeID: UUID) throws -> [Shot]
    func penalties(holeID: UUID) throws -> [Penalty]
    func trail(holeID: UUID) -> [TracePoint]
    func updateShot(_ shot: Shot) throws
    func deleteShot(_ shot: Shot) throws
    @discardableResult
    func insertShot(at coordinate: CLLocationCoordinate2D, holeID: UUID, club: Club?,
                    anchors: HolePathAnchors) throws -> Shot
    func insertPenalty(_ penalty: Penalty) throws
    func deletePenalty(_ penalty: Penalty) throws
    func setPuttCount(_ putts: Int, holeID: UUID) throws
    @discardableResult
    func setHandScore(roundID: UUID, holeNumber: Int, strokes: Int, putts: Int?) throws -> Hole
    func setPar(_ par: Int?, holeID: UUID) throws
    func setTeeShot(_ teeShot: TeeShotResult?, holeID: UUID) throws
    func setGirOverride(_ gir: Bool?, holeID: UUID) throws
}

struct RepositoryHoleStore: HoleStore {
    func round(id: UUID) throws -> Round? { try RoundRepository.round(id: id) }

    func hole(roundID: UUID, number: Int) throws -> Hole? {
        try HoleRepository.hole(forRound: roundID, number: number)
    }

    func shots(holeID: UUID) throws -> [Shot] { try ShotRepository.shotsForHole(holeID) }

    func penalties(holeID: UUID) throws -> [Penalty] { try PenaltyRepository.penaltiesForHole(holeID) }

    func trail(holeID: UUID) -> [TracePoint] { ShotPlacement.trail(forHole: holeID) }

    func updateShot(_ shot: Shot) throws { try ShotRepository.update(shot) }

    func deleteShot(_ shot: Shot) throws { try ShotRepository.deleteAndRenumber(shot) }

    @discardableResult
    func insertShot(at coordinate: CLLocationCoordinate2D, holeID: UUID, club: Club?,
                    anchors: HolePathAnchors) throws -> Shot {
        try ShotRepository.insertShot(at: coordinate, holeID: holeID, club: club, anchors: anchors, now: nil)
    }

    func insertPenalty(_ penalty: Penalty) throws { try PenaltyRepository.insert(penalty) }

    func deletePenalty(_ penalty: Penalty) throws { try PenaltyRepository.delete(penalty) }

    func setPuttCount(_ putts: Int, holeID: UUID) throws {
        try ShotRepository.setPuttCount(putts, holeID: holeID, putterID: ClubRepository.putter()?.id)
    }

    @discardableResult
    func setHandScore(roundID: UUID, holeNumber: Int, strokes: Int, putts: Int?) throws -> Hole {
        try HoleRepository.setHandScore(roundID: roundID, holeNumber: holeNumber, strokes: strokes, putts: putts)
    }

    func setPar(_ par: Int?, holeID: UUID) throws { try HoleRepository.setPar(holeID: holeID, par: par) }

    func setTeeShot(_ teeShot: TeeShotResult?, holeID: UUID) throws {
        try HoleRepository.setTeeShot(holeID: holeID, teeShot)
    }

    func setGirOverride(_ gir: Bool?, holeID: UUID) throws {
        try HoleRepository.setGirOverride(holeID: holeID, gir)
    }
}
