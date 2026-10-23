# The watch owns the round — design (next phase)

> **Status (2026-10-22):** design only, no code. Follows `WATCH_STANDALONE_SPIKE.md`
> (field test 1 passed: "go on the watch owns the round") and builds on B35 (watch GPS
> first) and B38 (watch trail), both on `main`. Open decisions (**🔵 Q1–Q6**) are in
> "Risks and open questions" at the end. File:line anchors are from `main` at b4cef6e and
> are starting points; confirm them by reading the code.

## 1. Goal and non-goals

**Goal.** A round started on the watch can be played start to finish with **no phone**:
scoring, shots (auto-detected and tapped), penalties, Finish Hole, the trail, and the
end-of-hole reconstruction. When the phone comes back in range, it gets the round and
becomes a **viewer and editor**. It does not become a second writer.

Keep all four configurations from `RECONCILED_BACKLOG.md` §7 working:

| Config | Who owns the round | What changes |
|---|---|---|
| Phone only | phone | nothing |
| Phone + glasses | phone | nothing |
| Phone + watch | whoever started it | a watch-started round runs on the watch; a phone-started one runs as today |
| All three | whoever started it | a watch-started round: the phone mirrors it and keeps serving the glasses HUD |

**Non-goals (this phase):** glasses with no phone (the G2 HUD is a WebView in the Even
App on the phone, `WATCH_FEASIBILITY.md`); two devices writing one round at once (no CRDT,
no edit merging); moving a round from phone to watch mid-play (§2); course search on the
watch (cached catalog only); changing the reconstruction algorithms (they move unchanged);
cellular or iCloud sync (WatchConnectivity is the only transport).

## 2. Ownership model

**One owner per round, recorded on the round.** Migration v10 adds `round.owner`
(`phone` | `watch`, default `phone`, so every existing round stays phone-owned),
`round.ownerEpoch` (0, +1 on every handoff: a fencing token) and `originDevice` (info).

- **The device that starts the round owns it.** Watch Start Round → `owner = watch`.
  Phone Start Round → `owner = phone`, exactly today's behavior (watch = sensor + remote,
  `LiveShotCoordinator` path unchanged).
- **Only the owner writes the round's rows** (round, hole, shot, penalty). The other
  device keeps a **mirror** (same rows, its own GRDB), written only by applying the
  owner's events (§5).
- **A non-owner edit is a request:** a command to the owner, which applies it and emits
  events — today's watch-command pattern, in the other direction.

**Handoff.** There are three cases. Only the first is needed for v1.
1. **Round end, watch → phone (automatic, v1).** End Round emits `roundEnded`. Once the
   phone has applied every event up to the final `seq` (§5 acks), the watch emits
   `ownerHandoff(to: phone, epoch + 1)` and the phone owns post-round work (review, pin
   drags, move stroke, restore excluded, link course). That editing already lives on the
   phone (`HoleDetailView`, `HoleReviewSheet`), so it stays single-writer with no new UI.
   Until then the phone shows the round read-only, "Syncing from watch".
2. **Mid-round lifeboat, watch → phone (v1.1).** Watch battery < 15 % or the workout
   failed (B19): the watch flushes, emits `ownerHandoff`, and the phone carries on as a
   phone round; glasses input is the backup again (B18).
3. **Forced takeover (v1.1).** The watch is dead or lost. The phone can **Take over this
   round**: bump `ownerEpoch`, own what it has mirrored. Old-epoch events arriving later
   are **not applied**; they land in a "Recovered from watch" list to apply or discard in
   review. Late data is never merged silently.

Moving a round from the phone to the watch in the middle of play is **not planned**
(🔵 Q2). Starting on the watch covers the case of leaving the phone in the car.

**Conflict rules**
- **One active round per golfer.** Phone aware of an active watch-owned round → its
  Start Round becomes **View watch round**; a watch aware of a phone round shows it, as
  today.
- **Both started a round while apart.** Two overlapping active rounds on reconnect: keep
  both, never auto-merge, flag on phone home "keep watch / keep phone / keep both" (🔵 Q3).
- **Edit to something gone** (e.g. a club edit on a shot Finish Hole excluded): the owner
  emits `commandRejected(id, reason)`, the phone shows a notice. The owner always wins.
- **Stale epoch:** any event or command below the round's epoch is quarantined (case 3).

## 3. Shared round engine

Today the round logic lives in `RoundController` (`GolfCaddie/Capture/RoundController.swift`,
1,205 lines). It is `@MainActor @Observable`, it calls the static GRDB repositories
directly, and it is mixed in with phone-only concerns: `LocationManager`, MapKit course
naming, glasses cooldowns, `UserDefaults`. The plan is to split it into a **pure state
machine** and a **repository protocol**, both in Shared, with a thin adapter on each
device.

### Shape

```swift
// GolfCaddie/Shared/RoundEngine/
struct RoundState: Equatable {          // round, hole, holes, currentHoleShots,
                                        // currentHolePenalties, currentClub, clubEpoch, isCasual
}
enum RoundIntent {                      // what a UI / watch / glasses asked for
  case start(StartOptions), end, resume, goToHole(Int), confirmAndAdvance(par: Int?)
  case finishHole(putts: Int, score: Int, at: Date)
  case logShot(ShotInput)               // time + LocationChoice + club + source + isPutt
  case insertMissing(coord, club), removeShot(UUID), undo, editClub(UUID, Club?)
  case addPenalty(PenaltyType, at: Date), setPar(UUID, Int?), setClubsLeftOut([String])
  case linkCourse(String?), placeHoleFromTrack, relayHoles(ClosedRange<Date>)
}
enum RoundEffect: Codable, Equatable {  // row-level facts; also the sync events (§5)
  case upsertRound(Round), upsertHole(Hole), insertShot(Shot), updateShot(Shot)
  case deleteShotAndRenumber(UUID), setExcluded([UUID], at: Date?)
  case insertPenalty(Penalty), deletePenalty(UUID)
}
struct RoundEngine {
  func reduce(_ s: RoundState, _ i: RoundIntent, _ ctx: RoundContext) throws
      -> (RoundState, [RoundEffect])
}
protocol RoundStore {                   // GRDB on both devices; in-memory for tests
  func apply(_ effects: [RoundEffect]) throws          // one transaction
  func shots(hole: UUID) throws -> [Shot]; func holes(round: UUID) throws -> [Hole]
  func penalties(hole: UUID) throws -> [Penalty]; func preferredTrail(round: UUID, from: Date, to: Date?) throws -> [TracePoint]
  func nextSequenceNumber(hole: UUID) throws -> Int
}
protocol CourseGeometry {               // phone: CourseDataRepository + LocalAnchorRepository
  func green(_ courseId: String?, _ hole: Int) -> CLLocationCoordinate2D?   // watch: WatchCourseStore
  func tee(_ courseId: String?, _ hole: Int) -> CLLocationCoordinate2D?
  func par(_ courseId: String?, _ hole: Int) -> Int?
}
struct RoundContext { store: RoundStore; geometry: CourseGeometry; clubs: [Club]; now: Date }
```

The effects are both the persistence diff and the sync payload. The device that writes
them and the device that mirrors them apply exactly the same list through the same
`RoundStore.apply`, so the mirror cannot drift from the owner because of different logic.

### What moves, from where

| Into the engine (Shared) | Today |
|---|---|
| start / end / resume / restore state | `RoundController.startRound` :208, `endRound` :249, `resumeRound` :722, `restoreActiveRound` :176 |
| hole navigation | `goToHole` :983, `stepHole` :1005, `confirmHoleAndAdvance` :802 |
| Finish Hole | `finishHole` :586 + `append` :614, `resolvedPutter` :624 |
| shot logging core | `ingestAutoShot` :467 (incl. `SameSwingDedup`, `TeeSnap`), `addShotFromWatch` :539, `addPuttFromWatch` :574, core of `markShotInternal` :1146 and `logShotFromGlasses` :1048 |
| edits | `insertMissingShot` :433, `removeShot` :632, `deleteShot` :715, `updateShotClub` :653, `undoLastAction` :691, `addPenaltyToCurrentHole` :670, `setPar` :1026, `setClubsLeftOut` :294 |
| course link + auto-par | `applyCuratedCourseId` :365, `autoFillParIfAvailable` :408 (behind `CourseGeometry`) |
| reconstruction | `reconstructHole` :821, `placeCurrentHoleFromTrack` :849, `replaceTrackPlacement` :945, `pathBConfidence` :973 |

| Moved to Shared unchanged (already pure, depend only on CoreLocation + models) | File |
|---|---|
| `Reconstructor`, `ReconstructionConfig`, `SameSwingDedup` | `Capture/Reconstructor.swift` |
| `PathBReconstructor`, `PathBConfig` | `Capture/PathBReconstructor.swift` |
| `HoleFinishReconciler` | `Capture/HoleFinishReconciler.swift` |
| `ShotReconciler`, `StepCounting` (CMPedometer works on watchOS) | `Capture/ShotReconciler.swift` |
| `TrackSegmenter` pure half (`timeWindow`, `points`, `detectStops`, `RoundTrack`) | `Capture/TrackSegmenter.swift`. `roundTrack(for:)` becomes a `RoundStore` read |
| `TrailMerge.preferred`, `ShotPlacement` | `Capture/TrailMerge.swift`. `trail(forHole:)` becomes a store read |
| `RecentIDSet` | `Capture/LiveShotCoordinator.swift` :16 |
| Models `Round`, `Hole`, `Shot`, `Penalty`, `TracePoint`, `Club`, `ClubsInPlay` | `GolfCaddie/Models/` (they conform to GRDB records, so the watch links GRDB, §4) |
| `Database.migrator` | `Persistence/Database.swift` :36, as `Shared/Persistence/Schema.swift` |

**Stays on the phone,** in `RoundController`, which becomes the `@Observable` adapter
that holds `RoundState`, calls `reduce`, applies the effects and publishes: `LocationManager`
and `recordBreadcrumb` :133 (becomes a `TrailSink` both devices implement), MapKit course
naming (`detectAndApplyCourseName` :325), glasses cooldowns and
`mostRecentlyConfirmedHoleFromGlasses`, the active hole in `UserDefaults`, the relay
debounce timer (`noteWatchTrail` :900), casual-mode defaults.

`LiveShotCoordinator` keeps the phone-owned swing pipeline, which is debounce, then
reconciliation, then fusion (`commit` :294, `fuse` :316, `watchTap` :275). The watch gets
a `WatchRoundController` adapter with the same shape. Its swing pipeline is shorter
because each detection already carries its own time and fix: `LocationPreference.choose(
watch: ownFix, phone: nil)`, falling back to the nearest point of the watch's own trail.

### Extraction without breaking the phone

1. The existing ~205 phone tests (`HoleFinishReconcilerTests`, `WatchReplayOrderingTests`,
   `WatchTrailPlacementTests`, `LiveMarkPathTests`, …) are the characterization suite and
   run unchanged against the adapter (import edits only).
2. Move the pure types first, then reroute one `RoundController` method at a time through
   `reduce` + `GRDBRoundStore`, one green commit per step.
3. Engine tests live in the **phone** test target (the watch has none; the `WatchCaddie`
   precedent), with an `InMemoryRoundStore` and a "same intents, same effects, any store"
   property test.

### Reconstruction on the watch: CPU and battery

Per hole the inputs are small: `Reconstructor` and `HoleFinishReconciler` see under 15
shots; `PathBReconstructor` + `detectStops` see ~15 min of trail thinned to 1 fix per
2 s or 3 m (`WatchTrailRecorder`), about 450 points in one linear pass. Well under 10 ms on an S11, once per hole. The late re-lay (`watchTrailArrived`) is not
needed on the watch (it has its own trail when the hole closes); the `ShotReconciler` step
gate is one CMPedometer query per burst. The real costs (GPS, 100 Hz motion, always-on)
already ran in field test 1. Estimate: < 1 % per round for engine + DB; measure it (§8).

## 4. Persistence on the watch

**Feasibility.** GRDB 7 supports watchOS 7+, we target watchOS 11 (`project.yml`), and
SQLite ships with the OS: add `- package: GRDB` to `GolfCaddieWatch`. Expect ~1–2 MB of
binary (measure in the phase 1 PR).

**One schema, one migrator.** Both devices run the **same** `Schema.migrator`, with all
migrations v1–v9 plus new ones registered under the same names. The watch creates every
table but uses a subset:

| Used on the watch | Not used on the watch (created, left empty) |
|---|---|
| `round`, `hole`, `shot`, `penalty`, `tracePoint`, `club`, `clubConfiguration`, new `roundEvent` | `curatedCourse`, `curatedSyncMeta`, `localCourseAnchor` (the watch keeps `WatchCourseStore`'s JSON) |

One migration list, one `MigrationTests`, no drifting "watch schema". A subset migrator
would save a few KB and add a second list of names to keep in step: not worth it.

**New migrations**
- `v10_round_ownership`: adds `round.owner` (TEXT NOT NULL DEFAULT 'phone'),
  `ownerEpoch` (INTEGER NOT NULL DEFAULT 0) and `originDevice` (TEXT).
- `v11_round_event_log`: adds the `roundEvent` table with columns `id` (TEXT PK, the
  event UUID), `roundID`, `epoch`, `seq` (INTEGER), `kind`, `payloadJSON`, `createdAt`,
  `ackedAt` (owner side) and `appliedAt` (mirror side). Adds UNIQUE(`roundID`, `epoch`,
  `seq`) and an index on (`roundID`, `ackedAt`).
- `v12_trace_point_batch` (optional): adds `tracePoint.batchId` so trail dedup does
  not depend on point-id derivation alone.

**Risks**
- **App killed by the system** (workout ended, crash, memory pressure, OS update). Every
  intent commits in one GRDB transaction before the UI confirms it with a haptic: the DB
  is the state, memory only a cache. On launch with an active watch-owned round,
  `HKHealthStore.recoverActiveWorkoutSession` resumes the workout and the engine reloads
  from the DB. The trail buffer is in memory today (up to 60 s lost on a kill, B38 "Not
  verified"); it moves to `tracePoint` rows written every 10 s in one transaction, and
  the WC flush reads from the DB.
- **Watch storage.** A 4.5 h round is ~8k trail rows (~0.5 MB with indexes), ~100 shots,
  ~300 events: small on any watch. Keep watch-owned rounds 30 days after the handoff ack,
  then delete them on the watch (the phone keeps them). Raw 100 Hz files stay DEBUG (B20).
- **File protection** `.completeUntilFirstUserAuthentication`, so writes work wrist-down.
  **`DatabaseQueue`**, not a pool: one process, no app-group container, no lock kills.
- **Schema skew** between builds: events carry `ShotContract.version`; the phone rejects
  an unknown event kind ("Update the phone app") and never applies a partial event.

## 5. Sync protocol

**An append-only event log, written by the owner and replayed on the mirror.** An event
is a `RoundEffect` list from one `reduce` call, wrapped in an envelope:

```swift
struct RoundEvent: Codable { id: UUID; roundID: UUID; epoch: Int; seq: Int
                             causedBy: UUID?      // the IdentifiedCommand id, if any
                             effects: [RoundEffect]; createdAt: Double }
```

- **Facts, not commands.** The mirror **does not** re-run the engine: that would need
  the same catalog, bag, pedometer answer and trail on both devices. Row facts are
  deterministic.
- **Ordering.** `seq` increases by 1 per round and epoch, with no gaps, and is assigned in
  the same transaction that writes the effects. The mirror applies strictly in `seq`
  order. An event that arrives early is held in `roundEvent` (not applied) until the gap
  fills. Event time stamps are for display only; they never decide order, so watch↔phone
  clock skew does not matter.
- **Dedupe.** Each event carries the id of the command that caused it (`causedBy`, the
  existing `IdentifiedCommand.id` from B2). On the mirror, UNIQUE(`roundID`, `epoch`,
  `seq`) plus the event `id` make redelivery a no-op. This replaces the in-memory
  64-entry `RecentIDSet` for watch-owned rounds with a persistent check that survives a
  phone relaunch.
- **Transport** reuses the existing channels. Events ride `transferUserInfo` under a new
  `ShotContract.eventKey` (queued, FIFO, survives disconnects), and **also** `sendMessage`
  when reachable so the mirror and glasses update within ~1 s (the queued copy then dedupes).
  **Acks** go phone→watch in `updateApplicationContext` (latest-wins suits a monotonic ack):
  `syncAck: [roundID: lastAppliedSeq]`; the watch sets `ackedAt`, and its "SYNCING N" chip
  (B4) counts unacked events instead of WC transfers. **Phone→watch commands** (§2) use
  `sendMessage` if reachable, else `transferUserInfo`: `IdentifiedCommand`s with new edit
  cases (`moveShot`, `placeShot(id, coord)`, `setPar`, `linkCourse`, `restoreExcluded`).
- **Long separation and reconnect.** WC delivers the queued events in order, and the
  mirror applies them as they arrive. Hours of play are about 300 small events, which is
  trivial. If the queue was lost (watch app reinstalled, WC session reset), the mirror
  notices a gap that stays open for more than 2 minutes while the watch is reachable,
  and sends `resendFrom(roundID, epoch, seq)`. The watch replays from `roundEvent`.
- **End-of-round checksum.** With `roundEnded`, the watch sends a hash of
  (shots, holes, penalties) in `seq` order. If the phone's mirror hash does not match, it
  asks for a **snapshot**: one `transferFile` with every row of the round, which replaces
  the mirror. This guards against logic bugs, not transport bugs; it should never fire.
  Log it if it does.

**How B35 and B38 fit in**
- **B35, watch GPS first.** In a watch-owned round, shots are located on the watch at
  capture time, `locationSource = watch`. The phone-side fusion (`fuse`, `watchTap`, the
  30 s `liveWindow` late-tap rule, `breadcrumb(near:)`) is **not used**, because the
  timestamp and fix come with the shot. The 2 s fix stream stays only for what the phone
  shows itself: the mirror's yardage and the glasses `distanceToGreenYards`.
  `LocationPreference` is unchanged and is used on both devices.
- **B38, watch trail.** Keeps its own channel (`ShotContract.trailKey`,
  `WatchTrailBatch`): high-volume, not a round fact. Simpler: batches gain an optional
  `roundID`, so `TraceIngest` files by id and keeps the time-window match (`assign` :27,
  600 s / 300 s slack) only for phone-owned rounds; batches are read from the DB, so they
  survive kills; the late re-lay (`noteWatchTrail`) is **not needed** for watch-owned
  rounds (the watch reconstructs from its own complete trail; results arrive as events).
  The phone's own breadcrumbs still land in the mirror (`source = phone`, never synced
  back), which keeps `compare-watch-track.py`'s routing comparison working.

## 6. Watch UX changes

**Start (no phone)**
- **Start Round** replaces "WATCH ONLY · YARDAGE + WORKOUT" (removed in phase 5).
- **Course:** nearest cached course within 3 km, auto-picked (the phone's rule,
  `CourseDataRepository.nearest(…, within: 3000)`); the Crown lists the 5 nearest. **No
  course** is allowed (scoring + trail, no yardage or green-split); the phone can
  `linkCourse` later, which re-runs reconstruction on the owner.
- **Starting hole** 1 or 10. **Clubs in play:** last round's pick, one tap to edit
  (PR #16 `clubsLeftOut`). Pre-start: battery %, GPS state, "Course data: N of 18 greens".

**Play.** The existing pages (Yardage, Strokes, Club grid, Actions, Score, Finish Hole,
penalties, Previous Hole) stay, and they read from the local engine instead of
`PhoneStateUpdate`.
- **Detections are logged.** Today watch-only mode counts them and drops them
  (`LiveSessionController.handleDetection` :272). Logging them needs B1 (auto-log + undo
  with a distinct haptic). Without B1, the 5 s confirm card still applies.
- `WatchCaddie.pendingHoleSteps` (the watch running ahead of the phone's hole) is not
  used: on a watch-owned round, the watch's hole is the hole.
- The status corner shows **SYNCED** or **N TO PHONE**, and **PHONE** when a mirror is
  live.

**End.** End Round sits on the Score page with a confirm step: score vs par and the
number of holes played. After that the workout is saved and the round goes to "Syncing
to phone" until the handoff is acked. **Resume:** if the app relaunches during an active
round, it returns straight to Play.

**Catalog and bag requirements**
- **Catalog.** The watch must have the catalog before going without the phone. The spike's
  catalog push already covers this, including a reinstall. Two additions:
  - A per-course **completeness flag**, green anchors for 18 of 18 holes, with tee anchors
    a plus (the B14 checklist).
  - A **version stamp** on the catalog file, so a phone push does not overwrite a newer
    file the watch fetched itself. This fixes the spike's "Base-catalog recency" known
    limit.
- **Bag.** The watch needs the `club` table and the bag, not just
  `PhoneStateUpdate.clubs`. Push them with the catalog (the same `transferFile` and hash
  scheme), and add the club `id` to `WatchClub` (additive), so `shot.club` stores ids as
  it does on the phone.

**Phone UX (viewer and editor).** A watch-owned round opens `ActiveRoundView` in
**mirror mode**: same map, card and scorecard, header "Watch round · synced 12 s ago".
Shot, putt and penalty controls send commands to the owner and show as pending (dimmed)
until its event returns; a rejection shows a notice. The glasses HUD reads the mirror;
glasses input is 🔵 Q4 (recommend read-only for v1).

## 7. Migration and rollout plan

Every phase is one PR that can ship on its own, behind a flag where it changes behavior.
After each phase all four configurations must work (`RECONCILED_BACKLOG.md` §7), and
`xcodegen generate` must run cleanly.

**Phase 1: extract the engine (phone-only behavior change: none)**
- Do the §3 moves. The watch target links GRDB and compiles `Shared/RoundEngine`, unused.
  `RoundController` and `LiveShotCoordinator` route through `reduce` + `GRDBRoundStore`.
- *Test:* full phone suite unchanged; new `RoundEngineTests` (`InMemoryRoundStore`, every
  intent, "same effects whatever the store"); watch + phone build Debug and Release; one
  phone-only nine on device, scorecard compared with the previous build.

**Phase 2: GRDB on the watch (no rounds yet)**
- The watch opens `golfcaddie.sqlite` with the shared migrator (+ v10, v11). The trail
  recorder writes `tracePoint` rows and `flushTrail` reads unsent rows (closes the 60 s
  kill gap). Nothing else changes.
- *Test:* `MigrationTests` for v10–v11 on a v9 fixture (phone rounds stay `owner = phone`);
  on device, force-quit the watch app mid-session → no trail gap beyond 10 s; record app
  size and battery on one nine.

**Phase 3: watch-owned rounds behind a flag** (`watchOwnedRounds`, off by default, a
DEBUG and TestFlight toggle on the watch)
- Watch Start Round, `WatchRoundController`, logged detections, Finish Hole on the watch,
  event outbox + acks, end-of-round handoff. The phone **applies events to a read-only
  mirror** (Logbook + scorecard; no live mirror UI yet).
- *Test:* engine tests for the watch swing path (own fix, then nearest own trail point);
  event tests on the phone target (out-of-order held then filled, duplicate is a no-op,
  gap → `resendFrom`, stale epoch quarantined, checksum mismatch → snapshot); simulator:
  3 holes with the phone app closed, then open it → mirror matches, handoff acked;
  device: 9 holes with the phone in airplane mode.

**Phase 4: phone viewer and editor**
- Mirror mode in `ActiveRoundView`, phone→watch commands (pending / rejected), glasses on
  a mirrored round, "View watch round" instead of Start, overlapping-round detection,
  lifeboat handoff (§2 case 2), forced takeover + "Recovered from watch" (case 3).
- *Test:* command round trip with the owner rejecting an edit to an excluded shot; the
  glasses contract `curl` checks against a mirrored round; takeover then late old-epoch
  events → nothing applied, all listed; all three devices on device for 3 holes.

**Phase 5: retire the old paths** (flag on by default, then removed)
- Remove watch-only mode (`WatchCaddie.watchOnlyHole`, the "WATCH ONLY" labels in
  `WatchRootView` :951) and `pendingHoleSteps`.
- If 🔵 Q1 is yes, "Start on phone with a reachable watch" creates a watch-owned round,
  and the phone-side swing fusion (`LiveShotCoordinator.commit`/`fuse`/`watchTap`,
  `RecentIDSet`) is kept only for phone + glasses rounds with a watch that is not
  reachable.
- Remove the time-window `TraceIngest.assign` for batches that carry `roundID`.
- Update `RECONCILED_BACKLOG.md` §4 "Device roles": the owner is the source of truth, not
  always the iPhone.
- *Test:* full suite after the deletions, four-config regression pass, one full 18.

## 8. Field-test plan

**Field test 2: watch-owned round, Bluetooth-off back nine.** This is the pending spike
protocol, now run on a phase 3 build.
- **Front nine:** watch-owned round, phone in pocket and paired, phone app open. The
  mirror updates live and the glasses are optional.
- **Back nine:** turn the phone's Bluetooth **off** and leave the phone in the cart.
  The watch plays alone. The phone keeps recording its own breadcrumbs into the mirrored
  round (§5, `source = phone`): the second track for the routing check.
- **Reconnect** at the 18th green. Time how long until the mirror has every event and the
  handoff is acked.
- **After the round:** `compare-watch-track.py` on the back nine shows the tracks
  diverging by normal GPS noise (settles which receiver the watch used); the mirror
  scorecard matches the watch hole by hole; the checksum matched with no snapshot.

**Battery budget.**
- Baseline, field test 1: **95→85 % over 2.0 h** ≈ 5 %/h (GPS + 100 Hz motion +
  always-on, Bluetooth on, phone-owned round).
- Budget, watch-owned: **≤ 6 %/h ≈ ≤ 30 % over 4.5 h** — inside the spike's ≤ 35 % and
  1 %/h of headroom for engine, DB, event traffic and logged detections.
- Record `battery.csv` (exists) plus event count, trail rows and DB size in
  `session.json` (new fields).

**Pass criteria**
- The back nine is fully playable with no phone: every hole scored, Finish Hole
  reconciled, and shots located with `locationSource = watch`.
- After reconnect, 100 % of events are applied within 2 minutes of the phone app
  opening, with zero duplicates (the DB export shows no repeated `causedBy`).
- The mirror matches the watch: the checksum matched, and per hole, the strokes, putts,
  penalties and excluded strokes are equal.
- Battery is ≤ 6 %/h over the whole round.
- No lost state after one deliberate force-quit of the watch app mid-hole.
- Glasses: on the front nine with the phone paired, the HUD tracks the watch round
  within about 2 s.

## 9. Risks and open questions

**Risks**
- **Watch app kills:** DB-first bounds the loss to ~10 s of trail; a kill with the
  confirm card up loses that one detection until B1 lands.
- **WC queue loss** (reinstall, re-pair to a new phone such as the Duo): the persistent
  outbox + `resendFrom` cover it; a new phone's empty mirror needs "send all rounds not
  yet handed off" on first contact.
- **Extraction regressions:** `RoundController` is the busiest file in the app. Phase 1
  must be behavior-neutral, covered by the existing suite, and carry no feature work.
- **Glasses latency:** glasses → watch owner → back is one `sendMessage` round trip
  (~0.3–1 s), which breaks read-after-write (`RECONCILED_BACKLOG.md` §4). See Q4.
- **Catalog gaps:** no green anchors → no yardage. The pre-round check shows it; it
  can't fix it on the course.

**🔵 Open questions for Moises**
1. **Q1 — Default owner when both are present.** When the phone starts a round and the
   watch is reachable, should the watch own it? That makes "phone + watch" always
   watch-owned and lets phase 5 retire most of the phone-side fusion. *Recommend: yes,
   after field test 2 passes.*
2. **Q2 — Phone→watch handoff mid-round** (start on the phone in the car park, then leave
   it in the cart). *Recommend: not in v1. Start on the watch instead.*
3. **Q3 — Overlapping rounds started on both devices while apart.** Keep both and ask, or
   let the watch round win automatically? *Recommend: keep both and ask; never merge.*
4. **Q4 — Glasses input on a watch-owned round.** Option (a): forward to the watch and
   relax read-after-write to "eventually, under about 1 s". Option (b): glasses are
   read-only on watch-owned rounds, since the watch is alive and is the input device.
   *Recommend: (b) for v1. Glasses input stays the lifeboat for phone-owned rounds and
   after a takeover.*
5. **Q5 — B1 before phase 3?** Logging detections on the watch with the 5 s auto-confirm
   card is the "phantom you never felt" problem B1 describes. *Recommend: land B1 first,
   or together with phase 3.*
6. **Q6 — Retention on the watch.** Delete watch-owned rounds 30 days after the handoff
   ack, or keep the last N rounds for an on-wrist history? *Recommend: 30 days, no
   on-wrist history in v1.*
