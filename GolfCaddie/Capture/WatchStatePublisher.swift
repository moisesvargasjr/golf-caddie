import Foundation
import WatchConnectivity

/// Maps the live RoundController + repositories into a PhoneStateUpdate and
/// pushes it to the watch via `updateApplicationContext` (latest-wins). Runs on
/// a ~1 s cadence while active (distance-to-green changes as the golfer walks),
/// and only sends when the snapshot actually changed (bounds BLE chatter).
@MainActor
final class WatchStatePublisher {
    private weak var controller: RoundController?
    private weak var location: LocationManager?
    private var timer: Timer?
    private var lastSent: PhoneStateUpdate?

    // Phone-side club epoch: bumped above the watch's whenever the phone changes
    // club, so the watch adopts the phone's selection (and vice versa).
    private var phoneEpoch = 0
    private var lastClubShort: String?

    func start(controller: RoundController, location: LocationManager) {
        self.controller = controller
        self.location = location
        timer?.invalidate()
        // 4 s, not 1 s: the per-second push (≈7,200 BLE wakes / round) was a
        // major battery drain on the watch (field test 2026-06-18). Still only
        // sends when the snapshot actually changed; distance-to-green updates
        // every few seconds is plenty for a glance.
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    private func tick() {
        guard WCSession.isSupported() else { return }
        let state = build()
        guard state != lastSent else { return }
        if let data = try? state.encoded() {
            try? WCSession.default.updateApplicationContext([ShotContract.payloadKey: data])
            lastSent = state
        }
    }

    private func build() -> PhoneStateUpdate {
        guard let controller, controller.isActive,
              let round = controller.currentRound,
              let hole = controller.currentHole
        else { return .inactive }

        let courseId = controller.curatedCourseId
        let holeNumber = hole.holeNumber

        // Club epoch: detect a phone-side club change and bump above the watch's.
        let club = controller.currentClub?.shortName
        if club != lastClubShort {
            lastClubShort = club
            phoneEpoch = max(phoneEpoch, LiveShotCoordinator.shared.lastWatchClubEpoch) + 1
        }
        let clubEpoch = max(phoneEpoch, LiveShotCoordinator.shared.lastWatchClubEpoch)

        let bag = (try? ClubConfigurationRepository.load().bag) ?? []
        let clubs = bag.map { c in
            WatchClub(short: c.shortName, name: c.longName,
                      avgYards: ClubAverages.shared.average(for: c) ?? Self.defaultYards(c))
        }

        let strokes = controller.currentHoleShots.enumerated().map { idx, shot -> WatchStroke in
            let fromYards: Int? = {
                guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
                return GlassesStateMapper.yardsToGreen(
                    from: .init(latitude: lat, longitude: lng), courseId: courseId, holeNumber: holeNumber)
            }()
            let lie = shot.source == .manual ? "Manual" : (idx == 0 ? "Tee" : Self.lieFor(fromYards))
            return WatchStroke(
                id: shot.id.uuidString,
                clubShort: shot.club?.shortName,
                clubName: shot.club?.longName ?? "—",
                lie: lie,
                fromYards: fromYards,
                time: Self.timeFormatter.string(from: shot.timestamp),
                manual: shot.source == .manual
            )
        }

        let confirmed = ((try? HoleRepository.holesForRound(round.id)) ?? []).filter { $0.confirmedAt != nil }
        let scorecard = confirmed.map { h -> WatchScoreRow in
            let shots = (try? ShotRepository.count(forHole: h.id)) ?? 0
            let penalties = ((try? PenaltyRepository.penaltiesForHole(h.id)) ?? []).reduce(0) { $0 + $1.strokeCount }
            return WatchScoreRow(hole: h.holeNumber, par: h.par, strokes: shots + penalties)
        }

        let distance: Int? = {
            guard let loc = location?.latestLocation, loc.horizontalAccuracy > 0 else { return nil }
            return GlassesStateMapper.yardsToGreen(from: loc.coordinate, courseId: courseId, holeNumber: holeNumber)
        }()

        return PhoneStateUpdate(
            isActive: true,
            courseName: round.courseName,
            holeNumber: holeNumber,
            par: hole.par,
            distanceToGreenYards: distance,
            currentClubShortName: club,
            clubEpoch: clubEpoch,
            clubs: clubs,
            strokes: strokes,
            scorecard: scorecard
        )
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    private static func lieFor(_ yards: Int?) -> String {
        guard let y = yards else { return "Fairway" }
        if y <= 0 { return "Hole" }
        if y < 20 { return "Green" }
        if y < 60 { return "Approach" }
        return "Fairway"
    }

    /// Fallback carry when a club has no shot history yet (matches the design's
    /// reference yardages).
    private static func defaultYards(_ c: ClubID) -> Int {
        switch c {
        case .driver: 235
        case .threeWood: 215
        case .fiveWood: 200
        case .threeHybrid: 200
        case .fourHybrid: 190
        case .fiveHybrid: 195
        case .threeIron: 200
        case .fourIron: 185
        case .fiveIron: 175
        case .sixIron: 165
        case .sevenIron: 150
        case .eightIron: 138
        case .nineIron: 125
        case .pitchingWedge: 110
        case .gapWedge: 95
        case .sandWedge: 80
        case .lobWedge: 65
        case .putter: 12
        }
    }
}
