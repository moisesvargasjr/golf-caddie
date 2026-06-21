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
| B4  | Watch→phone delivery feedback ("syncing N" chip) | … | … |
| B5  | Per-hole track segmentation + stop/dwell detection | … | … |
| B8  | Track as shot-location source of truth | … | … |
| B20 | Feature-flag spike/validation behind `#if DEBUG` | … | … |
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
