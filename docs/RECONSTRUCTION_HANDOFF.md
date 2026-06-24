# Reconstruction Work — Session Handoff / Resume Note

_Snapshot as of 2026-06-24. For a fresh agent continuing the end-of-hole
reconstruction build. The canonical plan is [`RECONCILED_BACKLOG.md`](RECONCILED_BACKLOG.md);
this note is "where we are + how to resume" on top of it._

## TL;DR — where we are right now

Building **B7 (Path A) end-of-hole reconstruction**, in-the-loop with the user.
- **B7 engine is done and up as PR #4** (`reconstruction/b7-path-a`, ready, **101/101 tests green**) — awaiting the user's review/merge + an optional on-device sanity-check of the dedup. https://github.com/moisesvargasjr/golf-caddie/pull/4
- **Next: B7.3** — the "We tracked N shots" confirmation card UI (not started).
- The repo is currently left on `main`. The B7 code is on branch
  `reconstruction/b7-path-a` (pushed, PR #4). **To continue: `git checkout reconstruction/b7-path-a`.**

## How to resume (do this first)

1. Read `docs/RECONCILED_BACKLOG.md` — the source of truth (23 items B1–B23, decisions, traceability).
2. `git checkout reconstruction/b7-path-a` (the B7 work; if PR #4 is already merged, it's on `main`).
3. Skim the validated prototype: `sample-data/reconstruct_prototype.py` (gitignored; see "Data" below).
4. Continue with **B7.3** (card UI) — see "What's next".

## Backlog status

- **Merged to main:** B2, B3, B4, B5, B8, B17, B20 (night 1) · B14, B16, B21 (night 2).
- **In progress:** **B7** (Path A) — engine on PR #4; B7.3 card next.
- **Draft / needs hardware:** B23 (glasses club-scroll fix — needs G2 to tune `SCROLL_QUIET_MS`; draft PR #3).
- **Not started:** B1 (watch auto-log card), **B6 (Path B — the next big piece)**, B9–B13 + B15 (UI), B18 (glasses input gating), B19 (watch battery), B22 (glasses sync-freeze).
- **Pending checks (merged but unverified):** B4 syncing chip, B17 staleness/battery (sim/G2), B14 curation tool (browser).

## Decisions locked (do not relitigate)

- **D1 = `lastShot` is club-only, NO distance** (resolved; B16 done).
- Reconstruction is the spine; **Path A (watch) is robust, Path B (phone-only) is the nudge fallback**.
- **B6/B7 are built in-the-loop, NOT unattended** (overnight runs are for safe/spec'd items only).
- One yardage everywhere = middle of green; glasses output-only + gated input lifeboat.

## What the prototype proved (grounds the whole build)

Validated in Python against the **real Emerald Isle round** (pulled off the phone) before writing Swift:
- **Path A** rides the live `fuse()` (swing-time → nearest breadcrumb) — already locates shots to within GPS noise. So Path A reconstruction is a **hole-out layer (classify + reconcile), not re-location**.
- **Path B** (phone-only): score → pins. Split error <1 putt/hole, placement ~11m → **the draggable-nudge UX is load-bearing**, not polish.
- **Tuned params:** dwell 8s / radius 6m · green radius 25m · merge 20m.
- **Segmentation bug found:** `TrackSegmenter.timeWindow` keys off hole-number+confirm-time, so a non-monotonic confirm (the round's H8 confirmed after H9) yields an empty/garbled window. Fix = segment by play-order/shot-time. **This is a B6 prerequisite** (Path A doesn't use TrackSegmenter).

## B7 code map (what's on the branch)

- `GolfCaddie/Capture/Reconstructor.swift` — **pure core** (B7.1): `Reconstructor.reconstruct()` (green-split putt classification, GPS-accuracy confidence, count-vs-score reconciliation) + `SameSwingDedup` (pure cross-source dedup decision).
- `GolfCaddie/Capture/RoundController.swift` — **integration** (B7.2): `confirmHoleAndAdvance` runs `reconstructHole(...)` (persists `isPutt`/`confidence`, non-destructive); `ingestAutoShot` routes through `SameSwingDedup` (manual MARK-SHOT-after-detect adopts the auto row; auto-after-manual dropped; never auto-vs-auto, never putt-into-full).
- `GolfCaddieTests/ReconstructorTests.swift` — 19 tests (classification, confidence, reconciliation, dedup).
- Reuses: `GlassesStateMapper.greenCoordinate` (green anchor, local-over-curated), `Shot.isPutt`/`confidence` (B3), `ClubID.putter`, `Distance`.

## What's next (concrete)

1. **B7.3 — confirmation card UI.** Extend `Views/HoleReviewSheet.swift` / `Views/ActiveRoundView.swift`: render the reconstructed split ("We tracked N shots"), amber pins below `HoleReconstruction.lowConfidenceThreshold` (0.5), Edit-pins / Looks-right, draggable pins (reuse `Views/EditableHoleMap.swift`). **UI — build a first cut, iterate with the user.**
2. **B6 — Path B (phone-only reconstruction).** The next big piece. Port the prototype's score→pins algorithm; **includes the B5 segmentation play-order fix**; score-stepper + collapsed disclosure (DESIGN Fig 1b); reuse `EditableHoleMap`, `ClubAverages`.
3. Hardware/verify follow-ups when the user has devices: B23 (G2), B4/B17/B1 (sim/device), B14 (browser).

## Environment gotchas

- **Builds need Xcode-beta 27** via `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (the only installed sim runtimes are iOS/watchOS 27). Test sim: **iPhone 17 Pro** (id `63965C6A-DE24-4AEF-881E-397A252D5AEB`); watch sim Apple Watch Series 11 (46mm).
- `xcodegen generate` after adding/removing Swift files (project globs `GolfCaddie/` + `GolfCaddieTests/`).
- **Flow:** branch → per-item commits → push → PR per repo → user reviews/merges. Three repos: `golf-caddie`, `golf-caddie-glasses`, `golf-caddie-coursedata`.
- **Data:** `sample-data/golfcaddie.sqlite` (gitignored) was pulled from the user's iPhone via
  `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.moisesvargasjr.golfcaddie --source "Library/Application Support/golfcaddie.sqlite" --destination ...`. Two rounds have GPS tracks (Emerald Isle FT4, Welk). Personal GPS — keep gitignored.
- Completed handoffs/logs are archived under `docs/archive/`. Cross-session synthesis also lives in the user's Obsidian vault (`personal/learning/golf-caddie-glasses/reconciled-backlog.md`).
