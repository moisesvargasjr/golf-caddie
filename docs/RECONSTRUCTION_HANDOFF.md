# Reconstruction Work — Shipped Record + Next-Phase Handoff

_Snapshot as of 2026-06-28. The end-of-hole reconstruction hero (B6 + B7, both
paths) is **built, validated, and merged to `main`**. This note records what
shipped and what's left, on top of the canonical plan in
[`RECONCILED_BACKLOG.md`](RECONCILED_BACKLOG.md)._

## TL;DR — reconstruction is DONE

The whole reconstruction spine landed via **PR #4** (merged 2026-06-28,
`reconstruction/b7-path-a` → `main`, merge commit `1356344`):
- **Path A (B7, watch):** `Reconstructor` (green-split putt classification, GPS-accuracy
  confidence, count reconciliation) + `SameSwingDedup` + the "what we tracked"
  `HoleReconstructionCard` + the `HolePinMapSheet` draggable pin corrector.
- **Path B (B6, phone-only):** `PathBReconstructor` (port of the R1 prototype) wired into
  the casual `Next ›` → review-sheet flow (same card in "reconstructed" mode + same pin
  corrector). Plus the **shot-time segmentation hardening** of `TrackSegmenter`.
- **Validated on the real Emerald Isle round** through the shipping pipeline: split exact
  6/18, putt err 0.89/hole, placement 12.0 m — matching/beating the Python prototype.
  **114 unit tests green.**

`main` is at build **0.1.0 (17)**; Xcode Cloud archives `main` → TestFlight.

## The one thing still unverified

The B7 **live-capture dedup** (a manual MARK-SHOT collapsing into a watch auto-detect)
is covered by 8 unit tests but **never exercised on the actual watch**. The next real
round on phone+watch is the check — does a MARK-SHOT-right-after-a-detected-swing feel
right (one shot, manual club kept), not double-logged. Everything else is additive /
non-destructive.

## What's left (the remaining backlog)

Reconstruction was the hard central piece; the rest is lighter. From `RECONCILED_BACKLOG.md`:
- **Not started:** B1 (watch auto-log + undo card — a Path-A prerequisite for *streaming*
  every swing), B9 (yardage-hero on-course screen — also where in-round current-hole map
  editing + the green marker live), B10 (auto hole-advance), B11 (watch redesign), B12
  (home resume-first), B13 (scorecard + reconstruction inbox), B15 (glasses HUD), B18
  (gate glasses input), B19 (watch battery), B22 (glasses sync-freeze).
- **Draft / hardware-gated:** B23 (glasses club-scroll fix — draft PR #3 in the glasses
  repo, needs the G2).
- **Merged but device-unverified:** the dedup (above), B4 syncing chip, B17 staleness/
  battery, B14 curation tool (browser visual check).

## Decisions locked (do not relitigate)

- **D1 = `lastShot` is club-only, NO distance** (B16, merged).
- Reconstruction is the spine; **Path A (watch) classifies located shots, Path B
  (phone-only) infers + places** — the draggable-pin correction is the load-bearing UX
  (placement is ~12 m, good enough to nudge, not relocate).
- **B6/B7 were built in-the-loop, not unattended.**
- One yardage everywhere = middle of green; glasses output-only + gated input lifeboat.

## What the prototype proved (now confirmed in shipping Swift)

Validated in Python against the real Emerald Isle round, then **re-confirmed through the
shipping pipeline** via a throwaway smoke test:
- **Path A** rides the live `fuse()` (swing-time → nearest breadcrumb) — already locates
  shots to GPS noise. So Path A is a **classify + reconcile** layer, not re-location.
- **Path B**: score → pins. The split is rough (~6/18 exact) **by nature** — which is why
  the draggable-nudge UX is load-bearing.
- **Tuned params:** dwell 8 s / radius ~5–6 m · green radius 25 m · merge 20 m.
- **Segmentation bug — FIXED:** confirm-time windowing handed the round's inverted H8/H9 a
  21-minute window. Now keyed off **last-stroke time** (`TrackSegmenter.timeWindow`'s
  `lastShotTimes`), robust to confirm inversions. This is what moved the real-data numbers
  from 4/18·1.17·13.7 m to 6/18·0.89·12.0 m.

## Code map (what shipped, all on `main`)

- `GolfCaddie/Capture/Reconstructor.swift` — Path-A core + `SameSwingDedup`.
- `GolfCaddie/Capture/PathBReconstructor.swift` — Path-B engine (merge dwells, estimate
  split, place pins).
- `GolfCaddie/Capture/TrackSegmenter.swift` — per-hole windowing (shot-time) + stop detection.
- `GolfCaddie/Capture/RoundController.swift` — `reconstructHole` (Path A at confirm),
  `placeCurrentHoleFromTrack` (Path B on casual review entry), `ingestAutoShot` dedup.
- `GolfCaddie/Views/HoleReconstructionCard.swift` — the card (`.tracked` / `.reconstructed`).
- `GolfCaddie/Views/HolePinMapSheet.swift` — draggable pin corrector (reuses `EditableHoleMap`).
- `GolfCaddie/Views/HoleReviewSheet.swift` — hosts the card + corrector for both paths.
- `GolfCaddie/Glasses/GlassesStateMapper.swift` — `greenCoordinate` + `teeCoordinate`.
- Tests: `ReconstructorTests`, `PathBReconstructorTests`, `TrackSegmenterTests`.

## Environment gotchas

- **Builds need Xcode-beta 27** via `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
  (only iOS/watchOS 27 sim runtimes installed). Test sim: **iPhone 17 Pro** (id
  `63965C6A-DE24-4AEF-881E-397A252D5AEB`); watch sim Apple Watch Series 11 (46mm).
- `xcodegen generate` after adding/removing Swift files (globs `GolfCaddie/` + `GolfCaddieTests/`).
- **Build number is in `project.yml` + both `Info.plist`s — keep them in lockstep**; the
  last upload was build 16, so source is at **17** (don't regress below an uploaded number).
- **Flow:** branch → per-item commits → push → PR per repo → user reviews/merges. Three
  repos: `golf-caddie`, `golf-caddie-glasses`, `golf-caddie-coursedata`.
- **Data:** `sample-data/golfcaddie.sqlite` (gitignored, personal GPS) was pulled via
  `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.moisesvargasjr.golfcaddie --source "Library/Application Support/golfcaddie.sqlite" --destination ...`.
  The real-data smoke test reads it directly via GRDB + `golf-caddie-coursedata/data/courses.json`
  for anchors (throwaway — re-create when you want to re-validate on real data).
- Completed handoffs/logs are archived under `docs/archive/`. Cross-session synthesis also
  lives in the Obsidian vault (`personal/learning/golf-caddie-glasses/reconciled-backlog.md`).
