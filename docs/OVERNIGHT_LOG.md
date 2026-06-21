# Overnight Agent Log — Foundations Batch (night 1, 2026-06-21)

Branch: `overnight/foundations-0621` (both repos). Commits are **local only** (no push);
review in the morning via `git log`/`git diff` on the branch in each repo.

Scope: 7 items in order — B2, B3, B4, B5, B8, B20 (phone/watch repo) + B17 (glasses repo).

Environment discovered:
- Phone scheme `GolfCaddie`, test target `GolfCaddieTests`, watch scheme `GolfCaddieWatch`.
- Test/build sim: **iPhone 17 Pro** (iOS 27). Watch sim: **Apple Watch Series 11 (46mm)** (watchOS 27).
- `xcodegen` 2.45.4 + `project.yml` present — run `xcodegen generate` if Swift files are added/removed.
- Glasses repo at `~/source/golf-caddie-glasses` (TypeScript/Vite).
- RAM-constrained Mac → builds run strictly one at a time.
- **Build toolchain gotcha:** the only installed sim runtimes are iOS/watchOS **27.0**, which
  the default `xcode-select` Xcode (**26.5**) cannot target (0 eligible sim destinations). All
  builds/tests use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.0).
  iPhone 17 Pro sim id `63965C6A-DE24-4AEF-881E-397A252D5AEB`; Apple Watch Series 11 (46mm)
  id `55B69EA8-A228-4AD5-834E-6C03ADFCBE41`.

Legend: ✅ done · ◑ partial · ⏭️ skipped/blocked.

---

## Status board

| Item | Title | Status | Tests |
|---|---|---|---|
| B2  | Transport idempotency (UUID on watch→phone commands) | ✅ done | phone 66 ✓ · watch build ✓ |
| B3  | Honest shot provenance + model fields | ✅ done | phone 72 ✓ · watch build ✓ |
| B4  | Watch→phone delivery feedback ("syncing N" chip) | ✅ done | watch build ✓ · phone 72 ✓ · ⚠ needs sim/device visual check |
| B5  | Per-hole track segmentation + stop/dwell detection | ✅ done | phone 80 ✓ |
| B8  | Track as shot-location source of truth | ✅ done | phone 82 ✓ |
| B20 | Feature-flag spike/validation behind `#if DEBUG` | ✅ done | phone DEBUG ✓ · watch DEBUG ✓ · phone+watch Release ✓ |
| B17 | Glasses polling cadence + staleness cue + battery | … | … |

---

## Per-item detail

### B2 — Transport idempotency on watch→phone commands ✅
**What changed**
- `GolfCaddie/Shared/SwingEventContract.swift`: new `IdentifiedCommand` struct (`id` + `command`);
  `WatchToPhoneMessage.command` now carries an `IdentifiedCommand` instead of a bare `WatchCommand`.
  The `.command(_:id:)` factory mints a fresh UUID per call (one tap = one id) but accepts an
  explicit id so a logical resend keeps its id. Watch senders are source-compatible (no changes).
- `GolfCaddie/Capture/LiveShotCoordinator.swift`: new pure `RecentIDSet` (bounded FIFO, `insert`
  returns false on a repeat); the `.command` ingest branch ignores an id already applied → at-most-once.
- `GolfCaddieTests/WatchCommandIdempotencyTests.swift` (new): `RecentIDSet` unit tests
  (insert/contains/capacity-eviction), wire round-trip (stable id survives encode/decode; distinct
  ids per send), and end-to-end (same command id ingested twice → 1 shot; fresh id → 2 shots).

**Tests:** `xcodebuild test -scheme GolfCaddie` → 66 passed (was 60; +6). `xcodebuild build
-scheme GolfCaddieWatch` → BUILD SUCCEEDED (contract compiles into the watch target).

**Notes for review:** at-most-once is keyed on the command id, so a *user re-tap* (a new id) is a
genuine second action and still applies — correct per spec. Swing events keep their existing
reconciler-based collapse (out of B2's scope). No schema change.

### B3 — Honest shot provenance + model fields ✅
**What changed**
- `GolfCaddie/Models/Shot.swift`: `ShotSource` gains `.watchManual` (deliberate watch tap) and
  `.reconstructed` (B6/B7 pins). `Shot` gains `isPutt: Bool = false` and `confidence: Double? = nil`
  (defaulted, so existing call sites compile unchanged). Doc note distinguishes pin-`confidence`
  from the detector's impact-strength `SwingEvent.confidence`.
- `GolfCaddie/Persistence/Database.swift`: migration `v4_shot_putt_confidence` — additive
  `ALTER shot ADD isPutt (NOT NULL default 0)` + `ADD confidence (nullable)`. New sources are
  string values in the existing `source` column → no schema change there.
- `GolfCaddie/Capture/RoundController.swift`: `ingestAutoShot` takes `source`/`isPutt` (defaulting
  to `.watchAuto`/false, so the detector path is byte-identical). `addShotFromWatch` → `.watchManual`;
  `addPuttFromWatch` → `.watchManual` + `isPutt`; phone `markPutt` → `isPutt` (via a new
  `markShotInternal(isPutt:)` param). All 6 `Shot(` sites audited: button/actionButton/manual/
  glasses/watchAuto now truthful; post-round add-missing-shot stays `.manual`.
- `GolfCaddie/Views/EditableHoleMap.swift`: pin `markerColor` handles the two new sources
  (watchManual → indigo, reconstructed → yellow, echoing DESIGN's low-confidence amber).
- Tests: `MigrationTests` migration-list pin updated to include v4; new `ShotProvenanceTests`
  (column existence, field/source round-trip through GRDB, default isPutt/nil-confidence on old-style
  rows, and the three entry-point provenance assertions).

**Tests:** phone 72 passed (was 66; +6). `GolfCaddieWatch` builds (B3 touches no watch-target
sources; confirmed anyway).

**Notes for review:** `confidence` is wired into the model + persistence but no live path sets it
yet — it's reconstruction's field (B6/B7), kept `nil` for live/manual shots by design. Phone
`markPutt`'s `isPutt` tag isn't unit-tested (its path awaits a 5 s `captureBestFix`; the watch putt
path proves the same flag). DB export (`VACUUM INTO`) carries the new columns automatically.

### B4 — Watch→phone delivery feedback ("syncing N" chip) ✅ (needs visual check)
**What changed**
- `GolfCaddieWatch/WatchSession.swift`: new `@Published outstandingMessages` = count of queued
  watch→phone userInfo transfers (`WCSession.outstandingUserInfoTransfers.count`), separate from the
  existing file-transfer `outstanding` (spike RESEND). `send(_:)` refreshes it right after
  `transferUserInfo`; new `session(_:didFinish userInfoTransfer:error:)` delegate drains it as the
  phone acknowledges each transfer (and records errors). No semantic auto-retry — the backlog is
  surfaced, not silently resent (B2 already makes the system's at-least-once redelivery safe).
- `GolfCaddieWatch/WatchRootView.swift`: new `SyncChip` (pulsing amber dot + "SYNCING N"), shown in
  `WatchPlayView` only when `outstandingMessages > 0`, placed outside the TabView so it's visible on
  every page and costs no space on a healthy link.

**Tests:** none added (per kickoff — B4 is runtime/visual, not unit-testable here). `GolfCaddieWatch`
builds; phone target unchanged (72 still pass).

**Needs on-device/sim visual check:** confirm the chip appears when the phone is unreachable
(airplane-mode the phone mid-round / kill the phone app), shows the queue count, and clears on
reconnect with no double-applied actions. Mechanism relies on `outstandingUserInfoTransfers`, which
counts swings *and* commands — intentional ("SYNCING N" = the whole watch→phone backlog).

### B5 — Per-hole track segmentation + stop/dwell detection ✅
**What changed**
- `GolfCaddie/Capture/TrackSegmenter.swift` (new): pure, DB-free core + a DB-backed convenience.
  - `StopDetectionConfig` — the two field-test knobs `T` (`minDwellSeconds`, 8 s) and `R`
    (`radiusMeters`, 5 m). `.default` reads optional `UserDefaults` overrides
    (`stopDetect.minDwellSeconds`/`.radiusMeters`) so they're adjustable **without recompiling**.
  - `TrackStop` — a candidate shot location (centroid, arrival/departure, sampleCount, 0…1
    `prominence` monotonic in dwell). Returned in track/time order.
  - `timeWindow(forHole:roundStart:holes:now:)` — slices the round-scoped track per hole by confirm
    times (previous hole's confirm → this hole's confirm, or `now` for the active hole; hole 1 starts
    at round start). Bounded by confirm timestamps, not tee/green (always available — Emerald Isle
    has no tee anchor).
  - `detectStops(in:config:)` — canonical stay-point detection (anchor + radius extension + dwell gate).
  - `stops(forHole:in:config:now:)` — composes the above over persisted data.
- Tests: `GolfCaddieTests/TrackSegmenterTests.swift` (new) — two-dwells-with-a-walk, pure walk → none,
  sub-threshold dwell → none, single-dwell centroid, <2 points, windowing bounds (incl. active hole →
  now, degenerate → nil), and DB-backed per-hole attribution (a hole-1 dwell and a hole-2 dwell each
  land only on their own hole).

**Tests:** phone 80 pass (was 72; +8). No watch-target files touched.

**Notes for review:** stop detection is anchored on the cluster's first point — a slow drift can
clip a long dwell, and a very slow amble (< R/T ≈ 0.6 m/s) could false-positive; both are acceptable
for v1 and tunable via the T/R knobs. `prominence` saturates at 60 s. This is the substrate B6/B7
consume (N strokes → N most-prominent stops); nothing calls it on the live path yet.

### B8 — Track as shot-location source of truth (retire the dual GPS-capture path) ✅
**What changed**
- `GolfCaddie/Capture/RoundController.swift`: `markShotInternal` (the phone Mark / +PUTT / casual /
  Action-button path) now reads the continuous `location.latestLocation` instead of awaiting
  `location.captureBestFix()` (the up-to-5 s ramp). This is the FT4 #6 "phone shot-mark latency"
  fix and unifies every live-logging path (phone/watch/glasses) on one mechanism — `latestLocation`,
  gated by `horizontalAccuracy > 0`, with `gpsAccuracy` recorded honestly. `markShotInternal` keeps
  its `async` signature (no caller churn); it simply no longer suspends.
- `captureBestFix` is **kept** for `detectAndApplyCourseName` only — a fire-and-forget once-per-round
  course lookup where waiting for a good fix is appropriate and off the live path.
- Tests: `GolfCaddieTests/LiveMarkPathTests.swift` (new) — `markShot` logs a `.button` shot from the
  track (graceful `hadGPS=false` with no sim fix), and `markPutt` tags a `.putter` `isPutt` putt via
  the phone path (the B3 case deferred because of the old 5 s wait — now cheap post-B8).

**Tests:** phone test target (see status board; +2). No watch-target files touched.

**Notes for review:** no live shot path now uses `captureBestFix` (confirmed by grep). Locations are
the live track fix; B5–B7 reconstruction refines pin locations from the full track afterward. W1
discipline preserved — nothing on the live path blocks on a GPS ramp.

### B20 — Feature-flag the spike/validation subsystem behind `#if DEBUG` ✅
**What changed** (all additive `#if DEBUG` guards — DEBUG behavior identical, Release excludes the code)
- **Watch:**
  - `GolfCaddieWatch/SessionMeta.swift` — whole file `#if DEBUG` (validation data model only).
  - `GolfCaddieWatch/LiveSessionController.swift` — `validationMode`, `selectedLabel`/`repCounts`,
    `meta`/`sessionDir`/`anchorTimer`/`batteryTimer`, the session-dir creation in `start()`, `mark()`,
    the spike save/transfer in `stop()`, and `scheduleTimers()` are all `#if DEBUG`. Release `start()`
    passes `dir = nil` to the recorder; live detection (workout + detector + DetectCard) is untouched.
  - `GolfCaddieWatch/MotionRecorder.swift` — the raw-file writers (handles/buffers/`recording`,
    `appendVec`, `makeFile`, the `if recording {…}` blocks inside the motion callbacks, the flush in
    `stop()`, the `Data.appendLE` extension) are `#if DEBUG`. The production sample taps
    (`onAccel`/`onGyro`/`trackRate`) and `manager` start/stop are unchanged.
  - `GolfCaddieWatch/WatchSession.swift` — the validation file-transfer half (`outstanding`,
    `deliveredCount`, `send(sessionDir:)`, `resendAll()`, the `didFinish fileTransfer` delegate, the
    `outstanding =` line) is `#if DEBUG`; the production userInfo half (B4 `outstandingMessages`,
    `send(_:)`, `didFinish userInfoTransfer`) stays.
  - `GolfCaddieWatch/WatchRootView.swift` — the VALIDATION toggle + RESEND footer and the play-screen
    MARK button are `#if DEBUG`. Release play screen has no validation affordances.
- **Phone:**
  - `GolfCaddie/Debug/SpikeSessionReceiver.swift` — **surgical**: the spike file receipt
    (`didReceive file:`, `appendReceipt`, `sessionsDirectory`, `receiptQueue`) is `#if DEBUG`, but the
    class, `activate()`, and the **production** `didReceiveUserInfo` (live swing/command receipt) stay
    in Release. (This delegate is the phone's only WCSession delegate — wrapping the whole file would
    have broken live shot logging.)
  - `GolfCaddie/Debug/SpikeSessionsView.swift` — whole file `#if DEBUG`.
  - `GolfCaddie/Views/SettingsView.swift` — the "Watch Spike" section is `#if DEBUG`.
  - `GolfCaddie/Debug/DebugHarness.swift` — already `#if DEBUG` (and its RootView call site), left as is.
  - `GolfCaddieApp.swift` — `SpikeSessionReceiver.shared.activate()` **kept** (production WC delegate).

**Tests/builds:** phone DEBUG test target unchanged (still passes); `GolfCaddieWatch` DEBUG builds;
**`-configuration Release` builds clean for BOTH `GolfCaddie` and `GolfCaddieWatch`** — confirming the
spike code compiles out with no dangling references.

**Notes for review:** the dual-role `SpikeSessionReceiver` is now misnamed in Release (it's just the
live-WC delegate there); a rename is B21 hygiene, out of scope. No runtime behavior change in DEBUG.
