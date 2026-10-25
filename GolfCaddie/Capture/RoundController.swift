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
    /// Penalty rows on the active hole — observable so the lie counter and
    /// Undo button re-render when one is added/removed. Reset to [] on hole
    /// boundaries (start / advance / end), refreshed from the DB on restore /
    /// resume. Mutations on this property must go through
    /// `addPenaltyToCurrentHole` / `undoLastAction` so other UI stays in sync.
    private(set) var currentHolePenalties: [Penalty] = []
    private(set) var currentClub: Club?
    private(set) var lastMarkResult: ShotMarkResult?
    private(set) var mostRecentlyEndedRound: Round?

    /// The just-confirmed hole when an advance came in via the glasses
    /// (`advanceHoleFromGlasses`), so the phone can tell the player the hole
    /// was finished there (the round map shows a note; ‹ opens the hole). The
    /// phone-confirm path does NOT set this. Cleared via
    /// `clearMostRecentlyConfirmedHoleFromGlasses` once shown.
    private(set) var mostRecentlyConfirmedHoleFromGlasses: Hole?

    /// Curated course resolved for the active round (proximity, name as
    /// tiebreak), or nil when no cached course matches. In-memory only for
    /// now — Phase 3 consumes this (auto-par, distance-to-green) and persists
    /// it on `Round`. Nil ⇒ exactly today's behavior (graceful degradation).
    private(set) var curatedCourseId: String?

    /// Casual mode: GPS yardage + map + a simple per-hole score stepper only —
    /// no shot tracking, club picker, watch or glasses (the "hand a friend the
    /// phone" experience). Adopts the global default at round start; toggleable
    /// mid-round and persisted so a relaunch resumes the same mode.
    private(set) var isCasualMode: Bool = false
    private static let casualDefaultKey = "roundModeDefaultCasual"
    private static let casualCurrentKey = "roundModeCurrentCasual"

    var shotsInCurrentHole: Int { currentHoleShots.count }

    /// Penalty STROKE count on the active hole (sum of per-row strokeCount,
    /// not row count) — what golf rules call strokes from penalties. Read by
    /// the active-round lie stamp: `LYING = shots + penaltyStrokes + 1`.
    var currentHolePenaltyStrokes: Int {
        currentHolePenalties.reduce(0) { $0 + $1.strokeCount }
    }

    @ObservationIgnored
    private let location: LocationManager

    @ObservationIgnored
    private var lastMarkAt: Date?

    @ObservationIgnored
    private let doubleTapThreshold: TimeInterval = 2.0

    /// Timestamp of the most recent glasses-originated action (logged shot
    /// OR undo). Read by `undoLastActionFromGlasses` to enforce a cooldown
    /// — field-test 2026-05-22 found the glasses undo gesture too sensitive
    /// to fire deliberately; consecutive undos within 3s were silently
    /// erasing legit shots. Phone actions are intentionally NOT tracked
    /// here: a phone-log followed by a deliberate glasses-undo is a
    /// legitimate cross-surface sequence.
    @ObservationIgnored
    private var lastGlassesActionAt: Date?

    /// Timestamp of the last glasses-logged SHOT, for the B34 double-tap
    /// guard. Separate from `lastGlassesActionAt` (the undo cooldown key) so
    /// an undo can't block the next legitimate shot.
    @ObservationIgnored
    private var lastGlassesShotAt: Date?

    @ObservationIgnored
    private let glassesUndoCooldown: TimeInterval = 3.0

    @ObservationIgnored
    private var lastBreadcrumb: CLLocation?

    /// B35 seams: where the watch's streamed fix and the phone's live fix come
    /// from. Production reads `WatchFixStore` and `LocationManager`; tests inject.
    @ObservationIgnored
    var watchFixProvider: () -> WatchFix? = { WatchFixStore.shared.latest }

    @ObservationIgnored
    var phoneFixProvider: (() -> GeoFix?)?

    /// The phone's own latest fix.
    func phoneFix() -> GeoFix? {
        if let phoneFixProvider { return phoneFixProvider() }
        return location.latestLocation.map(GeoFix.init)
    }

    /// B35 "watch GPS first": where the golfer is right now. The watch's
    /// streamed fix when usable (even if the phone reports better accuracy: the
    /// phone may be in the cart), else the phone's. `source` + `disagreementMeters`
    /// are what each shot records.
    func currentLocationChoice(at time: Date = Date()) -> LocationChoice {
        LocationPreference.choose(watch: watchFixProvider(), phone: phoneFix(), at: time,
                                  watchMaxAge: LocationPreference.streamedWatchFixMaxAge)
    }

    init(location: LocationManager) {
        self.location = location
        location.onLocationUpdate = { [weak self] loc in
            self?.recordBreadcrumb(loc)
        }
    }

    /// Persist a throttled GPS breadcrumb for the active round — the trail the
    /// fusion engine matches a watch SwingEvent's timestamp against. Throttle:
    /// ≥1 s since the last stored point AND (moved ≥1 m OR ≥5 s elapsed). The
    /// OR keeps a stationary breadcrumb fresh (so a shot logged while standing
    /// still still fuses) without unbounded growth — ~1/s moving, ~1/5 s still.
    private func recordBreadcrumb(_ location: CLLocation) {
        guard case let .active(round, _) = state else { return }
        guard location.horizontalAccuracy > 0 else { return }
        if let last = lastBreadcrumb {
            let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
            guard elapsed >= 1.0 else { return }
            let moved = location.distance(from: last)
            guard moved >= 1.0 || elapsed >= 5.0 else { return }
        }
        let point = TracePoint(
            id: UUID(),
            roundID: round.id,
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
        try? TracePointRepository.insert(point)
        lastBreadcrumb = location
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    /// The bag minus what this round left home — the club list for the watch,
    /// the glasses and the phone picker. The whole bag when idle.
    var clubsInPlay: [Club] {
        let bag = (try? ClubConfigurationRepository.loadBagClubs()) ?? []
        return ClubsInPlay.resolve(bag: bag, leftOut: currentRound?.clubsLeftOut ?? [])
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
        // Restore the hole the golfer was actually on (persisted across launches),
        // not just the highest-numbered — they may have skipped around.
        let savedID = UserDefaults.standard.string(forKey: Self.activeHoleKey(round.id)).flatMap(UUID.init)
        if let savedID, let match = holes.first(where: { $0.id == savedID }) {
            hole = match
        } else if let last = holes.last {
            hole = last
        } else {
            hole = Hole(id: UUID(), roundID: round.id, holeNumber: 1, par: nil, confirmedAt: nil)
            try HoleRepository.insert(hole)
        }
        state = .active(round: round, hole: hole)
        isCasualMode = round.mode.map { $0 == .casual }
            ?? UserDefaults.standard.bool(forKey: Self.casualCurrentKey)
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        currentHolePenalties = (try? PenaltyRepository.penaltiesForHole(hole.id)) ?? []
        // Hydrate the curated link from the persisted round (no re-match)
        // and fill par if the restored hole still has none.
        curatedCourseId = round.curatedCourseId
        autoFillParIfAvailable()
        location.startTracking()
    }

    /// Holes in a standard round; navigation wraps within 1...18.
    static let holesPerRound = 18

    static func activeHoleKey(_ roundID: UUID) -> String { "activeHole.\(roundID.uuidString)" }

    /// Begin a round on `startingHole` in `mode` (chosen at Begin, Duo v2).
    /// Only the starting hole gets a row: earlier holes stay row-less until the
    /// golfer enters a score for them (`HoleRepository.setHandScore`).
    /// `mode == nil` keeps the old behaviour of adopting the Settings casual
    /// default — that default is superseded by the Begin choice in a later PR
    /// (Home, PR 9), after which every caller passes a mode.
    func startRound(startingHole: Int = 1, mode: RoundMode? = nil, clubsLeftOut: [String] = []) throws {
        guard case .idle = state else { return }
        let firstHole = max(1, min(Self.holesPerRound, startingHole))
        let resolvedMode: RoundMode = mode
            ?? (UserDefaults.standard.bool(forKey: Self.casualDefaultKey) ? RoundMode.casual : RoundMode.tracking)
        let round = Round(
            id: UUID(),
            startedAt: Date(),
            endedAt: nil,
            courseName: nil,
            notes: nil,
            clubsLeftOut: clubsLeftOut.isEmpty ? nil : clubsLeftOut,
            mode: resolvedMode,
            startingHole: firstHole
        )
        let hole = Hole(
            id: UUID(),
            roundID: round.id,
            holeNumber: firstHole,
            par: nil,
            confirmedAt: nil
        )
        try RoundRepository.insert(round)
        try HoleRepository.insert(hole)
        WatchFixStore.shared.reset() // never carry a previous round's fix over
        state = .active(round: round, hole: hole)
        UserDefaults.standard.set(hole.id.uuidString, forKey: Self.activeHoleKey(round.id))
        currentHoleShots = []
        currentHolePenalties = []
        currentClub = nil
        lastMarkResult = nil
        curatedCourseId = nil
        lastBreadcrumb = nil
        // The round's mode (persisted on the round, v10) and the legacy
        // current-mode key, which older code paths still read on restore.
        isCasualMode = resolvedMode == .casual
        UserDefaults.standard.set(isCasualMode, forKey: Self.casualCurrentKey)
        location.requestAlways()
        location.startTracking()
        LiveShotCoordinator.shared.warmUpStepCounter()
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
        WatchFixStore.shared.reset()
        state = .idle
        currentHoleShots = []
        currentHolePenalties = []
        currentClub = nil
        lastMarkAt = nil
        curatedCourseId = nil
        lastBreadcrumb = nil
        UserDefaults.standard.removeObject(forKey: Self.activeHoleKey(round.id))
    }

    func clearMostRecentlyEndedRound() {
        mostRecentlyEndedRound = nil
    }

    func clearMostRecentlyConfirmedHoleFromGlasses() {
        mostRecentlyConfirmedHoleFromGlasses = nil
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

    /// Change the clubs in play mid-round (a club "left home" turned out to be
    /// in the bag, or vice versa). Persists on the round so the watch, glasses
    /// and pickers follow on their next read, and drops the selected club if
    /// it's no longer in play so nothing gets tagged with a club not carried.
    func setClubsLeftOut(_ leftOut: [String]) {
        guard case let .active(round, hole) = state else { return }
        let bag = (try? ClubConfigurationRepository.loadBagClubs()) ?? []
        guard !bag.isEmpty else { return }
        let normalized = ClubsInPlay.normalized(bag: bag, leftOut: leftOut)
        let stored = normalized.isEmpty ? nil : normalized
        guard round.clubsLeftOut != stored else { return }
        var updated = round
        updated.clubsLeftOut = stored
        try? RoundRepository.update(updated)
        state = .active(round: updated, hole: hole)
        if let club = currentClub, normalized.contains(club.id) {
            currentClub = nil
        }
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
        // A curated match supplies its own (authoritative) name, so skip the
        // POI lookup entirely — it's the mislabeling source (at the Welk it
        // names the sibling "Fountains" course) and now redundant.
        if case let .active(round, _) = state, round.id == roundID, round.courseName != nil {
            return
        }
        guard let name = await CourseDetector.detectCourseName(near: fix.coordinate)
        else { return }
        guard case let .active(round, _) = state,
              round.id == roundID,
              round.courseName == nil else { return }
        applyCourseName(name)
    }

    /// Best-effort curated-course match for the active round: the cached
    /// course underfoot (`CourseCatalog.courseUnderfoot`), else a name/alias
    /// match against the detected `courseName`. Soft-fail (no cache / no match ⇒ nil). Guarded to the
    /// still-active originating round.
    private func resolveCuratedCourse(near coord: CLLocationCoordinate2D, roundID: UUID) {
        // A course already linked by hand (Home's Course row, or an in-round
        // relink before the fix arrived) wins over proximity.
        guard case let .active(round, _) = state, round.id == roundID,
              round.curatedCourseId == nil else { return }
        let courses = (try? CourseDataRepository.allCourses()) ?? []
        if let course = CourseCatalog.courseUnderfoot(in: courses, at: coord) {
            applyCuratedCourseId(course.id)
            return
        }
        if let name = round.courseName,
           let course = try? CourseDataRepository.matching(name: name) {
            applyCuratedCourseId(course.id)
        }
    }

    /// Set the resolved curated course: in-memory property + persist it on
    /// the round (survives relaunch/resume) + reassign state (same discipline
    /// as applyCourseName). Then auto-fill par for the active hole.
    private func applyCuratedCourseId(_ id: String?, adoptName: Bool = false) {
        let previousCourseId = curatedCourseId
        curatedCourseId = id
        if case let .active(round, hole) = state, round.curatedCourseId != id {
            var updated = round
            updated.curatedCourseId = id
            // Prefer the curated course's OWN name as the display label. Apple's
            // nearest-POI lookup mislabels multi-course facilities — at the Welk
            // it picks the sibling "Fountains" course while we correctly link
            // the Oaks (field test 2026-06-18). Adopt the curated name when the
            // round has no name yet (fresh auto-detect) or the caller is fixing
            // a wrong detect via manual re-link. Never clobbers a manual name on
            // a plain auto-detect (guarded by courseName == nil there).
            if let id, updated.courseName == nil || adoptName,
               let course = try? CourseDataRepository.course(byId: id) {
                updated.courseName = course.name
            }
            try? RoundRepository.update(updated)
            state = .active(round: updated, hole: hole)
        }
        if let previousCourseId, previousCourseId != id {
            replaceAutoFilledPars(from: previousCourseId)
        }
        autoFillParIfAvailable()
    }

    /// A re-link away from a wrong course: auto-filled pars follow the new
    /// course (`CourseRelinkPars`), through `setPar` so the live hole follows.
    private func replaceAutoFilledPars(from previousCourseId: String) {
        guard case let .active(round, _) = state,
              let changes = try? CourseRelinkPars.changes(roundID: round.id, from: previousCourseId,
                                                          to: curatedCourseId) else { return }
        for change in changes {
            try? setPar(change.par, forHole: change.holeID)
        }
    }

    /// Manually link (or unlink) a curated course on the active round from
    /// the in-round UI — the recovery path for "auto-detect missed at start"
    /// or "auto-detect picked the wrong course." Mirrors the post-round
    /// retro-link on `RoundReviewView`, but routes through
    /// `applyCuratedCourseId` so the in-memory `curatedCourseId` and `state`
    /// refresh too — without that, @Observable consumers (distance-to-green,
    /// anchor-capture gating, curated par auto-fill, `holeBearing`) wouldn't
    /// pick up the change until the round was reloaded. Pass nil to unlink.
    /// No-op outside an active round (the picker isn't reachable there).
    func setCuratedCourseId(_ id: String?) {
        guard case .active = state else { return }
        // Manual (re)link is the "auto-detect picked the wrong course" recovery,
        // so adopt the curated course's name as the label too — replacing a
        // wrong POI name like "Fountains" with "The Oaks at the Welk".
        applyCuratedCourseId(id, adoptName: true)
    }

    /// If a curated course is resolved, pre-fill par for the ACTIVE hole when
    /// it has none yet. Manual par always wins (only nil → filled), so this
    /// is a creation-time default, not an override. Idempotent; routed
    /// through setPar so state/glasses propagation is consistent.
    private func autoFillParIfAvailable() {
        guard let courseId = curatedCourseId,
              case let .active(_, hole) = state,
              hole.par == nil,
              let course = try? CourseDataRepository.course(byId: courseId),
              let curated = course.holes.first(where: { $0.number == hole.holeNumber })
        else { return }
        try? setPar(curated.par, forHole: hole.id)
    }

    /// Append a "missed" shot to the active hole — for the case where the
    /// player realized after-the-fact (or after multiple shots) that they
    /// forgot to tap Log Shot. Routes through the controller (not
    /// `ShotRepository.insertShot` directly) so the in-memory
    /// `currentHoleShots` refreshes and the lie counter, scorecard, and
    /// glasses HUD all see the shot immediately.
    ///
    /// The coordinate comes from the phone UI's pin-drop, NOT live GPS — we
    /// can't reconstruct where the player was at the missed-shot moment.
    /// `hadGPS = true` because we DO have a coordinate (just not a live
    /// fix); accuracy is left nil to distinguish from real fixes. The shot
    /// is appended at the END of the hole (sequenceNumber = count + 1);
    /// `insertShot(at:club:anchors:)` is the general form (numbered by
    /// position along the hole), which holding the map uses; this
    /// end-append remains for older callers.
    func insertMissingShot(at coord: CLLocationCoordinate2D, club: Club?) throws {
        guard case let .active(_, hole) = state else {
            throw GlassesError.noActiveHole
        }
        let nextSeq = (try? ShotRepository.nextSequenceNumber(forHole: hole.id)) ?? 1
        let drafted = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: nextSeq,
            timestamp: Date(),
            latitude: coord.latitude,
            longitude: coord.longitude,
            gpsAccuracy: nil,
            hadGPS: true,
            club: club?.id,
            source: .manual,
            notes: nil,
            isPutt: Shot.derivedIsPutt(club: club),
            locationSource: .manual
        )
        // B38: a pin dropped within ~15 m of the golfer's path snaps onto it (track).
        let shot = ShotPlacement.pinned(drafted, at: coord)
        try ShotRepository.insertShot(shot, at: nextSeq)
        currentHoleShots.append(shot)
    }

    /// Commit a reconciled auto-detected shot from the watch. The coordinate was
    /// already fused on the phone (breadcrumb nearest the swing's timestamp);
    /// pass nil when fusion found nothing (hadGPS=false). The shot keeps the
    /// swing's own `timestamp` (when it actually happened) and the club carried
    /// on the event, falling back to the round's `currentClub`. Routed through
    /// the controller so `currentHoleShots`, the lie counter, and the glasses
    /// HUD refresh. No-op-throws outside an active hole.
    @discardableResult
    func ingestAutoShot(at coordinate: CLLocationCoordinate2D?, accuracy: Double?,
                        club: Club?, timestamp: Date,
                        source: ShotSource = .watchAuto, isPutt: Bool = false,
                        locationSource: ShotLocationSource? = nil,
                        disagreementMeters: Double? = nil) throws -> UUID {
        guard case let .active(_, hole) = state else { throw GlassesError.noActiveHole }
        let resolvedClub = club ?? currentClub
        // B31: a putter club means a putt no matter what the caller's flag said
        // (the watch "+ ADD STROKE" grid includes Pt but sends isPutt=false).
        // Deriving before the dedup also engages its "never merge putt ↔ full"
        // guard for putter-club taps.
        let resolvedIsPutt = Shot.derivedIsPutt(club: resolvedClub, explicit: isPutt)
        // B7 cross-source dedup: collapse the "detector fired AND the golfer also
        // tapped MARK SHOT for the same swing" double-log into one row.
        switch SameSwingDedup.decide(
            incoming: .init(timestamp: timestamp, coordinate: coordinate, source: source, isPutt: resolvedIsPutt),
            against: currentHoleShots
        ) {
        case .insert:
            break
        case let .adoptManualClub(existingID):
            // A deliberate tap for a swing the detector already logged: keep the
            // auto row's fused location, take over with the manual club + source.
            if let idx = currentHoleShots.firstIndex(where: { $0.id == existingID }) {
                var merged = currentHoleShots[idx]
                if let resolvedClub { merged.club = resolvedClub.id }
                merged.source = source
                merged.isPutt = Shot.derivedIsPutt(
                    club: resolvedClub ?? ClubCatalog.shared.club(id: merged.club),
                    explicit: isPutt)
                try? ShotRepository.update(merged)
                currentHoleShots[idx] = merged
            }
            return existingID
        case let .dropDuplicate(existingID):
            return existingID // an auto shot duplicating a manual one — already represented
        }
        let nextSeq = (try? ShotRepository.nextSequenceNumber(forHole: hole.id)) ?? 1
        // The hole's first full shot came off the tee: pin it there when the fix
        // agrees (TeeSnap). Putts and later shots keep their fix.
        var coordinate = coordinate
        if !resolvedIsPutt {
            coordinate = TeeSnap.snapped(
                coordinate,
                isFirstFullShot: !currentHoleShots.contains { !$0.isPutt },
                tee: GlassesStateMapper.teeCoordinate(courseId: curatedCourseId, holeNumber: hole.holeNumber))
        }
        let shot = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: nextSeq,
            timestamp: timestamp,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            gpsAccuracy: accuracy,
            hadGPS: coordinate != nil,
            club: resolvedClub?.id,
            source: source,
            notes: nil,
            isPutt: resolvedIsPutt,
            locationSource: coordinate == nil ? nil : locationSource,
            locationDisagreementMeters: coordinate == nil ? nil : disagreementMeters
        )
        try ShotRepository.insert(shot)
        currentHoleShots.append(shot)
        return shot.id
    }

    /// Watch "add shot here now" (false-negative recovery) — logs at the live
    /// fix with the current club, like the glasses fast path. Tagged
    /// `.watchManual` (a deliberate tap), NOT `.watchAuto` — so per-club stats
    /// and detector precision/recall measured from real rounds stay honest (B3).
    func addShotFromWatch(late: LateWatchTap? = nil) throws {
        let at = late ?? liveWatchTap()
        try ingestAutoShot(at: at.coordinate, accuracy: at.accuracy,
                           club: currentClub, timestamp: at.timestamp, source: .watchManual,
                           locationSource: at.locationSource, disagreementMeters: at.disagreementMeters)
    }

    /// When + where a watch MARK/putt tap happened, overriding "now at the
    /// phone's live fix": the watch's own GPS at the tap (live or late), or, for
    /// a tap delivered late (queued while the phone was unreachable), the
    /// watch's tap time and the breadcrumb fused to it — NOT the delivery time
    /// and the phone's position holes later. `coordinate` nil = no fix near that
    /// time (honest no-GPS beats a wrong location).
    struct LateWatchTap {
        let timestamp: Date
        let choice: LocationChoice

        var coordinate: CLLocationCoordinate2D? { choice.fix?.coordinate }
        var accuracy: Double? { choice.fix?.horizontalAccuracy }
        var locationSource: ShotLocationSource? { ShotLocationSource(choice.source) }
        var disagreementMeters: Double? { choice.disagreementMeters }
    }

    private func liveWatchTap() -> LateWatchTap {
        LateWatchTap(timestamp: Date(), choice: currentLocationChoice())
    }

    /// Watch putt counter (+1) — a putter shot at the live fix. Putts are not
    /// auto-detected (per the handoff doc), so this manual tap is how they land.
    /// Tagged `.watchManual` + `isPutt` so the green-split and "no full-shot
    /// distance" rules have an explicit signal beyond the putter club (B3).
    ///
    /// No tap-bounce dedup: putts are often batch-logged a few rapid taps at a
    /// time after the fact (sink it, then catch up), all at the hole — so rapid
    /// same-spot putts are real, not accidental double-taps (field note 2026-06-30).
    func addPuttFromWatch(late: LateWatchTap? = nil) throws {
        let at = late ?? liveWatchTap()
        try ingestAutoShot(at: at.coordinate, accuracy: at.accuracy,
                           club: resolvedPutter(), timestamp: at.timestamp, source: .watchManual, isPutt: true,
                           locationSource: at.locationSource, disagreementMeters: at.disagreementMeters)
    }

    /// Watch "Finish Hole": the golfer gave the putt count (and, on a par 4 or
    /// 5, where the tee shot finished) and confirmed the score. Reconcile the tracked strokes to it (see `HoleFinishReconciler`),
    /// then confirm the hole and advance. Excluded strokes stay restorable.
    /// Returns the plan that was applied (nil without an active hole).
    @discardableResult
    func finishHole(putts: Int, score: Int, teeShot: TeeShotResult? = nil,
                    at timestamp: Date = Date()) throws -> HoleFinishReconciler.Plan? {
        guard case let .active(_, hole) = state else { return nil }
        // Before the confirm, which re-reads the stored row.
        if let teeShot { try HoleRepository.setTeeShot(holeID: hole.id, teeShot) }
        let plan = HoleFinishReconciler.plan(
            shots: currentHoleShots, penaltyStrokes: currentHolePenaltyStrokes, putts: putts, score: score)

        if !plan.excludeIDs.isEmpty {
            try ShotRepository.setExcluded(plan.excludeIDs, at: timestamp)
            currentHoleShots.removeAll { plan.excludeIDs.contains($0.id) }
        }
        // Missed full shots go in BEFORE the putts so the sequence reads right.
        // Unlocated + `.reconstructed` → review ambers them for a pin/club.
        for _ in 0..<plan.fullShotsToAdd {
            try append(Shot(
                id: UUID(), holeID: hole.id, sequenceNumber: 0, timestamp: timestamp,
                latitude: nil, longitude: nil, gpsAccuracy: nil, hadGPS: false,
                club: nil, source: .reconstructed, notes: nil, isPutt: false))
        }
        let putter = resolvedPutter()
        for _ in 0..<plan.puttsToAdd {
            try append(Shot(
                id: UUID(), holeID: hole.id, sequenceNumber: 0, timestamp: timestamp,
                latitude: nil, longitude: nil, gpsAccuracy: nil, hadGPS: false,
                club: putter?.id, source: .watchManual, notes: nil, isPutt: true))
        }
        try confirmHoleAndAdvance(par: hole.par)
        return plan
    }

    private func append(_ shot: Shot) throws {
        var shot = shot
        shot.sequenceNumber = (try? ShotRepository.nextSequenceNumber(forHole: shot.holeID)) ?? 1
        try ShotRepository.insert(shot)
        currentHoleShots.append(shot)
    }

    /// First putter-kind club in play, else first active putter-kind club.
    /// The editor guarantees ≥1 active putter; explicit isPutt:true keeps putts
    /// correct even in the nil fallback.
    private func resolvedPutter() -> Club? {
        if let putter = clubsInPlay.first(where: { $0.kind == .putter }) { return putter }
        return ((try? ClubRepository.all()) ?? []).first { $0.kind == .putter }
    }

    /// Remove a specific shot on the active hole by id (the watch Strokes-page
    /// per-row delete). Renumbers siblings and refreshes the observable list.
    /// No-op if the shot isn't on the active hole.
    func removeShot(id: UUID) throws {
        guard case let .active(_, hole) = state else { return }
        guard let shot = currentHoleShots.first(where: { $0.id == id }) else { return }
        try ShotRepository.deleteAndRenumber(shot)
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
    }

    /// Re-pull `currentHoleShots` after an out-of-band edit (a stroke moved
    /// between holes from HoleDetailView). No-op unless the active hole is one
    /// of `holeIDs`.
    func refreshCurrentHoleShots(ifActiveHoleIn holeIDs: Set<UUID>) {
        guard case let .active(_, hole) = state, holeIDs.contains(hole.id) else { return }
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
    }

    /// Change a logged shot's club on the active hole by id (the watch
    /// Strokes-page edit sheet, B25), re-deriving `isPutt` from the new club
    /// (B31). Mutates `currentHoleShots` in place so the WatchStatePublisher's
    /// next tick carries the edit back to the watch. No-op if the shot isn't
    /// on the active hole. (Past-hole edits go through `HoleSession` /
    /// HoleDetailView — they don't touch the live list.)
    func updateShotClub(id: UUID, club: Club?) throws {
        guard case .active = state else { return }
        guard let idx = currentHoleShots.firstIndex(where: { $0.id == id }) else { return }
        var shot = currentHoleShots[idx]
        shot.club = club?.id
        shot.isPutt = Shot.derivedIsPutt(club: club, explicit: shot.isPutt)
        try ShotRepository.update(shot)
        currentHoleShots[idx] = shot
    }

    /// Add a penalty to the active hole (the round map's penalty question,
    /// via `HoleSession`). Routes the insert through the controller so the in-memory
    /// `currentHolePenalties` refreshes — without that, the @Observable
    /// consumers (the shot list, the score) wouldn't see the new penalty
    /// until something else rebuilt them.
    func addPenaltyToCurrentHole(type: PenaltyType, at timestamp: Date = Date()) throws {
        guard case let .active(_, hole) = state else {
            throw GlassesError.noActiveHole
        }
        // Strokes come from the type (wrong ball = 2). A late-delivered watch
        // penalty keeps its tap time.
        let penalty = Penalty.make(holeID: hole.id, type: type, at: timestamp)
        try PenaltyRepository.insert(penalty)
        currentHolePenalties.append(penalty)
    }

    // MARK: - Live-hole editing (HoleSession routes here for the live hole)

    /// Remove one penalty from the active hole by id. No-op if it isn't there.
    func removePenaltyFromCurrentHole(id: UUID) throws {
        guard case .active = state,
              let penalty = currentHolePenalties.first(where: { $0.id == id }) else { return }
        try PenaltyRepository.delete(penalty)
        currentHolePenalties = currentHolePenalties.filter { $0.id != id }
    }

    /// A pin dragged on the live hole: snapped within 8 m of the walking path
    /// and saved `.manual` (so the trail re-placement never moves it).
    func moveShotOnCurrentHole(id: UUID, to coordinate: CLLocationCoordinate2D) throws {
        guard case .active = state,
              let shot = currentHoleShots.first(where: { $0.id == id }) else { return }
        let moved = ShotPlacement.dragged(shot, to: coordinate)
        try ShotRepository.update(moved)
        currentHoleShots = currentHoleShots.map { $0.id == id ? moved : $0 }
    }

    /// Hold-the-map add on the live hole: the general form of
    /// `insertMissingShot` — the shot is numbered by its position along the
    /// hole (`ShotInsertOrdering`) instead of always going last.
    @discardableResult
    func insertShot(at coordinate: CLLocationCoordinate2D, club: Club?,
                    anchors: HolePathAnchors = .none) throws -> Shot {
        guard case let .active(_, hole) = state else { throw GlassesError.noActiveHole }
        let shot = try ShotRepository.insertShot(at: coordinate, holeID: hole.id, club: club,
                                                 anchors: anchors, now: Date())
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        return shot
    }

    /// Set the live hole's putt count (tracked holes): trims or appends putts.
    func setPuttsOnCurrentHole(_ putts: Int) throws {
        guard case let .active(_, hole) = state else { throw GlassesError.noActiveHole }
        try ShotRepository.setPuttCount(putts, holeID: hole.id, putterID: resolvedPutter()?.id)
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
    }

    /// Hand score on the live hole (casual Finish). Updates `state` so the
    /// in-memory hole matches the row and a later confirm doesn't clobber it.
    func setHandScoreOnCurrentHole(strokes: Int, putts: Int?) throws {
        guard case let .active(round, hole) = state else { throw GlassesError.noActiveHole }
        let updated = try HoleRepository.setHandScore(
            roundID: round.id, holeNumber: hole.holeNumber, strokes: strokes, putts: putts)
        state = .active(round: round, hole: updated)
    }

    /// Undo the most recent action on the active hole — whichever of {newest
    /// shot, newest penalty} has the later timestamp. No-op when both are
    /// empty. Shared by the phone Undo button (this method directly) and the
    /// glasses POST /api/undo path (via `undoLastActionFromGlasses`, which
    /// adds the no-active-hole error semantic the glasses contract expects).
    func undoLastAction() throws {
        guard case let .active(_, hole) = state else { return }
        let lastPenalty = currentHolePenalties.last
        let lastShot = currentHoleShots.last
        switch (lastShot, lastPenalty) {
        case (nil, nil):
            return
        case let (shot?, nil):
            try ShotRepository.deleteAndRenumber(shot)
            currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        case let (nil, penalty?):
            try PenaltyRepository.delete(penalty)
            currentHolePenalties.removeLast()
        case let (shot?, penalty?):
            if penalty.timestamp >= shot.timestamp {
                try PenaltyRepository.delete(penalty)
                currentHolePenalties.removeLast()
            } else {
                try ShotRepository.deleteAndRenumber(shot)
                currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
            }
        }
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
        if let mode = resumed.mode { isCasualMode = mode == .casual }
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        currentHolePenalties = (try? PenaltyRepository.penaltiesForHole(hole.id)) ?? []
        mostRecentlyEndedRound = nil
        location.startTracking()
    }

    func setCurrentClub(_ club: Club?) {
        currentClub = club
    }

    /// Set the selected club from the glasses POST /api/club path. Resolves
    /// the short name with the SAME club-table vocabulary the wire uses
    /// (ClubRepository.from(shortName:), active clubs only) and routes through
    /// the SAME setCurrentClub path / single-source-of-truth `currentClub`
    /// property that the phone club picker sets (ActiveRoundView.swift:199),
    /// that GET /api/state reports (GlassesStateMapper currentClub), and that
    /// a glasses-logged shot is tagged with (logShotFromGlasses → club:
    /// currentClub). It only changes the selection: no shot logged, no score
    /// mutated, no GPS — a synchronous stored-property write plus one tiny DB
    /// read, so W1 (no 5s block) is unaffected. Idempotent: re-selecting the
    /// current club is a no-op assignment. Requires an active hole (parity
    /// with shot/undo); unknown short name → unknownClub.
    func setCurrentClubFromGlasses(shortName: String) throws {
        guard case .active = state else {
            throw GlassesError.noActiveHole
        }
        guard let club = (try? ClubRepository.from(shortName: shortName)) ?? nil else {
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
    /// send an empty body and have no par input, so we pass the hole's
    /// EXISTING par through — preserving the curated auto-fill (and any phone
    /// override of it). Passing nil here would clobber the auto-filled par to
    /// nil, dropping the closing hole out of scoring's par-aware aggregate.
    /// When no par was ever set (no curated match + no phone entry) `.par`
    /// is already nil and the behavior is identical to "phone confirm with no
    /// par entered." NOT idempotent: one call advances exactly one hole (the
    /// glasses gate this behind a 2-step arm+confirm and never auto-retry it).
    /// Requires an active hole (parity with shot/undo/club); synchronous, no
    /// GPS, so W1 is unaffected.
    func advanceHoleFromGlasses() throws {
        guard case let .active(_, currentHole) = state else {
            throw GlassesError.noActiveHole
        }
        try confirmHoleAndAdvance(par: currentHole.par)
        // Capture the just-confirmed hole's identity for the phone to pop
        // up a retro summary sheet (field-test 2026-05-22). Synthesize the
        // confirmed state — the sheet loads shots / penalties from the DB
        // by holeID, so we only need the ID + holeNumber + par for the
        // masthead and par stepper.
        var justConfirmed = currentHole
        justConfirmed.confirmedAt = Date()
        mostRecentlyConfirmedHoleFromGlasses = justConfirmed
    }

    func confirmHoleAndAdvance(par: Int?) throws {
        guard case let .active(round, currentHole) = state else { return }
        // Start from the stored row so columns edited elsewhere (a hand score
        // from HoleSession) survive the confirm.
        var updated = (try? HoleRepository.hole(byID: currentHole.id)) ?? currentHole
        updated.par = par
        updated.confirmedAt = Date()
        try HoleRepository.update(updated)
        reconstructHole(currentHole, in: round) // B7: green-split + confidence, persisted
        // Advance to the next hole number, wrapping 18 → 1 (so a back-9 start
        // rolls onto the front 9). goToHole finds an existing row or creates it.
        let next = (currentHole.holeNumber % Self.holesPerRound) + 1
        goToHole(next)
    }

    /// End-of-hole reconstruction (B7 Path A): classify the just-played hole's
    /// shots into full shots vs putts (green-split) and score each for confidence,
    /// then persist. Non-destructive — locations and clubs are untouched; only
    /// `isPutt`/`confidence` change, so the confirmation card (B7.3) and per-club
    /// stats get an honest split with no golfer effort. Putter strokes still
    /// classify even when the course has no green anchor.
    private func reconstructHole(_ hole: Hole, in round: Round) {
        let shots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        guard !shots.isEmpty else { return }
        // Phone-only holes are placed by Path B on review entry (and possibly
        // hand-adjusted since); don't re-run the green-split over them.
        guard !shots.contains(where: { $0.source == .reconstructed }) else { return }
        let green = GlassesStateMapper.greenCoordinate(
            courseId: round.curatedCourseId, holeNumber: hole.holeNumber)
        // The green-split's "logged with the putter" check needs the real set
        // of putter-kind ids (renamed/custom putters, archived included so
        // history classifies). Soft-fail keeps the config's seed-id default.
        var config = ReconstructionConfig.default
        let putterIDs = ((try? ClubRepository.all(includeArchived: true)) ?? [])
            .filter { $0.kind == .putter }
            .map(\.id)
        if !putterIDs.isEmpty { config.putterClubIDs = Set(putterIDs) }
        for r in Reconstructor.reconstruct(shots: shots, green: green, config: config).shots
            where r.applied != r.shot {
            try? ShotRepository.update(r.applied)
        }
    }

    /// Path-B (phone-only) placement (B6): turn the active hole's detail-less
    /// casual strokes into located, classified shots by reading the GPS track —
    /// full shots at off-green dwells, putts on the green. Called when the golfer
    /// opens the review on a phone-only hole; the review sheet then shows the
    /// reconstructed split + draggable pins to confirm/adjust. Runs once: if the
    /// hole is already reconstructed (and maybe hand-tuned), it's left untouched.
    func placeCurrentHoleFromTrack() {
        guard case let .active(round, hole) = state else { return }
        let shots = ((try? ShotRepository.shotsForHole(hole.id)) ?? [])
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
        guard !shots.isEmpty else { return }
        guard !shots.contains(where: { $0.source == .reconstructed }) else { return }

        let green = GlassesStateMapper.greenCoordinate(
            courseId: round.curatedCourseId, holeNumber: hole.holeNumber)
        let tee = GlassesStateMapper.teeCoordinate(
            courseId: round.curatedCourseId, holeNumber: hole.holeNumber)
        let stops = (try? TrackSegmenter.stops(forHole: hole, in: round)) ?? []
        let recon = PathBReconstructor.reconstruct(score: shots.count, stops: stops,
                                                   tee: tee, green: green)

        for (shot, placed) in zip(shots, recon.shots) {
            var updated = shot
            updated.latitude = placed.latitude
            updated.longitude = placed.longitude
            updated.hadGPS = true
            updated.gpsAccuracy = nil
            updated.isPutt = placed.isPutt
            updated.source = .reconstructed
            updated.locationSource = .track
            updated.locationDisagreementMeters = nil
            updated.confidence = Self.pathBConfidence(placed)
            try? ShotRepository.update(updated)
        }
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
    }

    // MARK: - Late watch trail (B38)

    /// Quiet period after the last trail batch before holes are re-laid. A
    /// reconnect delivers a burst of batches within seconds; re-laying per batch
    /// would redo the same work dozens of times.
    @ObservationIgnored
    var relayDebounce: TimeInterval = 1.0

    @ObservationIgnored
    private var pendingRelay: [UUID: ClosedRange<Date>] = [:]

    @ObservationIgnored
    private var relayTimer: Timer?

    /// Number of (round) re-lay passes run so far; the burst test pins this.
    @ObservationIgnored
    private(set) var relayPassCount = 0

    /// Trail points just landed for these rounds/time spans. Collects them and
    /// re-lays once after the burst settles.
    func noteWatchTrail(_ spans: [UUID: ClosedRange<Date>]) {
        for (roundID, span) in spans {
            let merged = pendingRelay[roundID].map {
                min($0.lowerBound, span.lowerBound)...max($0.upperBound, span.upperBound)
            }
            pendingRelay[roundID] = merged ?? span
        }
        relayTimer?.invalidate()
        relayTimer = Timer.scheduledTimer(withTimeInterval: relayDebounce, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.runPendingRelay() }
        }
    }

    private func runPendingRelay() {
        let spans = pendingRelay
        pendingRelay = [:]
        relayTimer = nil
        watchTrailArrived(spans: spans)
    }

    /// Re-lay holes the SYSTEM placed from the track, now that a better trail
    /// exists. Per round, reads the holes/shots/trail once, and touches only holes
    /// whose time window overlaps the new fixes.
    ///
    /// Safety: a hole is only touched when EVERY stroke on it is system-placed
    /// (`.reconstructed` with `locationSource == .track`, or still unlocated).
    /// Every hand placement is tagged `manual` (snapped or not), and a watch-fixed
    /// stroke is `watch`, so either makes the whole hole off limits: placement is
    /// positional (stroke N to stop N), so we never move some strokes around
    /// others. Holes open in review/detail (`HolesUnderEdit`) are skipped too.
    func watchTrailArrived(spans: [UUID: ClosedRange<Date>]) {
        guard !spans.isEmpty, let rounds = try? RoundRepository.allRounds() else { return }
        for round in rounds {
            guard let span = spans[round.id], let track = try? TrackSegmenter.roundTrack(for: round) else { continue }
            relayPassCount += 1
            for hole in track.holes where !HolesUnderEdit.contains(hole.id) {
                guard let window = track.window(for: hole), window.overlaps(span) else { continue }
                replaceTrackPlacement(hole: hole, in: track)
            }
        }
        if case let .active(_, hole) = state {
            currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? currentHoleShots
        }
    }

    private func replaceTrackPlacement(hole: Hole, in track: TrackSegmenter.RoundTrack) {
        let shots = ((try? ShotRepository.shotsForHole(hole.id)) ?? [])
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
        guard !shots.isEmpty, shots.contains(where: { $0.locationSource == .track }),
              shots.allSatisfy({ $0.source == .reconstructed && ($0.locationSource == .track || $0.latitude == nil) })
        else { return }
        let round = track.round
        let green = GlassesStateMapper.greenCoordinate(courseId: round.curatedCourseId, holeNumber: hole.holeNumber)
        let tee = GlassesStateMapper.teeCoordinate(courseId: round.curatedCourseId, holeNumber: hole.holeNumber)
        let stops = TrackSegmenter.detectStops(in: track.trail(for: hole))
        let recon = PathBReconstructor.reconstruct(score: shots.count, stops: stops, tee: tee, green: green)
        for (shot, placed) in zip(shots, recon.shots) {
            var updated = shot
            updated.latitude = placed.latitude
            updated.longitude = placed.longitude
            updated.hadGPS = true
            updated.gpsAccuracy = nil
            updated.isPutt = placed.isPutt
            updated.locationSource = .track
            updated.confidence = Self.pathBConfidence(placed)
            guard updated != shot else { continue }
            try? ShotRepository.update(updated)
        }
    }

    /// Confidence for a Path-B placed pin: a fallback guess (no dwell behind it)
    /// is flagged for the golfer to drag; a putt on the green or a dwell-placed
    /// full shot is a reasonable guess that doesn't shout for attention.
    private static func pathBConfidence(_ s: PathBShot) -> Double {
        if !s.placedFromDwell { return 0.3 } // fallback drop → amber "check"
        return s.isPutt ? 1.0 : 0.7
    }

    /// Switch the active hole to `number` — for flexible navigation (prev/next
    /// arrows, the hole grid). Returns to an existing hole row if one exists
    /// (preserving its shots/par), else creates it. Does NOT confirm the hole
    /// being left, so skipping ahead leaves it open to return to. Refreshes the
    /// observable shot/penalty lists and persists the active hole for resume.
    func goToHole(_ number: Int) {
        guard case let .active(round, current) = state else { return }
        guard (1...Self.holesPerRound).contains(number), number != current.holeNumber else { return }
        let hole: Hole
        if let existing = try? HoleRepository.hole(forRound: round.id, number: number) {
            hole = existing
        } else {
            let new = Hole(id: UUID(), roundID: round.id, holeNumber: number, par: nil, confirmedAt: nil)
            try? HoleRepository.insert(new)
            hole = new
        }
        state = .active(round: round, hole: hole)
        UserDefaults.standard.set(hole.id.uuidString, forKey: Self.activeHoleKey(round.id))
        currentHoleShots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
        currentHolePenalties = (try? PenaltyRepository.penaltiesForHole(hole.id)) ?? []
        currentClub = nil
        lastMarkResult = nil
        autoFillParIfAvailable()
    }

    /// Step to the adjacent hole (wrapping 1...18) without confirming — the
    /// prev/next arrows.
    func stepHole(by delta: Int) {
        guard case let .active(_, current) = state else { return }
        let next = ((current.holeNumber - 1 + delta + Self.holesPerRound) % Self.holesPerRound) + 1
        goToHole(next)
    }

    /// All hole rows for the active round (for the hole-grid overview).
    func holesForCurrentRound() -> [Hole] {
        guard case let .active(round, _) = state else { return [] }
        return (try? HoleRepository.holesForRound(round.id)) ?? []
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
    /// user-retry double-log.
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
        // B34: the G2 fires doubled tap events (same burst-y hardware behavior
        // behind the B23 scroll coalescer), and the glasses' in-flight write
        // guard can't catch them — the loopback POST completes faster than the
        // gap between the duplicates — so every input-mode tap logged TWO
        // shots (field 2026-07). Same guard as the phone Mark button: drop a
        // repeat inside the window, putts EXEMPT (batch-logged rapid taps are
        // real — B30). Dedicated timestamp, NOT lastGlassesActionAt: an undo
        // must not block the next legitimate shot. Silent return (200 OK) per
        // the undo-cooldown precedent — the next poll reconciles the count.
        let isPutt = Shot.derivedIsPutt(club: currentClub)
        if !isPutt {
            if let last = lastGlassesShotAt,
               Date().timeIntervalSince(last) < doubleTapThreshold {
                return
            }
            lastGlassesShotAt = Date()
        }
        let choice = currentLocationChoice()
        let hasFix = choice.fix != nil
        let nextSeq = (try? ShotRepository.nextSequenceNumber(forHole: hole.id)) ?? 1
        let shot = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: nextSeq,
            timestamp: Date(),
            latitude: choice.fix?.latitude,
            longitude: choice.fix?.longitude,
            gpsAccuracy: choice.fix?.horizontalAccuracy,
            hadGPS: hasFix,
            club: currentClub?.id,
            source: .glasses,
            notes: nil,
            isPutt: isPutt, // B31 gap: this path never derived the putt flag
            locationSource: ShotLocationSource(choice.source),
            locationDisagreementMeters: choice.disagreementMeters
        )
        try ShotRepository.insert(shot)
        currentHoleShots.append(shot)
        lastMarkResult = .success(shotID: shot.id, accuracy: choice.fix?.horizontalAccuracy)
        lastGlassesActionAt = Date()
        if hasFix { Haptics.success() } else { Haptics.warning() }
    }

    /// Undo for the glasses Actions screen. Thin wrapper around
    /// `undoLastAction` that adds the no-active-hole error the glasses
    /// contract expects (the phone path returns silently instead — the Undo
    /// button is only shown during an active round). No-op (not an error)
    /// when there is nothing to undo OR when fired within `glassesUndoCooldown`
    /// of the previous glasses action (shot or undo) — see
    /// `lastGlassesActionAt` for rationale. Silent return matches the
    /// existing `markShotInternal` double-tap guard: the glasses contract
    /// still returns 200 OK, no special-casing needed at the firmware end.
    func undoLastActionFromGlasses() throws {
        guard case .active = state else {
            throw GlassesError.noActiveHole
        }
        if let last = lastGlassesActionAt,
           Date().timeIntervalSince(last) < glassesUndoCooldown {
            return
        }
        try undoLastAction()
        lastGlassesActionAt = Date()
    }

    func markShot() async throws {
        try await markShotInternal(source: .button, club: currentClub)
    }

    /// Quick one-tap putt from the phone round screen — a putter stroke at the
    /// live fix, regardless of the currently-selected club (putts otherwise mean
    /// scrolling the club picker to Putter). Goes through the normal mark path
    /// (double-tap guard, GPS fusion) so it's a first-class stroke. Tagged
    /// `isPutt` so the green-split / no-distance rules see it (B3).
    func markPutt() async throws {
        try await markShotInternal(source: .button, club: resolvedPutter(), isPutt: true)
    }

    /// Flip the active round between full shot-tracking and casual GPS+score.
    func setCasualMode(_ on: Bool) {
        isCasualMode = on
        UserDefaults.standard.set(on, forKey: Self.casualCurrentKey)
        guard case let .active(round, hole) = state else { return }
        var updated = round
        updated.mode = on ? .casual : .tracking
        guard updated != round, (try? RoundRepository.update(updated)) != nil else { return }
        state = .active(round: updated, hole: hole)
    }

    /// Casual "+1 stroke" — a detail-less manual stroke (no club). Hole score is
    /// just the stroke count, so every existing scorecard/summary reads it
    /// unchanged; `−` is the usual `undoLastAction()`.
    func addCasualStroke() async throws {
        try await markShotInternal(source: .manual, club: nil)
    }

    func markShotFromActionButton() async throws {
        try await markShotInternal(source: .actionButton, club: nil)
    }

    private func markShotInternal(source: ShotSource, club: Club?, isPutt: Bool = false) async throws {
        // B31: putter club ⇒ putt, whatever the caller passed — so a Mark tap
        // with Putter as the selected club is a first-class putt.
        let resolvedIsPutt = Shot.derivedIsPutt(club: club, explicit: isPutt)
        // The double-tap guard exists for the physical Action button / on-screen
        // double-press on a *full shot* (you don't hit two in a second). Putts are
        // EXEMPT — including Marks with the putter selected (B31): they're commonly
        // batch-logged a few rapid taps at a time after the fact (sink it, then
        // catch up), and this guard was silently dropping them — a par-3 played
        // to 6 got scored 3 (field: Oaks North South h1, 2026-07-02; same lesson
        // as the reverted watch debounce B26). A deliberate single glasses gesture
        // must not be deduped either; the glasses path doesn't go through here anyway.
        if (source == .button || source == .actionButton) && !resolvedIsPutt {
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
        // Location comes from the continuous best-accuracy track (`latestLocation`),
        // NOT a per-shot `captureBestFix` ramp (B8). During a round, tracking is
        // always running so `latestLocation` is fresh — and this removes the
        // up-to-5 s stall the field test felt standing on the phone Mark button
        // (FT4 #6). It unifies all live logging (phone/watch/glasses) on one
        // mechanism; reconstruction (B5–B7) refines locations from the track later.
        let choice = currentLocationChoice()
        let hasFix = choice.fix != nil
        let nextSeq = (try? ShotRepository.nextSequenceNumber(forHole: hole.id)) ?? 1
        let shot = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: nextSeq,
            timestamp: Date(),
            latitude: choice.fix?.latitude,
            longitude: choice.fix?.longitude,
            gpsAccuracy: choice.fix?.horizontalAccuracy,
            hadGPS: hasFix,
            club: club?.id,
            source: source,
            notes: nil,
            isPutt: resolvedIsPutt,
            locationSource: ShotLocationSource(choice.source),
            locationDisagreementMeters: choice.disagreementMeters
        )
        try ShotRepository.insert(shot)
        currentHoleShots.append(shot)
        lastMarkResult = .success(shotID: shot.id, accuracy: choice.fix?.horizontalAccuracy)

        if hasFix {
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }
}
