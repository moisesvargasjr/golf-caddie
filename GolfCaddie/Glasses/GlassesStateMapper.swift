import CoreLocation
import Foundation

/// Pure-value inputs to `GlassesStateMapper.snapshot`. Extracted so tests can
/// exercise the mapping without instantiating `RoundController` /
/// `LocationManager` (both `@Observable @MainActor` with `private(set)`
/// properties that `@testable` does not relax). Production code keeps using
/// the `snapshot(controller:location:batteryPercent:)` convenience, which
/// builds an inputs struct and delegates.
struct GlassesStateInputs {
    var isActive: Bool
    var currentRound: Round?
    var currentHole: Hole?
    var currentHoleShots: [Shot]
    var currentClub: ClubID?
    var curatedCourseId: String?
    var latestLocation: CLLocation?
    var lastLocationReceivedAt: Date?
    var locationUnavailable: Bool
    var batteryPercent: Int?
    var glassesInputEnabled: Bool = false
}

// Pure read model: live RoundController + repositories → GolfState.
// @MainActor because it reads RoundController/LocationManager state and does
// synchronous GRDB reads (same pattern the app already uses in RoundReviewView).
enum GlassesStateMapper {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime] // no fractional seconds
        return f
    }()

    /// Production entry point. Thin wrapper over `snapshot(inputs:)` — exists
    /// so callers don't need to know about `GlassesStateInputs`.
    @MainActor
    static func snapshot(
        controller: RoundController,
        location: LocationManager,
        batteryPercent: Int?
    ) -> GolfState {
        snapshot(inputs: GlassesStateInputs(
            isActive: controller.isActive,
            currentRound: controller.currentRound,
            currentHole: controller.currentHole,
            currentHoleShots: controller.currentHoleShots,
            currentClub: controller.currentClub,
            curatedCourseId: controller.curatedCourseId,
            latestLocation: location.latestLocation,
            lastLocationReceivedAt: location.lastLocationReceivedAt,
            locationUnavailable: location.locationUnavailable,
            batteryPercent: batteryPercent,
            glassesInputEnabled: UserDefaults.standard.bool(forKey: "glassesInputEnabled")
        ))
    }

    /// Pure-mapping entry point — what the tests pin against. Still touches
    /// the database (penalties, all-holes, club bag, anchors, curated course)
    /// because those *are* part of the mapper's real contract.
    @MainActor
    static func snapshot(inputs: GlassesStateInputs) -> GolfState {
        guard inputs.isActive,
              let round = inputs.currentRound,
              let hole = inputs.currentHole
        else {
            return .idle
        }

        let liveShots = inputs.currentHoleShots
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
                    courseId: inputs.curatedCourseId,
                    holeNumber: hole.holeNumber,
                    latestLocation: inputs.latestLocation
                )
            ),
            currentClub: inputs.currentClub?.shortName,
            clubs: selectableClubShortNames(),
            lastShot: lastShotDTO(from: liveShots),
            scoring: scoringDTO(confirmedFrom: allHoles),
            gps: gpsDTO(
                latestLocation: inputs.latestLocation,
                lastLocationReceivedAt: inputs.lastLocationReceivedAt,
                locationUnavailable: inputs.locationUnavailable
            ),
            battery: inputs.batteryPercent,
            holes: allHoles.map { holeSummary($0) },
            glassesInputEnabled: inputs.glassesInputEnabled
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
    /// (RootView → ActiveRoundView club row) and the SAME
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

    /// Recap of the most recently swung club — just the club, no distance.
    /// A club's carry isn't knowable until the NEXT shot is logged (it's the
    /// GPS gap to the following position), so pairing a distance here would
    /// describe the PRIOR club, which confused on the HUD (see LastShotDTO).
    /// `currentClub` is the upcoming selection; this is the last actual swing.
    private static func lastShotDTO(from shots: [Shot]) -> LastShotDTO? {
        guard let last = shots.last else { return nil }
        return LastShotDTO(
            club: last.club?.shortName,
            sequenceNumber: last.sequenceNumber
        )
    }

    private static func gpsDTO(
        latestLocation: CLLocation?,
        lastLocationReceivedAt: Date?,
        locationUnavailable: Bool
    ) -> GPSDTO {
        let acc = latestLocation?.horizontalAccuracy ?? -1
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
        if locationUnavailable {
            stale = true
        } else if let received = lastLocationReceivedAt {
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
    private static func distanceToGreen(
        courseId: String?,
        holeNumber: Int,
        latestLocation: CLLocation?
    ) -> Int? {
        guard let courseId,
              let loc = latestLocation, loc.horizontalAccuracy > 0
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

    /// The hole's green coordinate (local capture wins over curated), or nil if
    /// no course is linked / no anchor exists. Shared by the live
    /// distance-to-green and the watch per-stroke distances.
    static func greenCoordinate(courseId: String?, holeNumber: Int) -> CLLocationCoordinate2D? {
        guard let courseId else { return nil }
        let local = try? LocalAnchorRepository.anchor(courseId: courseId, holeNumber: holeNumber)
        let curatedGreen = (try? CourseDataRepository.course(byId: courseId))?
            .holes.first { $0.number == holeNumber }?.greenAnchor
        guard let green = local?.green ?? curatedGreen else { return nil }
        return CLLocationCoordinate2D(latitude: green.lat, longitude: green.lng)
    }

    /// Yards from an arbitrary coordinate to the hole's green; nil without a green.
    static func yardsToGreen(from coordinate: CLLocationCoordinate2D, courseId: String?, holeNumber: Int) -> Int? {
        guard let green = greenCoordinate(courseId: courseId, holeNumber: holeNumber) else { return nil }
        return Int(Distance.yards(fromMeters: Distance.meters(from: coordinate, to: green)).rounded())
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
