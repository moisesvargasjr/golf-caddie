import CoreLocation
import Foundation

// Pure read model: live RoundController + repositories → GolfState.
// @MainActor because it reads RoundController/LocationManager state and does
// synchronous GRDB reads (same pattern the app already uses in RoundReviewView).
enum GlassesStateMapper {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime] // no fractional seconds
        return f
    }()

    @MainActor
    static func snapshot(
        controller: RoundController,
        location: LocationManager,
        batteryPercent: Int?
    ) -> GolfState {
        guard controller.isActive,
              let round = controller.currentRound,
              let hole = controller.currentHole
        else {
            return .idle
        }

        let liveShots = controller.currentHoleShots
        let holePenaltyStrokes = penaltyStrokes(forHole: hole.id)
        let holeShotCount = liveShots.count
        let holeScore = holeShotCount + holePenaltyStrokes

        let allHoles = trimmedHoles(forRound: round.id)

        return GolfState(
            contractVersion: 1,
            active: true,
            round: RoundDTO(
                id: round.id.uuidString,
                startedAt: iso8601.string(from: round.startedAt),
                courseName: round.courseName
            ),
            hole: HoleDTO(
                number: hole.holeNumber,
                par: hole.par,
                shotCount: holeShotCount,
                penalties: holePenaltyStrokes,
                score: holeScore,
                distanceToGreenYards: distanceToGreen(
                    courseId: controller.curatedCourseId,
                    holeNumber: hole.holeNumber,
                    location: location
                )
            ),
            currentClub: controller.currentClub?.shortName,
            clubs: selectableClubShortNames(),
            lastShot: lastShotDTO(from: liveShots),
            scoring: scoringDTO(confirmedFrom: allHoles),
            gps: gpsDTO(location: location),
            battery: batteryPercent,
            holes: allHoles.map { holeSummary($0) }
        )
    }

    // MARK: - Pieces

    private static func penaltyStrokes(forHole holeID: UUID) -> Int {
        let penalties = (try? PenaltyRepository.penaltiesForHole(holeID)) ?? []
        return penalties.reduce(0) { $0 + $1.strokeCount }
    }

    /// Replicates RoundReviewView.trimTrailingEmptyHole: drop a trailing
    /// unconfirmed hole only when it has zero shots AND zero penalties.
    private static func trimmedHoles(forRound roundID: UUID) -> [Hole] {
        let holes = (try? HoleRepository.holesForRound(roundID)) ?? []
        guard let last = holes.last, last.confirmedAt == nil else { return holes }
        let lastShots = (try? ShotRepository.count(forHole: last.id)) ?? 0
        let lastPenalties = (try? PenaltyRepository.penaltiesForHole(last.id).count) ?? 0
        if lastShots == 0 && lastPenalties == 0 {
            return Array(holes.dropLast())
        }
        return holes
    }

    /// Ordered selectable clubs as ClubID.shortName strings, in the golfer's
    /// bag order. Single source of truth: the SAME ClubConfigurationRepository
    /// bag RootView loads and feeds into the phone club picker
    /// (RootView.swift:97 → ActiveRoundView → ClubGridView) and the SAME
    /// ClubID.shortName vocabulary GET's currentClub uses. Omitted (nil) when
    /// the bag is empty so the wire shape matches the contract's "older iOS /
    /// no clubs" case rather than emitting [].
    private static func selectableClubShortNames() -> [String]? {
        let bag = (try? ClubConfigurationRepository.load().bag) ?? []
        guard !bag.isEmpty else { return nil }
        return bag.map { $0.shortName }
    }

    private static func score(forHole hole: Hole) -> Int {
        let shotCount = (try? ShotRepository.count(forHole: hole.id)) ?? 0
        return shotCount + penaltyStrokes(forHole: hole.id)
    }

    /// totalPar/toPar aggregate ONLY confirmed holes that have a par (omit both
    /// if none). totalStrokes covers all confirmed holes. Deliberately does NOT
    /// reuse RoundReviewView.totalPar (which requires every hole to have par).
    private static func scoringDTO(confirmedFrom holes: [Hole]) -> ScoringDTO {
        let confirmed = holes.filter { $0.confirmedAt != nil }
        let totalStrokes = confirmed.reduce(0) { $0 + score(forHole: $1) }

        let withPar = confirmed.filter { $0.par != nil }
        let totalPar: Int?
        let toPar: Int?
        if withPar.isEmpty {
            totalPar = nil
            toPar = nil
        } else {
            let parSum = withPar.reduce(0) { $0 + ($1.par ?? 0) }
            let strokesOverParHoles = withPar.reduce(0) { $0 + score(forHole: $1) }
            totalPar = parSum
            toPar = strokesOverParHoles - parSum
        }

        return ScoringDTO(
            totalStrokes: totalStrokes,
            totalPar: totalPar,
            toPar: toPar,
            holesCompleted: confirmed.count
        )
    }

    private static func holeSummary(_ hole: Hole) -> HoleSummaryDTO {
        let shots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        let shotDTOs = shots.enumerated().map { idx, shot in
            ShotSummaryDTO(
                sequenceNumber: shot.sequenceNumber,
                club: shot.club?.shortName,
                distanceYards: yards(between: shot, and: shots[safe: idx + 1])
            )
        }
        return HoleSummaryDTO(
            number: hole.holeNumber,
            par: hole.par,
            score: shots.count + penaltyStrokes(forHole: hole.id),
            confirmedAt: hole.confirmedAt.map { iso8601.string(from: $0) },
            shots: shotDTOs
        )
    }

    private static func lastShotDTO(from shots: [Shot]) -> LastShotDTO? {
        guard let last = shots.last else { return nil }
        let prior = shots.count >= 2 ? shots[shots.count - 2] : nil
        return LastShotDTO(
            club: last.club?.shortName,
            distanceYards: yards(between: prior, and: last),
            sequenceNumber: last.sequenceNumber
        )
    }

    @MainActor
    private static func gpsDTO(location: LocationManager) -> GPSDTO {
        let loc = location.latestLocation
        let acc = loc?.horizontalAccuracy ?? -1
        // Revised gps.stale semantics (contract): a golfer stands still
        // constantly, so an age-only window flagged STALE even with a
        // perfectly valid recent fix. stale is true ONLY when:
        //   (a) location authorization/services are genuinely unavailable
        //       (denied/restricted), OR
        //   (b) NO location has been *received* by this process for > 30 s.
        // The freshness clock keys off LocationManager.lastLocationReceivedAt
        // (reset on ANY received location, independent of distanceFilter and
        // of the fix's own embedded timestamp — see LocationManager
        // didUpdateLocations), not loc.timestamp, so a stationary golfer with
        // a valid recent fix is never flagged stale (distanceFilter is now
        // kCLDistanceFilterNone so fixes keep arriving while stationary).
        let stale: Bool
        if location.locationUnavailable {
            stale = true
        } else if let received = location.lastLocationReceivedAt {
            stale = Date().timeIntervalSince(received) > 30
        } else {
            stale = true
        }
        return GPSDTO(
            accuracyMeters: acc > 0 ? acc : nil,
            stale: stale
        )
    }

    /// Live yards from the current fix to the hole's green anchor (local
    /// capture wins over curated). nil — and thus omitted — when the round
    /// didn't match a curated course, no green anchor exists yet, or there's
    /// no fix. Same yardage primitive as everywhere else.
    @MainActor
    private static func distanceToGreen(
        courseId: String?,
        holeNumber: Int,
        location: LocationManager
    ) -> Int? {
        guard let courseId,
              let loc = location.latestLocation, loc.horizontalAccuracy > 0
        else { return nil }
        let local = try? LocalAnchorRepository.anchor(
            courseId: courseId, holeNumber: holeNumber
        )
        let curatedGreen = (try? CourseDataRepository.course(byId: courseId))?
            .holes.first { $0.number == holeNumber }?.greenAnchor
        guard let green = local?.green ?? curatedGreen else { return nil }
        let meters = Distance.meters(
            from: loc.coordinate,
            to: CLLocationCoordinate2D(latitude: green.lat, longitude: green.lng)
        )
        return Int(Distance.yards(fromMeters: meters).rounded())
    }

    /// Yards between two shots' coordinates; nil if either is missing or lacks
    /// GPS. Order-independent (distance is symmetric).
    private static func yards(between a: Shot?, and b: Shot?) -> Int? {
        guard let a, let b,
              let aLat = a.latitude, let aLng = a.longitude,
              let bLat = b.latitude, let bLng = b.longitude
        else { return nil }
        let meters = Distance.meters(
            from: CLLocationCoordinate2D(latitude: aLat, longitude: aLng),
            to: CLLocationCoordinate2D(latitude: bLat, longitude: bLng)
        )
        return Int(Distance.yards(fromMeters: meters).rounded())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
