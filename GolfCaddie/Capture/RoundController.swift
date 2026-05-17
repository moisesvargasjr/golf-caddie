import Foundation
import Observation

enum GlassesError: Error {
    case noActiveHole
}

@Observable
@MainActor
final class RoundController {
    enum State {
        case idle
        case active(round: Round, hole: Hole)
    }

    enum ShotMarkResult {
        case success(shotID: UUID, accuracy: Double?)
        case failed(reason: String)
    }

    private(set) var state: State = .idle
    private(set) var currentHoleShots: [Shot] = []
    private(set) var currentClub: ClubID?
    private(set) var lastMarkResult: ShotMarkResult?
    private(set) var mostRecentlyEndedRound: Round?

    var shotsInCurrentHole: Int { currentHoleShots.count }

    @ObservationIgnored
    private let location: LocationManager

    @ObservationIgnored
    private var lastMarkAt: Date?

    @ObservationIgnored
    private let doubleTapThreshold: TimeInterval = 2.0

    init(location: LocationManager) {
        self.location = location
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var currentHole: Hole? {
        if case let .active(_, hole) = state { return hole }
        return nil
    }

    var currentRound: Round? {
        if case let .active(round, _) = state { return round }
        return nil
    }

    func restoreActiveRound() throws {
        guard case .idle = state else { return }
        guard let round = try RoundRepository.activeRound() else { return }
        let holes = try HoleRepository.holesForRound(round.id)
        let hole: Hole
        if let last = holes.last {
            hole = last
        } else {
            hole = Hole(id: UUID(), roundID: round.id, holeNumber: 1, par: nil, confirmedAt: nil)
            try HoleRepository.insert(hole)
        }
        state = .active(round: round, hole: hole)
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        location.startTracking()
    }

    func startRound() throws {
        guard case .idle = state else { return }
        let round = Round(
            id: UUID(),
            startedAt: Date(),
            endedAt: nil,
            courseName: nil,
            notes: nil
        )
        let hole = Hole(
            id: UUID(),
            roundID: round.id,
            holeNumber: 1,
            par: nil,
            confirmedAt: nil
        )
        try RoundRepository.insert(round)
        try HoleRepository.insert(hole)
        state = .active(round: round, hole: hole)
        currentHoleShots = []
        currentClub = nil
        lastMarkResult = nil
        location.requestAlways()
        location.startTracking()
    }

    func endRound() throws {
        guard case let .active(round, _) = state else { return }
        var ended = round
        ended.endedAt = Date()
        try RoundRepository.update(ended)
        location.stopTracking()
        mostRecentlyEndedRound = ended
        state = .idle
        currentHoleShots = []
        currentClub = nil
        lastMarkAt = nil
    }

    func clearMostRecentlyEndedRound() {
        mostRecentlyEndedRound = nil
    }

    func removeLastShot() throws {
        guard case .active = state, let last = currentHoleShots.last else { return }
        try ShotRepository.deleteAndRenumber(last)
        currentHoleShots.removeLast()
    }

    func deleteShot(_ shot: Shot) throws {
        try ShotRepository.deleteAndRenumber(shot)
        if case let .active(_, hole) = state, shot.holeID == hole.id {
            currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        }
    }

    func resumeRound(_ round: Round) throws {
        guard case .idle = state else { return }
        var resumed = round
        resumed.endedAt = nil
        try RoundRepository.update(resumed)

        let holes = try HoleRepository.holesForRound(round.id)
        let hole: Hole
        if let last = holes.last {
            hole = last
        } else {
            hole = Hole(id: UUID(), roundID: round.id, holeNumber: 1, par: nil, confirmedAt: nil)
            try HoleRepository.insert(hole)
        }
        state = .active(round: resumed, hole: hole)
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        mostRecentlyEndedRound = nil
        location.startTracking()
    }

    func setCurrentClub(_ club: ClubID?) {
        currentClub = club
    }

    func confirmHoleAndAdvance(par: Int?) throws {
        guard case let .active(round, currentHole) = state else { return }
        var updated = currentHole
        updated.par = par
        updated.confirmedAt = Date()
        try HoleRepository.update(updated)

        let newHole = Hole(
            id: UUID(),
            roundID: round.id,
            holeNumber: currentHole.holeNumber + 1,
            par: nil,
            confirmedAt: nil
        )
        try HoleRepository.insert(newHole)
        state = .active(round: round, hole: newHole)
        currentHoleShots = []
        currentClub = nil
        lastMarkResult = nil
    }

    /// Fast, non-blocking shot log for the glasses POST path. Unlike
    /// markShotInternal it does NOT await captureBestFix (a 5s GPS ramp) —
    /// during an active round continuous best-accuracy tracking is already
    /// running, so latestLocation is fresh enough. Keeps POST /api/shot under
    /// the glasses' ~5s client timeout, preventing the slow-success +
    /// user-retry double-log. No double-tap guard (deliberate single gesture).
    func logShotFromGlasses() throws {
        guard case let .active(_, hole) = state else {
            throw GlassesError.noActiveHole
        }
        let loc = location.latestLocation
        let hasFix = (loc?.horizontalAccuracy ?? -1) > 0
        let nextSeq = (try? ShotRepository.nextSequenceNumber(forHole: hole.id)) ?? 1
        let shot = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: nextSeq,
            timestamp: Date(),
            latitude: hasFix ? loc?.coordinate.latitude : nil,
            longitude: hasFix ? loc?.coordinate.longitude : nil,
            gpsAccuracy: hasFix ? loc?.horizontalAccuracy : nil,
            hadGPS: hasFix,
            club: nil,
            source: .glasses,
            notes: nil
        )
        try ShotRepository.insert(shot)
        currentHoleShots.append(shot)
        lastMarkResult = .success(shotID: shot.id, accuracy: hasFix ? loc?.horizontalAccuracy : nil)
        if hasFix { Haptics.success() } else { Haptics.warning() }
    }

    /// Undo for the glasses Actions screen: remove whichever of {newest shot,
    /// newest penalty} on the active hole has the later timestamp. No-op (not
    /// an error) when there is nothing to undo.
    func undoLastActionFromGlasses() throws {
        guard case let .active(_, hole) = state else {
            throw GlassesError.noActiveHole
        }
        let lastPenalty = try PenaltyRepository.penaltiesForHole(hole.id).last
        let lastShot = currentHoleShots.last

        switch (lastShot, lastPenalty) {
        case (nil, nil):
            return
        case let (shot?, nil):
            try ShotRepository.deleteAndRenumber(shot)
            currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        case let (nil, penalty?):
            try PenaltyRepository.delete(penalty)
        case let (shot?, penalty?):
            if penalty.timestamp >= shot.timestamp {
                try PenaltyRepository.delete(penalty)
            } else {
                try ShotRepository.deleteAndRenumber(shot)
                currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
            }
        }
    }

    func markShot() async throws {
        try await markShotInternal(source: .button, club: currentClub)
    }

    func markShotFromActionButton() async throws {
        try await markShotInternal(source: .actionButton, club: nil)
    }

    private func markShotInternal(source: ShotSource, club: ClubID?) async throws {
        // The double-tap guard exists for the physical Action button / on-screen
        // double-press. A deliberate single glasses gesture must not be deduped
        // against it (would return state without the shot, breaking
        // read-after-write); the glasses path doesn't go through here anyway.
        if source == .button || source == .actionButton {
            if let last = lastMarkAt, Date().timeIntervalSince(last) < doubleTapThreshold {
                return
            }
            lastMarkAt = Date()
        }

        guard case let .active(_, hole) = state else {
            lastMarkResult = .failed(reason: "No active round")
            Haptics.error()
            return
        }
        let fix = await location.captureBestFix()
        let nextSeq = (try? ShotRepository.nextSequenceNumber(forHole: hole.id)) ?? 1
        let shot = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: nextSeq,
            timestamp: Date(),
            latitude: fix?.coordinate.latitude,
            longitude: fix?.coordinate.longitude,
            gpsAccuracy: fix?.horizontalAccuracy,
            hadGPS: fix != nil,
            club: club,
            source: source,
            notes: nil
        )
        try ShotRepository.insert(shot)
        currentHoleShots.append(shot)
        lastMarkResult = .success(shotID: shot.id, accuracy: fix?.horizontalAccuracy)

        if fix != nil {
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }
}
