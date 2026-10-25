import CoreLocation
import Foundation
import Observation

/// "The hole on screen" (Duo v2, Architecture B): one editor for the live hole,
/// a past hole in this round, or a hole in a finished round. Replaces the
/// private state + repository writes of the old `HoleDetailView` and
/// `HoleReviewSheet` (both gone; a finished round's review uses this too).
///
/// Routing: when the hole is the live round's current hole, writes go through
/// `LiveHoleEditing` (`RoundController`) so its observable lists, the watch and
/// the glasses stay in sync, and reads come from the controller's live lists.
/// Any other hole is written through the `HoleStore` (repositories), after
/// which the controller is asked to `refreshCurrentHoleShots`.
///
/// Lifecycle: call `open()` when the hole appears and `close()` when it goes.
/// While open the hole is in `HolesUnderEdit`, so a late watch trail never
/// re-places pins under the golfer's finger. A hole with no row yet (a hole
/// before a late start) can be opened; its row is created only when a score is
/// entered via `setHandScore`.
@Observable
@MainActor
final class HoleSession {
    let roundID: UUID
    let holeNumber: Int

    private(set) var isOpen = false
    private(set) var storedHole: Hole? = nil
    private(set) var storedShots: [Shot] = []
    private(set) var storedPenalties: [Penalty] = []
    /// The preferred GPS trail inside the hole's time window (watch first).
    private(set) var trail: [TracePoint] = []
    /// The round's starting hole (nil for pre-v10 rounds).
    private(set) var startingHole: Int? = nil

    private let live: LiveHoleEditing?
    private let store: HoleStore
    /// Orders hold-to-add shots along the hole. Replaced when the round's
    /// course link changes, so a correction applies without rebuilding the
    /// session (and losing the selection or an open question).
    var anchors: HolePathAnchors
    @ObservationIgnored private var registeredHoleID: UUID? = nil

    /// `store` nil = the GRDB-backed `RepositoryHoleStore` (built here, not as a
    /// default argument: its init is main-actor isolated).
    init(roundID: UUID, holeNumber: Int, live: LiveHoleEditing?,
         store: HoleStore? = nil, anchors: HolePathAnchors = .none) {
        self.roundID = roundID
        self.holeNumber = holeNumber
        self.live = live
        self.store = store ?? RepositoryHoleStore()
        self.anchors = anchors
        reload()
    }

    convenience init(hole: Hole, live: LiveHoleEditing?,
                     store: HoleStore? = nil, anchors: HolePathAnchors = .none) {
        self.init(roundID: hole.roundID, holeNumber: hole.holeNumber, live: live,
                  store: store, anchors: anchors)
    }

    // MARK: - Reads

    /// True while this hole is the live round's current hole.
    var isLive: Bool {
        guard let id = storedHole?.id, let current = live?.currentHole else { return false }
        return current.id == id
    }

    /// The hole row (the controller's copy while live); nil until one exists.
    var hole: Hole? { isLive ? live?.currentHole : storedHole }
    var shots: [Shot] { isLive ? (live?.currentHoleShots ?? []) : storedShots }
    var penalties: [Penalty] { isLive ? (live?.currentHolePenalties ?? []) : storedPenalties }
    var par: Int? { hole?.par }
    var penaltyStrokes: Int { penalties.totalStrokes }

    /// nil when there's no row yet.
    var scoreSource: HoleScoreSource? { hole?.effectiveScoreSource }
    var isHandScored: Bool { hole?.isHandScored ?? false }
    /// Shots were (or are being) logged for this hole, as opposed to a typed-in
    /// score or nothing at all.
    var isTracked: Bool { hole != nil && !isHandScored && (isLive || !shots.isEmpty || !penalties.isEmpty) }

    var score: Int? {
        needsEntry ? nil : HoleScoring.score(hole: hole, shots: shots, penaltyStrokes: penaltyStrokes)
    }

    var putts: Int? { needsEntry ? nil : HoleScoring.putts(hole: hole, shots: shots) }

    /// Before the starting hole with no score: show "not tracked" + entry; the
    /// scorecard shows ADD and the totals leave it out.
    var needsEntry: Bool {
        HoleScoring.needsEntry(holeNumber: holeNumber, startingHole: startingHole, hole: hole,
                               hasTrackedData: !shots.isEmpty || !penalties.isEmpty)
    }

    // MARK: - Lifecycle

    func open() {
        guard !isOpen else { return }
        isOpen = true
        reload()
        registerUnderEdit()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let id = registeredHoleID { HolesUnderEdit.end(id) }
        registeredHoleID = nil
    }

    /// Re-read the hole, its shots, penalties and trail from the store.
    func reload() {
        startingHole = (try? store.round(id: roundID))?.startingHole
        storedHole = try? store.hole(roundID: roundID, number: holeNumber)
        guard let id = storedHole?.id else {
            storedShots = []
            storedPenalties = []
            trail = []
            return
        }
        storedShots = (try? store.shots(holeID: id)) ?? []
        storedPenalties = (try? store.penalties(holeID: id)) ?? []
        trail = store.trail(holeID: id)
    }

    // MARK: - Writes

    /// Drop a dragged pin: snapped to the walking path within 8 m, saved `.manual`.
    func moveShot(_ id: UUID, to coordinate: CLLocationCoordinate2D) throws {
        if let live, isLive { try live.moveShotOnCurrentHole(id: id, to: coordinate); return reload() }
        let shot = try existingShot(id)
        try store.updateShot(ShotPlacement.dragged(shot, to: coordinate))
        didWritePastHole()
    }

    /// Change a shot's club; the putt flag follows the club (B31).
    func setClub(_ club: Club?, forShot id: UUID) throws {
        if let live, isLive { try live.updateShotClub(id: id, club: club); return reload() }
        var shot = try existingShot(id)
        shot.club = club?.id
        shot.isPutt = Shot.derivedIsPutt(club: club, explicit: shot.isPutt)
        try store.updateShot(shot)
        didWritePastHole()
    }

    /// Hold-the-map add: numbered by position along the hole, saved `.manual`.
    @discardableResult
    func insertShot(at coordinate: CLLocationCoordinate2D, club: Club? = nil) throws -> Shot {
        if let live, isLive {
            let shot = try live.insertShot(at: coordinate, club: club, anchors: anchors)
            reload()
            return shot
        }
        let id = try existingHoleID()
        let shot = try store.insertShot(at: coordinate, holeID: id, club: club, anchors: anchors)
        didWritePastHole()
        return shot
    }

    func deleteShot(_ id: UUID) throws {
        if let live, isLive { try live.removeShot(id: id); return reload() }
        try store.deleteShot(try existingShot(id))
        didWritePastHole()
    }

    /// Adds a penalty carrying its type's strokes (wrong ball = 2).
    func addPenalty(_ type: PenaltyType) throws {
        if let live, isLive { try live.addPenaltyToCurrentHole(type: type, at: Date()); return reload() }
        let id = try existingHoleID()
        try store.insertPenalty(Penalty.make(holeID: id, type: type))
        didWritePastHole()
    }

    func removePenalty(_ id: UUID) throws {
        if let live, isLive { try live.removePenaltyFromCurrentHole(id: id); return reload() }
        guard let penalty = storedPenalties.first(where: { $0.id == id }) else { throw HoleEditError.notFound }
        try store.deletePenalty(penalty)
        didWritePastHole()
    }

    /// Putts: on a hand-scored hole this edits the typed-in putts; on a
    /// tracked hole it trims or appends putt strokes.
    func setPutts(_ putts: Int) throws {
        if let hole, hole.isHandScored {
            return try setHandScore(strokes: hole.handStrokes ?? max(putts, 1), putts: putts)
        }
        if let live, isLive { try live.setPuttsOnCurrentHole(putts); return reload() }
        try store.setPuttCount(putts, holeID: try existingHoleID())
        didWritePastHole()
    }

    /// Typed-in score for a hole that wasn't tracked (late start / casual).
    /// Creates the hole row if this is the first entry for it.
    func setHandScore(strokes: Int, putts: Int?) throws {
        if let live, isLive { try live.setHandScoreOnCurrentHole(strokes: strokes, putts: putts); return reload() }
        try store.setHandScore(roundID: roundID, holeNumber: holeNumber, strokes: strokes, putts: putts)
        reload()
        registerUnderEdit()
    }

    func setPar(_ par: Int?) throws {
        let id = try existingHoleID()
        if let live { try live.setPar(par, forHole: id) } else { try store.setPar(par, holeID: id) }
        reload()
    }

    // MARK: - Helpers

    private func existingHoleID() throws -> UUID {
        guard let id = storedHole?.id else { throw HoleEditError.notFound }
        return id
    }

    private func existingShot(_ id: UUID) throws -> Shot {
        guard let shot = storedShots.first(where: { $0.id == id }) else { throw HoleEditError.notFound }
        return shot
    }

    private func didWritePastHole() {
        reload()
        if let id = storedHole?.id { live?.refreshCurrentHoleShots(ifActiveHoleIn: [id]) }
    }

    /// Registers the hole in `HolesUnderEdit` once it has a row (a row-less
    /// hole has no pins to protect; it registers after its first entry).
    private func registerUnderEdit() {
        guard isOpen, registeredHoleID == nil, let id = storedHole?.id else { return }
        HolesUnderEdit.begin(id)
        registeredHoleID = id
    }
}
