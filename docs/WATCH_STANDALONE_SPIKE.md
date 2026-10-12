# Watch-standalone spike — on-wrist GPS, course cache, local yardage

> **Status (2026-09-19):** steps 1–6 built on `spike/watch-standalone` (PR #14, review
> round 1 addressed) — watch + phone build in Debug and Release, 159 phone tests green,
> **not yet run on a device**. A simulator build and phone unit tests establish none of the device outcomes
> below (permissions, wrist-down updates, disconnected yardage, saved route, GPS, battery). Steps 7–8 (analysis script, Action Button) follow.
> **Supersedes** `WATCH_FEASIBILITY.md`, which predates the watch app and assumed a
> Series 6 battery budget.

## Why now

The watch app was designed around a Series 6 with a degraded battery: the watch is a
sensor + remote, the phone owns GPS / DB / course data / round state, and the wrist
yardage is a phone value pushed every 4 s. The watch is now an **Apple Watch Ultra 4**,
so the battery constraint is gone and the goal changes:

- The app keeps working as a **standalone phone app** (unchanged).
- With the watch paired, a round can also be **run from the watch**.

## Research summary (2026-09-19)

**Ultra 4** (Apple tech specs; DC Rainmaker review)
- Battery: 18 h outdoor workout with full GPS + HR, 50 h normal use. A 5 h round should
  cost roughly 25–30 % before our 100 Hz motion load (estimate — the spike measures it).
- Dual-frequency L1/L5 GPS. **Assumption to verify on the actual device:** watchOS is
  documented to source location from the paired phone while it's in Bluetooth range and
  from the watch's own receiver otherwise. No API reports which receiver produced a fix,
  so this is inferred, not observed — see "GPS-routing check" below before reading
  anything into the paired-vs-disconnected comparison.
- S11, 64 GB, 422×514 always-on display refreshing at 1 Hz (suits a wrist-down yardage
  face). Public motion limits unchanged: 800 Hz accel / 200 Hz device motion via
  `CMBatchedSensorManager`.
- Action Button unchanged: third-party apps get start / pause / resume workout intents;
  a custom mid-workout action ("mark shot") is limited — verify on device.

**watchOS 27 / iOS 27**
- New: HealthKit workout zones, Foundation Models + Vision on the watch. No changes found
  in CoreLocation, CoreMotion, MapKit or WatchConnectivity. No Apple golf API or course
  data.
- watchOS 27 drops Series 6–8, the first Ultra and SE 2.
- iOS 27 SDK requires a launch screen + scene lifecycle (we have both).
- Nothing here needs Xcode 27 or a higher deployment target; the design rests on APIs
  shipping since watchOS 10/11.

**APIs the design uses**
- `HKLiveWorkoutBuilder` + `HKWorkoutRouteBuilder` — a real golf workout with a route.
- `startMirroringToCompanionDevice` / `sendToRemoteWorkoutSession(data:)` — live
  watch→phone channel for a watch-led round with the phone bridging to the glasses.
- `WKRunsIndependentlyOfCompanionApp` — watch app runs without the phone app present.
- `URLSession` on the watch — direct catalog fetch over Wi-Fi / cellular.

## Target architecture (after the spike)

- **One shared round engine** — models, `RoundController`, the reconstructors and GRDB
  compiled into both targets.
- **One owner per round** — whichever device starts the round owns and writes it; the
  other mirrors.
- **Phone-started round** — exactly as today, glasses included; watch is sensor + remote.
- **Watch-started round** — the watch owns GPS, shots and the DB. Phone nearby: it
  receives live state through workout mirroring and keeps serving the glasses (the G2 HUD
  is a WebView in the Even App on the phone — it always needs the phone). Phone absent:
  the round syncs afterwards as a file transfer, deduplicated by round UUID.

## The spike

Three questions to answer **before** moving the round logic:

1. Is watch GPS good enough for yardages and for shot reconstruction?
2. What does a round with GPS + 100 Hz motion + always-on display cost in battery?
3. Can the watch hold course data and compute locally with the phone off?

Out of scope: shot logging on the watch, round ownership, a watch database.

### Steps

1. **Share the course types.** Wire structs (`GeoPoint`, `CuratedHole`, `CuratedCourse`,
   `CourseDataFile`) and `Distance` move to `GolfCaddie/Shared/` (the watch target already
   compiles it). GRDB record types stay on the phone.
2. **Course cache on the watch.** `WatchCourseStore` keeps the catalog as a JSON file in
   the watch's Documents. The phone pushes it with `transferFile`, carrying the in-app
   captured local anchors as **separate overrides** (they win over curated on the phone,
   so they must on the watch); fallback is a direct ETag fetch of the public catalog URL,
   which refreshes only the base — overrides keep precedence. Delivery is tracked: a push
   counts as delivered only on a successful `didFinish`, failures retry with backoff, and
   a watch that has never received a push (fresh install / reinstall) requests one. Course resolution: the phone's linked
   course id when a phone round is active, else nearest cached course by coordinate
   (no MapKit search — works offline).
3. **Watch GPS.** `WatchLocationProvider` — a trimmed `LocationManager` (best accuracy, no
   distance filter) started inside the workout session.
   `NSLocationWhenInUseUsageDescription` on the watch.
4. **A real workout.** `WorkoutKeeper` moves to `HKLiveWorkoutBuilder` + a route builder;
   filtered fixes feed the route; the round lands in Fitness with its map. Sessions under
   2 minutes are discarded so test starts don't litter Fitness.
5. **Local yardage.** `YardageScreen` computes distance-to-green from the watch fix + the
   cached green, falling back to the phone's pushed value; a small `W` / `P` marker shows
   **where the yardage was computed** (watch vs phone). It is *not* evidence of which
   device's GPS receiver produced the fix. The wrist value is actively cleared 20 s after
   the last good fix (timer-driven, not redraw-driven). Phone round active → the hole comes from the phone. No phone
   round → **watch-only**: course auto-picked, holes stepped with +/−.
6. **Telemetry** *(built)*. `WatchTelemetryRecorder` writes a session folder
   `telemetry-<yyyyMMdd-HHmmss>-<4hex>` per start→stop (format pinned in
   `Shared/WatchTelemetryFormat.swift` + tests):
   - `fixes.csv` — **every** fix received, unfiltered: `receivedAt, fixTime, lat, lng,
     hAcc, vAcc, alt, speed, speedAcc, course, reachable, hole, localYards, phoneYards`.
     `fixTime` is the join key against phone breadcrumbs; `reachable` (phone WC-reachable)
     segments the paired vs Bluetooth-off halves; the yardage columns give the
     watch-vs-phone yardage comparison directly.
   - `battery.csv` — level at start, every 5 min, at stop. `session.json` — device model,
     OS, build, fix count, battery start/end.
   - **On by default** (start-screen `GPS LOG ON/OFF`) — a forgotten toggle would waste a
     round. The toggle lives on the watch, not phone Settings, so it works watch-only.
   - Transfer at stop via `transferFile`; the watch deletes a file only after a confirmed
     `didFinish`, shows `N TO SEND` on the start screen, and re-queues leftovers at launch.
   - Phone stores to `Documents/WatchTelemetry/<session>/` in **Release too**; export from
     Settings → *Watch GPS Log* (share a zip) or Finder file sharing.
   - Phone-side data for the comparison is the existing round DB (Settings → Backup):
     breadcrumbs are throttled (≥1 s and ≥1 m, or 5 s when still) and only recorded during
     an **active phone round** — so the back-nine protocol needs a phone round running.
7. **Analysis script** *(follow-up)*. `scripts/` tool: phone DB export + watch track →
   median / p95 track gap, yardage disagreement at each shot time, `Reconstructor`
   placement error on the watch track vs the 12 m phone baseline.
8. **Action Button check** *(follow-up)*. `StartWorkoutIntent`; check on device whether a
   second press can mark a shot.

### Known limits of the 1–5 build

- **Watch-only is yardage + workout, not a round.** No shots are logged and nothing is
  stored as a round; swing detections are counted but the DetectCard is skipped. The UI
  labels the start as "WATCH ONLY · YARDAGE + WORKOUT". A full watch-owned round (shot
  logging, storage, sync) is the *next phase*, not this build.
- **Base-catalog recency isn't compared.** A phone push replaces the watch's base catalog
  even if the watch fetched a newer public file itself (the file has no version stamp).
  Both come from the same published file, so the window is small.
- **Health permissions changed** (route write, HR/energy read) — the watch re-prompts on
  the first start.
- Built with Xcode 27 (the machine's Xcode 26.6 lacks the watchOS platform); deployment
  targets unchanged.

### Device validation (required — nothing here is established yet)

1. **Permissions.** First start: location + Health prompts appear on the watch. Check
   grant, and check *deny* for each: denied location → no `W`, falls back to `P` / `–––`
   with no crash; denied Health → start reports the error.
2. **Catalog delivery.** Phone app open once → the watch-only screen shows a course name
   near a cached course instead of "No course data yet". Delete + reinstall the watch app
   → the catalog (including a locally captured green) comes back without changing anything
   on the phone.
3. **Phone-led yardage.** Header shows `· W` within a few seconds of starting; agrees with
   the phone within a few yards.
4. **Wrist-down updates.** Wrist down for a minute while walking, raise: the yardage is
   current, not frozen; always-on shows it ticking.
5. **Phone-disconnected cached yardage.** Phone Bluetooth off (or phone left behind), no
   phone round: start watch-only, course resolves from the cache, +/− steps holes,
   yardage follows.
6. **Expiry.** Walk indoors / cover the watch until fixes stop: within ~20 s `W` drops to
   `P` (phone-led) or `–––` (watch-only).
7. **Telemetry.** After a session the start screen shows `N TO SEND`, draining to nothing
   once the phone app is open; the session appears under Settings → Watch GPS Log with
   `fixes.csv`, `battery.csv`, `session.json`; `fixes.csv` has ~1 row/s including
   wrist-down stretches. Repeat with the phone unreachable at stop: files wait, then
   deliver on reconnect / next watch launch.
8. **Saved workout.** End a >2 min session: a Golf workout with a route map appears in
   Fitness. End a <2 min session: nothing is saved.

### GPS-routing check (before trusting paired-vs-disconnected conclusions)

`W`/`P` can't tell us which receiver produced a fix. With step 6 telemetry in place, compare
the watch-logged fixes against the phone's breadcrumbs for the same seconds:

- Paired, phone in pocket: near-identical coordinates/accuracy ⇒ the watch is being fed
  the phone's fixes (expected).
- Phone Bluetooth off: the tracks should diverge by normal GPS noise ⇒ the watch's own
  receiver. If they *don't* diverge, or the watch stops getting fixes, the routing
  assumption is wrong for this hardware/OS and the back-nine protocol needs rethinking.

Only the disconnected segment says anything about the Ultra 4's own GPS.

### Field test protocol

- **Front nine:** phone in pocket, paired as usual — baseline; shows whether the watch is
  just borrowing the phone's GPS.
- **Back nine:** phone Bluetooth off, phone still tracking in the pocket **with the phone
  round still running** — two independent tracks and a true standalone test. Use the
  watch's Next Hole as normal: the watch steps its own hole immediately (the phone can't
  answer), so the wrist yardage stays on the hole being played.
- **On reconnect** the queued hole's-worth of watch traffic replays in order: a hole change
  first commits the swings played before it, later taps wait their turn, and a late
  MARK/putt is stamped with the watch's tap time and the breadcrumb from then (no
  breadcrumb near that time ⇒ no GPS, never the phone's current position). Found by
  reading the replay path before the round — previously every queued Next Hole applied
  first and all swings were logged to the last hole. **Check after the round:** back-nine
  swings sit on their own holes in the phone scorecard.

### Pass criteria

- Median gap between the two tracks ≤ ~5 m.
- Yardages agree within ~3 yd.
- Battery ≤ 35 % for 18 holes.
- Always-on display shows yardage updating about once a second.
- The watch-only nine works end to end.

If it passes: next phase moves the round engine + GRDB to the watch, then workout
mirroring.
