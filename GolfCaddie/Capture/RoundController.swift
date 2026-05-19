import CoreLocation
import Foundation
import Observation

enum GlassesError: Error {
    case noActiveHole
    case unknownClub
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

    /// Curated course resolved for the active round (proximity, name as
    /// tiebreak), or nil when no cached course matches. In-memory only for
    /// now — Phase 3 consumes this (auto-par, distance-to-green) and persists
    /// it on `Round`. Nil ⇒ exactly today's behavior (graceful degradation).
    private(set) var curatedCourseId: String?

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
        curatedCourseId = nil
        location.requestAlways()
        location.startTracking()
        // Fire-and-forget course auto-detection. startRound stays fully
        // synchronous and behavior-identical — detection never blocks the
        // round starting (W1 discipline) and silently no-ops on any failure.
        let roundID = round.id
        Task { [weak self] in await self?.detectAndApplyCourseName(roundID: roundID) }
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
        curatedCourseId = nil
    }

    func clearMostRecentlyEndedRound() {
        mostRecentlyEndedRound = nil
    }

    /// Single apply path for a course-name change, shared by auto-detection
    /// and the manual override. Guards the round is still active before
    /// mutating, persists via the same RoundRepository.update other lifecycle
    /// mutations use, and reassigns `state` so @Observable re-renders and the
    /// glasses GET /api/state picks up `courseName` (GlassesStateMapper
    /// already maps it — no glasses-side work). No-op when unchanged.
    private func applyCourseName(_ name: String?) {
        guard case let .active(round, hole) = state else { return }
        guard round.courseName != name else { return }
        var updated = round
        updated.courseName = name
        try? RoundRepository.update(updated)
        state = .active(round: updated, hole: hole)
    }

    /// Manual course override from the phone UI — also the path for "detection
    /// found nothing" or "detection was wrong". Trims whitespace; an empty
    /// string clears the name back to nil.
    func setCourseName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        applyCourseName((trimmed?.isEmpty ?? true) ? nil : trimmed)
    }

    /// Fire-and-forget course auto-detection, kicked off at the end of
    /// startRound(). Awaits captureBestFix (the existing ≤5m/5s primitive) so
    /// the lookup uses a good fix, then aborts SILENTLY on any of: no/poor fix
    /// (>50m — a bad fix yields an unreliable nearest-course pick, better no
    /// name than a wrong one), no result, or the round having changed /
    /// already carrying a name (a manual edit or restore must win — see
    /// restoreActiveRound, which deliberately does not re-detect).
    private func detectAndApplyCourseName(roundID: UUID) async {
        guard let fix = await location.captureBestFix() else { return }
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 50 else { return }
        // Resolve a curated course (proximity, name as tiebreak) for Phase 3
        // consumption — independent of, and before, the POI name lookup so a
        // missing MapKit POI doesn't also lose the curated match.
        resolveCuratedCourse(near: fix.coordinate, roundID: roundID)
        guard let name = await CourseDetector.detectCourseName(near: fix.coordinate)
        else { return }
        guard case let .active(round, _) = state,
              round.id == roundID,
              round.courseName == nil else { return }
        applyCourseName(name)
    }

    /// Best-effort curated-course match for the active round: nearest cached
    /// course within 3 km, else a name/alias match against the detected
    /// `courseName`. Soft-fail (no cache / no match ⇒ nil). Guarded to the
    /// still-active originating round.
    private func resolveCuratedCourse(near coord: CLLocationCoordinate2D, roundID: UUID) {
        guard case let .active(round, _) = state, round.id == roundID else { return }
        if let course = try? CourseDataRepository.nearest(to: coord, within: 3000) {
            curatedCourseId = course.id
            return
        }
        if let name = round.courseName,
           let course = try? CourseDataRepository.matching(name: name) {
            curatedCourseId = course.id
        }
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

    /// Set the selected club from the glasses POST /api/club path. Parses the
    /// short name with the SAME vocabulary as ClubID.shortName (ClubID.from)
    /// and routes through the SAME setCurrentClub path / single-source-of-truth
    /// `currentClub` property that the phone club picker sets
    /// (ActiveRoundView.swift:199), that GET /api/state reports
    /// (GlassesStateMapper currentClub), and that a glasses-logged shot is
    /// tagged with (logShotFromGlasses → club: currentClub). It only changes
    /// the selection: no shot logged, no score mutated, no GPS — a synchronous
    /// stored-property write, so W1 (no 5s block) is unaffected. Idempotent:
    /// re-selecting the current club is a no-op assignment. Requires an active
    /// hole (parity with shot/undo); unknown short name → unknownClub.
    func setCurrentClubFromGlasses(shortName: String) throws {
        guard case .active = state else {
            throw GlassesError.noActiveHole
        }
        guard let club = ClubID.from(shortName: shortName) else {
            throw GlassesError.unknownClub
        }
        setCurrentClub(club)
    }

    /// Confirm/close the active hole and advance to the next from the glasses
    /// POST /api/hole/advance path. Routes through the SAME
    /// `confirmHoleAndAdvance` the phone "next hole"/confirm action uses
    /// (ActiveRoundView.confirmHole → confirmHoleAndAdvance, ActiveRoundView
    /// .swift:397) so the closed hole's `confirmedAt`, `holes[]`, `scoring`,
    /// and the eagerly-created next hole behave EXACTLY as a phone-confirmed
    /// hole — the newly-`confirmedAt` hole appearing in `holes[]` is what
    /// drives the glasses auto hole-summary, no special-casing. The glasses
    /// send an empty body and have no par input, so par is nil — identical to
    /// a phone confirm where the golfer did not enter a par (scoring already
    /// aggregates only confirmed holes that have a par). NOT idempotent: one
    /// call advances exactly one hole (the glasses gate this behind a 2-step
    /// arm+confirm and never auto-retry it). Requires an active hole (parity
    /// with shot/undo/club); synchronous, no GPS, so W1 is unaffected.
    func advanceHoleFromGlasses() throws {
        guard case .active = state else {
            throw GlassesError.noActiveHole
        }
        try confirmHoleAndAdvance(par: nil)
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

    /// Edit par on ANY hole (incl. an already-confirmed one) from the
    /// previous-hole editor. Deliberately NOT `confirmHoleAndAdvance`: it must
    /// not set `confirmedAt` or spawn a next hole — it only changes `par`.
    /// Persists via `HoleRepository.setPar`; if the edited hole is the live
    /// `currentHole`, reassign `state` so @Observable re-renders and the
    /// glasses GET picks it up (same discipline as `applyCourseName`). Score
    /// is derived everywhere, so no recompute is needed. Use this for an
    /// active round; for an ended round with no live controller call
    /// `HoleRepository.setPar` directly.
    func setPar(_ par: Int?, forHole holeID: UUID) throws {
        try HoleRepository.setPar(holeID: holeID, par: par)
        if case let .active(round, hole) = state, hole.id == holeID {
            var updated = hole
            updated.par = par
            state = .active(round: round, hole: updated)
        }
    }

    /// Fast, non-blocking shot log for the glasses POST path. Unlike
    /// markShotInternal it does NOT await captureBestFix (a 5s GPS ramp) —
    /// during an active round continuous best-accuracy tracking is already
    /// running, so latestLocation is fresh enough. Keeps POST /api/shot under
    /// the glasses' ~5s client timeout, preventing the slow-success +
    /// user-retry double-log. No double-tap guard (deliberate single gesture).
    ///
    /// The shot is tagged with the round's currently-selected `currentClub`
    /// (the same source `GET /api/state` reports as `currentClub` and the same
    /// value a phone-tapped shot records — see markShot()/markShotInternal). If
    /// no club is selected, `currentClub` is nil and the shot has no club, but
    /// a selected club is never dropped. Reading currentClub is a synchronous
    /// stored-property access, so W1 (no 5s GPS block) is unaffected.
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
            club: currentClub,
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
