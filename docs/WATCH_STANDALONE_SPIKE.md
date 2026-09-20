# Watch-standalone spike — on-wrist GPS, course cache, local yardage

> **Status:** spike in progress on `spike/watch-standalone` (2026-09-19). Steps 1–5
> are the app build; steps 6–8 (telemetry, analysis script, Action Button) follow.
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
- Dual-frequency L1/L5 GPS. **The watch uses the phone's GPS whenever the phone is in
  Bluetooth range** — testing the watch's own GPS needs the phone out of range or with
  Bluetooth off.
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
   the watch's Documents. The phone pushes it with `transferFile` (with in-app captured
   local anchors overlaid, since those win over curated on the phone); fallback is a
   direct ETag fetch of the public catalog URL. Course resolution: the phone's linked
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
   which source is live. Phone round active → the hole comes from the phone. No phone
   round → **watch-only**: course auto-picked, holes stepped with +/−.
6. **Telemetry** *(follow-up)*. Log every watch fix (time, lat, lng, accuracy, speed) +
   battery every 5 min; transfer to the phone at round end behind a "Watch GPS spike"
   Settings toggle so it works in TestFlight builds.
7. **Analysis script** *(follow-up)*. `scripts/` tool: phone DB export + watch track →
   median / p95 track gap, yardage disagreement at each shot time, `Reconstructor`
   placement error on the watch track vs the 12 m phone baseline.
8. **Action Button check** *(follow-up)*. `StartWorkoutIntent`; check on device whether a
   second press can mark a shot.

### Field test protocol

- **Front nine:** phone in pocket, paired as usual — baseline; shows whether the watch is
  just borrowing the phone's GPS.
- **Back nine:** phone Bluetooth off, phone still tracking in the pocket — two independent
  tracks and a true standalone test. Queued swings are fused to the phone breadcrumb by
  *timestamp* (`TracePointRepository.nearest(toTimestamp:)`), so late delivery should
  still place shots correctly — confirm in the round.

### Pass criteria

- Median gap between the two tracks ≤ ~5 m.
- Yardages agree within ~3 yd.
- Battery ≤ 35 % for 18 holes.
- Always-on display shows yardage updating about once a second.
- The watch-only nine works end to end.

If it passes: next phase moves the round engine + GRDB to the watch, then workout
mirroring.
