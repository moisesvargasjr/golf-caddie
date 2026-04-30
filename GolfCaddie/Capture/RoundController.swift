import Foundation
import Observation

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
    private(set) var shotsInCurrentHole: Int = 0
    private(set) var currentClub: ClubID?
    private(set) var lastMarkResult: ShotMarkResult?

    @ObservationIgnored
    private let location: LocationManager

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
        shotsInCurrentHole = (try? ShotRepository.count(forHole: hole.id)) ?? 0
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
        shotsInCurrentHole = 0
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
        state = .idle
        shotsInCurrentHole = 0
        currentClub = nil
    }

    func setCurrentClub(_ club: ClubID?) {
        currentClub = club
    }

    func markShot(source: ShotSource = .button) async throws {
        guard case let .active(_, hole) = state else {
            lastMarkResult = .failed(reason: "No active round")
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
            club: currentClub,
            source: source,
            notes: nil
        )
        try ShotRepository.insert(shot)
        shotsInCurrentHole += 1
        lastMarkResult = .success(shotID: shot.id, accuracy: fix?.horizontalAccuracy)
    }
}
