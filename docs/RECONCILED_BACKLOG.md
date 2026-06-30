# Golf Caddie — Reconciled Prioritized Backlog

> **Read this first.** This document merges two handoffs into one ranked, dedup'd,
> implementation-ready backlog:
> - `docs/IMPROVEMENTS_HANDOFF.md` — architecture/correctness review (13 items)
> - `docs/design_handoff_frictionless_round/` — UX overhaul (the "frictionless
>   round" — end-of-hole reconstruction, screen-by-screen redesign)
>
> Where the two disagree, the resolution is stated inline. Where a genuine product
> decision remains, it is flagged **🔵 DECIDE** with a recommendation. Every item in
> both source docs is traced to a backlog ID in the **Traceability** appendix —
> nothing was dropped. **Real-round field-test feedback is folded in too** — most
> recently **FT4 (Emerald Isle, 2026-06-20)**, which adds blockers B22–B23 and
> sharpens several existing items; see §2.5 and the FT4 traceability table in §10.
>
> Covers three repos:
> - `golf-caddie/` — iOS phone app (`GolfCaddie/`) + watch target (`GolfCaddieWatch/`)
> - `golf-caddie-glasses/` — Even Realities G2 HUD (TypeScript/Vite)
> - `golf-caddie-coursedata/` — curated course data + curation web tool
>
> File:line anchors are from a 2026-06-20 code read — treat as starting points,
> confirm by reading. IDs (B1…B23) are stable; reference them in commits/PRs.

---

## Build status (updated 2026-06-28)

- **✅ Merged to `main`:**
  - _Foundations (night-1):_ **B2** (command idempotency), **B3** (shot provenance +
    `isPutt`/`confidence`), **B4** (watch→phone delivery feedback), **B5** (per-hole
    track segmentation + stop/dwell), **B8** (track as shot-location source of truth),
    **B17** (glasses poll ~1.5 s + reconnect staleness + battery), **B20** (spike/
    validation behind `#if DEBUG`).
  - _Contract + coursedata + hygiene (night-2):_ **B16** (`lastShot` club-only),
    **B14** (Course Desk tee anchors + completeness gate — needs a browser visual
    check), **B21** (doc/flag/dead-code hygiene).
  - _The reconstruction hero (PR #4, 2026-06-28):_ **B6** (Path B phone-only — engine +
    casual `Next ›` review-flow UI + shot-time segmentation hardening) and **B7** (Path
    A watch — `Reconstructor` + `SameSwingDedup` + the "what we tracked" card + draggable
    pin corrector). **Both paths**, validated on the real Emerald Isle round (split
    6/18, putt err 0.89/hole, placement 12.0 m — matching/beating the R1 prototype);
    **114 unit tests green**. The B5 segmentation was hardened here (window by last-shot
    time, robust to confirm inversions).
- **✅ Resolved decision — D1:** `lastShot` is **CLUB-ONLY, no distance** (see §2 D1 and
  B16). Do not relitigate.
- **🟢 Draft / hardware-gated:** **B23** (glasses club-scroll fix — root-caused, guarded
  fix on **draft PR #3** in the glasses repo; **NEEDS G2 CONFIRMATION**).
- **⏳ Not started:** B1 (watch auto-log card), B9, B10, B11, B12, B13, B15, B18, B19,
  B22.
- **🔬 Merged but device-unverified:** the B7 live-capture **dedup** (a manual MARK-SHOT
  collapsing into a watch auto-detect) is unit-tested but wants a real round on the
  watch to confirm the feel; B4's syncing chip and B17's staleness/battery want a
  device/G2 pass; B14 wants a browser visual check.

---

## 0. The reconciliation thesis (read before picking up any item)

Both documents point at the **same destination**: a round where the golfer never
has to stop, stand on the spot, and tap — yardage is the hero, and shot/club data
accrues automatically and is *confirmed*, not *captured*. They differ only in which
layer they emphasize and what job they give the **watch swing detector**:

- **IMPROVEMENTS** treats the detector as the *primary source of truth* that must be
  near-perfect: no lost shots, no phantom shots, no double-counts. Its items 1–3 are
  about making real-time, on-the-spot auto-logging trustworthy.
- **DESIGN** *demotes* the detector to one of **three triangulating signals** —
  (1) the continuously-recorded GPS track, (2) the swing-detection *timestamps*, and
  (3) known hole geometry / the entered **score** — and moves the moment of truth to
  **hole-out reconstruction**. The score is the ultimate backstop: "forgetting can no
  longer cost you the data."

**The resolution that drives this whole backlog:** adopt DESIGN's reconstruction
model as the spine. This *relaxes* the perfection IMPROVEMENTS demanded of the
detector (hole-out reconciliation + score-as-truth catches phantom and missed
detections), while still **requiring** IMPROVEMENTS' transport correctness
(idempotency, delivery visibility, honest source tagging). Several IMPROVEMENTS
items therefore change shape rather than being done verbatim — each notes how.

**This is good news for effort:** a surprising amount of the reconstruction
infrastructure already exists (see §3). The hero feature is more "wire together +
add an end-of-hole reconciliation pass + new UI" than "build from scratch."

---

## 1. Decisions already locked (do not relitigate)

Carried from both source docs:

1. **Reconstruction is the spine.** "Marking becomes confirming." Phone records the
   walk passively; the hole is settled once, at hole-out. (DESIGN hero.)
2. **Auto-detect (watch) is the primary *detection* path; manual tap is a backstop.**
   But detection now *feeds reconstruction* rather than being the final word.
   (IMPROVEMENTS product decision, re-scoped by the thesis above.)
3. **Everything must work phone-only.** Four configs stay first-class: phone-only,
   phone+watch, phone+glasses (no watch), all three. (See §7 config matrix.)
4. **Glasses are output-only on the live path**; the input fallback STAYS as a gated
   "watch died" lifeboat — gated and tested, not deleted. (IMPROVEMENTS.)
5. **One yardage number everywhere: distance to the *middle* of the green.** No
   front/back. The curated data has a single green marker; three-point greens are
   out of scope. (DESIGN data contract — this also *resolves* IMPROVEMENTS item 11.)
6. **Spike/validation tooling is feature-flagged behind `#if DEBUG`, not deleted.**
   (IMPROVEMENTS.)

## 2. Open product decisions (flagged 🔵 — confirm before/within the relevant item)

- **✅ D1 — RESOLVED: `lastShot` is CLUB-ONLY, no distance (item B16, 2026-06-22).**
  The decision is **keep club-only with NO `distanceYards`** anywhere on `lastShot`.
  Code already agreed (`LastShotDTO`, `shared/types.ts`); B16 fixed the stale contract
  doc to match. The "ship `distanceYards`" recommendation below is **superseded — do
  not implement it**; it is kept only for history. Rationale for club-only: a club's
  carry isn't knowable until the *next* shot is logged, so a distance paired with the
  last club would describe the *prior* club — confusing on the HUD. Per-stroke
  distances live on the scorecard (`holes[].shots[].distanceYards`), not `lastShot`.
  - _(superseded)_ ~~Recommendation: ship `distanceYards` = realized carry of the last
    completed stroke; re-opens the field-test-3 semantic the 2026-06-19 note reverted.~~
    The HUD (Fig. 5) `LAST · S2 · 4-IRON · 168y` mock is **not** the contract; render
    last-shot club-only (e.g. `Last: 7i`).
- **🔵 D2 — DetectCard timeout semantics.** RESOLVED here (not left open): adopt
  **auto-accept + undo** (DESIGN), NOT timeout-discard (IMPROVEMENTS item 2's
  alternate branch). Rationale: reconstruction's hole-out reconciliation + score make
  a stray auto-logged shot cheap to catch, and IMPROVEMENTS item 1 itself recommends
  the auto-log model. **Hard requirement that survives:** a *distinct haptic on every
  auto-log* so no shot ever reaches the DB unfelt. (Item B1.)
- **🔵 D3 — Course-data scope.** IMPROVEMENTS scoped `golf-caddie-coursedata` as
  "reference only, no code changes." DESIGN requires **tee anchors per hole** as the
  second bookend reconstruction needs. RESOLVED: coursedata IS in scope (item B14).
  Tee anchors are an *enhancement* to reconstruction accuracy, not a hard blocker —
  Path B can ship using the existing `greenAnchor` + the track's own start — so B14
  can land in parallel (separate repo) but should precede "trusting" reconstruction.

## 2.5 Field test 4 — Emerald Isle (2026-06-20): what the round told us

Latest real round (`docs/FIELD_TEST_4_EMERALD_ISLE.md` — par-18, shot 55; glasses
output + Apple Watch Series 6 input + phone), now triaged into this backlog. Two
**🔴 high-severity blockers** were surfaced and added as items; the rest is evidence
that confirms, sharpens, or de-risks items already here.

**New blockers (fix before the next round — see "P0 · Field-test blockers"):**
- **B22 — glasses sync-freeze.** HUD stalled on a prior hole/stroke for *several*
  strokes, then re-synced on its own → glasses "essentially unusable" as output. Both
  hole and stroke froze together ⇒ likely the **poll loop**, not the renderer.
- **B23 — glasses club-scroll over-sensitivity.** Constantly skipped past the intended
  club; **regression since the Welk test** (suspect `1e0cc28`/`81d504b`). It bit because
  the watch died mid-round and the glasses became the *input* device.

**Signals that sharpen / strengthen existing items:**
- **#6 phone shot-mark latency** ("glasses and watch mark immediately; the phone lags,
  leaving you standing there") = a felt confirmation of exactly what **B8** predicts (the
  ≤5 s `captureBestFix` ramp). Treat B8 as field-validated; consider pulling it earlier.
- **#7 edit the *current* hole from the map** without being forced to advance first → an
  explicit requirement now on **B7/B6** (in-round, current-hole pin/club editing, not
  only at hole-out or post-round).
- **#8 static map orientation** (always green-to-north / you-to-south, no heading
  rotation) and **#9 render a green/flag marker on the map** → added to **B9** (the
  on-course map already has `greenAnchor`; today it's an undecorated map).
- **#3 watch battery** — Series 6 hit 20 % by ~hole 14 (powered off). A concrete data
  point for **B19**'s duty-cycle work; the test device is *below* the Series 9 / Ultra 2
  floor, so this is partly hardware, partly the always-on 100 Hz capture.
- **#5 watch-died → glasses-as-input** actually happened → the "watch-died lifeboat"
  config (**B18**, config-matrix row 3) is real, not hypothetical; it must be gated *and*
  usable (which #2 / B23 currently breaks).

**Positive signals (de-risk the plan):**
- Watch **swing tracking worked well** and **manual putt marking worked** (#4) — the
  detector is trustworthy enough to be Path-A's signal (**B1/B7**), and the watch putt
  flow (**B11**) is on solid ground.
- Emerald Isle was curated and used live (now in `courses.json` with `greenAnchor` only,
  **no `tee`**) — a fresh real course that confirms **B14**'s premise.

## 2.6 Field test 5 — Oaks North (North nine, 2026-06-28): what the round told us

Watch + glasses + phone (Apple Watch Series 6), 9 holes, linked `oaks-north-north`.
The phone DB was pulled off-device via `xcrun devicectl … --domain-type appDataContainer`
and analyzed (`/tmp/golf-dbs/iphone/golfcaddie.sqlite` — **personal GPS, never committed**):
48 shots, 2 727 trace points, **0 penalties**, course linked correctly (no mis-link).

**Positive signals (de-risk):**
- **Glasses sync held the whole round** — B22 (FT4 freeze) did **not** recur. One clean run;
  not yet proof it's gone.
- **Watch auto-tracked every full swing** (26 `watchAuto`, zero manual marking) — Path A
  (B1/B7) field-validated again. Putts (not auto-detected, by design) entered by hand.
- The B7 cross-source dedup (`SameSwingDedup`) held — **no auto+manual collisions** in the data.

**New items surfaced — all three FIXED (branches noted):**
- **B26 — putt double-log on tap-bounce.** Hole 5 logged the same putt twice, 1 s apart, same
  spot — the manual-putt control had no debounce. (Distinct from B7's auto/manual dedup, which
  held.) **Fix:** watch leading-edge debounce (`LiveSessionController.sendPutt`, 1.5 s) + phone
  backstop (`RoundController.addPuttFromWatch` drops a putt ≤ 2.5 s after the last putt). Test:
  `LiveMarkPathTests.testWatchPuttDoubleTapIsDroppedAsBounce`. ✅ (`watch/input-redesign`)
- **B27 — glasses "⚠ NO SYNC" banner flicker.** `onPoll` flipped `disconnected` on a single
  dropped poll with no debounce (unlike the GPS-stale path), so a transient blip flashed the
  banner for one frame and shifted every HUD line below it — read in the field as the
  "TOTAL/PENALTY line flickering." **Fix:** `DISCONNECT_DEBOUNCE = 2` consecutive drops before
  the cue shows (`router.ts`). ✅ (repacked `golfcaddie.ehpk`; on-G2 confirm pending)
- **B28 — putt over-classification.** `Reconstructor.isPutt` flagged *any* non-putter shot
  inside the green radius as a putt → 6 lob-wedge chips from the fringe mis-counted as putts.
  **Fix:** a known non-putter is never a putt; green-proximity is only a fallback when the club
  is unknown (the Path B case). Tests updated + `testClublessStrokeFromGreenIsPutt` added. ✅

**Earlier FT5-prep feedback, now tracked items:**
- **B24 — watch input redesign.** PUTT +1 promoted to the primary key (→ `.puttPlusOne`), MARK
  shrunk to secondary, putter dropped from the crown scroll; yardage block top-anchored so the
  to-green number clears the LISTENING meter. ✅ (`watch/input-redesign`)
- **B25 — watch in-round club edit.** Change a logged shot's club mid-hole *and* on the summary,
  without the phone. Needs a new watch→phone command (the watch can only add/delete a shot today,
  not mutate one), a phone handler, and a `StrokeRow` affordance. 🔲 **next.**

## 3. What already exists (inventory — saves the implementer days)

Verified in code 2026-06-20. The reconstruction "hero" is far from greenfield:

| Capability | Status | Where |
|---|---|---|
| Continuous GPS breadcrumb, **persisted** | ✅ exists (round-scoped, not hole-scoped) | `RoundController.recordBreadcrumb()` :104–123; `Models/TracePoint.swift` :4–13 (id, roundID, timestamp, lat, lng, accuracy); `Persistence/TracePointRepository.swift` |
| Swing-timestamp → nearest breadcrumb match | ✅ exists (the core Path-A primitive) | `LiveShotCoordinator.fuse()` :125–137; `TracePointRepository.nearest(toTimestamp:inRound:)` :33–53 (±10 s) |
| Per-club rolling-average distance from consecutive shots | ✅ exists ("club distance for free") | `Utils/ClubAverages.swift` :23–68 (min 3 samples) |
| Practice-swing burst collapse (step-gate) | ✅ exists | `Capture/ShotReconciler.swift` :46–59 (8 s `clusterMaxGap`); `LiveShotCoordinator` debounce 3.0 s :30 |
| Draggable shot pins, draggable tee/green anchors, long-press | ✅ exists (post-round) | `Views/EditableHoleMap.swift` :206–276 |
| Add-a-missing-shot via center crosshair | ✅ exists (in-round) | `Views/MissingShotPinSheet.swift` |
| End-of-hole card (par stepper, shot list, club reassign, penalties, confirm) | ✅ exists — but shows *real-time-logged* shots, no reconstruction | `Views/HoleReviewSheet.swift` (par :162–178, shots :182–206, confirm :331–354) |
| Map polyline + numbered shot pins | ✅ exists | `Views/ActiveRoundMap.swift` (polyline :122–136, pins :91–120/255–307) |
| Club suggestion from distance-to-green (watch) | ✅ exists (refine to use learned averages) | `WatchRootView` `suggestedClubIndex(clubs, yards:)` ~:265 |
| Logbook design tokens (paper, Georgia serif, Menlo mono, amber/crimson, atoms) | ✅ fully implemented | `Design/Palette.swift`, `Typography.swift`, `Theme.swift`, `Design/Atoms/*`; watch `WatchTheme.swift` :7–28; glasses `format.ts` |
| Shot model: location, gpsAccuracy, hadGPS, club?, source, seq, timestamp | ✅ exists | `Models/Shot.swift` :12–26 |

**Genuinely greenfield** (the actual work): end-of-hole reconstruction *pass*
(stop/dwell detection, score→N-pins, Path B); per-hole track segmentation; green
radius/polygon putt classification; `isPutt`/`confidence` on `Shot`; collapsed-pin
disclosure UI; scorecard amber-dot inbox; cross-source dedup + watch-command
idempotency; delivery feedback; auto hole-advance; resume-first home; yardage-hero
on-course screen; course-tool tee anchors + completeness; glasses HUD redesign +
polling/reconnect/battery.

## 4. Invariants & contracts to preserve (don't break while working)

- **Glasses wire contract** (`golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md`):
  no JSON `null` (omit absent keys), short club names, `score = shotCount + penalties`,
  ISO-8601 without fractional seconds, trailing-empty-hole trimmed. `GlassesStateMapper`
  (phone) and `shared/types.ts` (glasses) stay lockstep.
- **Read-after-write**: any POST to the phone server returns a `GolfState` that already
  includes the write's effect. (Already true — `GlassesServer` :169–216 re-encodes.)
- **W1 fast-path discipline**: glasses/watch shot logging must NOT block on a slow GPS
  ramp. With B8, the track becomes the location source, so the live path only ever
  reads `latestLocation` — keep it non-blocking.
- **Phone-only must keep working** with no watch and no glasses present.
- **Device roles** (DESIGN data contract): iPhone = source of truth (records track,
  owns map/round/scorecard/reconstruction; fully usable alone). Watch = primary input
  (detect/confirm/club/putts). Glasses = primary glance (read-only HUD). Course tool =
  pre-round prep.

---

# 5. Prioritized backlog

Tiers are ordered by dependency → value-per-effort → risk. Items inside a tier can
largely proceed in parallel. Effort: **S** ≈ <½ day, **M** ≈ 1–3 days, **L** ≈ 3+ days
(reconstruction items are inherently multi-session). Each item: **Why / Change /
Where / Acceptance / Traces-to**.

> Ordering note vs the source docs: DESIGN ranks reconstruction #1 and the watch
> auto-accept card #3; this backlog pulls the watch confirm-card change (B1) *forward*
> into P0 because it's low-effort, fixes a current data-trust bug on its own, AND is a
> prerequisite for Path A. Otherwise the spine order matches DESIGN (Path B before
> Path A), and IMPROVEMENTS' transport-correctness items become the P0 enablers.

## P0 — Field-test blockers (FT4 Emerald Isle — fix before the next round)

Bugs/regressions, not new features — and they **lead**: they block the glasses entirely
and the watch-died input fallback, i.e. the field-testing loop itself. They run in
parallel with the P0 foundations below (different surface, can be a different person).

### B22 — Glasses sync-freeze (HUD stalls for several strokes) + sync-liveness cue · Glasses+Phone · M · 🔴 FT4 blocker
- **Why.** FT4: the HUD intermittently froze on a previous hole/stroke and stayed stale
  for *several strokes* before re-syncing on its own (no known trigger) — making the
  glasses essentially unusable as an output device. Both hole *and* stroke stall
  together, so it's **likely the poll loop**, not the renderer.
- **Change.** Reproduce and fix the stall in the `GET /api/state` polling path — usual
  suspects: a fetch that throws and a timer that then never reschedules (no
  catch→reschedule), an `await` that never resolves, or a phone-side `GlassesServer` that
  stops responding when the app is backgrounded between GPS callbacks (see the overview's
  "background execution" caveat). Add a **sync-liveness cue** (the FT "ask"): a subtle
  "feed live / last update Xs ago" indicator on the HUD (and optionally phone-side) so a
  stalled feed is never read as live. Build this as **one freshness mechanism shared with
  B17**'s reconnect-staleness cue — same problem (silent stale HUD): B22 is the
  mid-session-stall case, B17 the dropped-link case.
- **Where.** glasses `src/app/api-client.ts` (poll loop / `POLL_MS` :16 — guarantee each
  tick reschedules even after a thrown/slow fetch), `router.ts` (last-good freshness
  :160–162), `main.ts`; phone `GolfCaddie/Glasses/GlassesServer.swift` (liveness while
  backgrounded). Add console instrumentation to catch it in the field.
- **Acceptance.** The HUD cannot silently show stale data across multiple strokes; a
  stalled/dropped feed is visually distinct from a live one within ~1–2 polls; the poll
  loop provably reschedules after a failed fetch (repro by injecting fetch failures in the
  simulator and confirming recovery).
- **Traces-to.** FT4 #1. Couples with **B17** (shared freshness mechanism).

### B23 — Glasses club-scroll over-sensitivity regression (since Welk build) · Glasses · S–M · 🔴 FT4 blocker
- **Why.** FT4: club selection on the glasses was so over-sensitive it constantly skipped
  past the intended club; the workaround was to pick any club and fix it on the phone.
  **New since the Welk field test** — points at a change in the `.ehpk` build / glasses
  input handling since Welk (suspect commits `1e0cc28` / `81d504b`). It bit because the
  watch died mid-round and the glasses became the *input* device — the very "watch-died
  lifeboat" the backlog commits to keeping (B18 / config-matrix row 3).
- **Change.** Bisect glasses input handling between the Welk build and current
  (`1e0cc28` / `81d504b` are the suspects); restore stable scrolling so one physical
  scroll = one club step (debounce / step-threshold on the touchpad delta; note the SDK
  scroll axis is inverted per the overview). Verify against the club lane specifically.
- **Where.** glasses `src/app/input.ts` (scroll delta → step mapping / sensitivity),
  `screens/club.ts` (club-lane cursor), `command-client.ts` (`POST /api/club`); diff these
  since `1e0cc28` / `81d504b`.
- **Acceptance.** On real G2, scrolling the club lane lands on the intended club without
  skipping; the watch-died → glasses-input path is usable end-to-end (ties to B18's
  no-watch test).
- **Traces-to.** FT4 #2. Gates the phone+glasses-no-watch config (**B18**).

## P0 — Foundations: cheap correctness + model prep (do first; mostly parallel)

### B1 — Watch confirm card → auto-log + undo, no dropped detections, haptic on every auto-log · Watch · M
- **Why.** Today `handleDetection` drops any detection while a card is showing
  (`guard pending == nil`), and the card **auto-confirms** on a 5 s timeout with **no
  haptic** — so a practice swing/waggle can log a phantom shot the golfer never feels,
  and a real second shot within 5 s is silently lost. Worst case for data trust, and
  it starves the phone reconciler of the bursts it exists to collapse.
- **Change.** Adopt the **auto-log + undo** model (resolves IMPROVEMENTS 1+2 together,
  and is exactly DESIGN's "auto-accept" card, Fig. 4):
  - Every detection **logs immediately** (tagged `source = .watchAuto`) and is sent to
    the phone — never dropped on the floor (the phone reconciler + B7 reconciliation
    are the net; a lost real shot is worse than an extra one).
  - The card becomes a **non-blocking "Shot detected · 8-iron? · turn crown to change"
    correction card with an auto-accept countdown ring** (DESIGN shows ~3 s). Timeout
    **keeps** the shot (it's already logged); the only action is correct-club or
    "Not a shot → undo."
  - **Play a distinct haptic at the moment of every auto-log** — different from the
    manual-tap `.success` so the two are distinguishable by feel.
- **Where.** `GolfCaddieWatch/LiveSessionController.swift` (pending slot :35,
  `handleDetection` guard :142, `confirmPending` :151 — currently no haptic; detection
  haptic `.notification` :138); `GolfCaddieWatch/WatchRootView.swift` DetectCard
  (`seconds = 5.0` :554, timeout auto-confirm :619).
- **Acceptance.** 3 detections 1.5 s apart all reach the phone (none dropped); no shot
  is ever written without a felt haptic; ignoring the card keeps the shot; `ShotReconcilerTests`
  stay green. Verify on watchOS sim + one real-device pass.
- **Traces-to.** IMPROVEMENTS 1, 2; DESIGN priority 3 (auto-accept card), Fig. 4.

### B2 — Transport idempotency on watch→phone commands · Phone+Watch · S
- **Why.** `WatchCommand`s carry no id, so a flaky link + user re-tap (or a retried
  `transferUserInfo`) can double-log or double-advance. `SwingEvent` already has an
  `id`; extend the discipline.
- **Change.** Add a `UUID` to every `WatchCommand` (`.addShot`, `.advanceHole`,
  `.previousHole`, `.puttPlusOne`, `.removeStroke`). The phone (`LiveShotCoordinator.handle`)
  keeps a small recently-applied-id set and ignores duplicates. At-least-once delivery
  becomes safe.
- **Where.** `GolfCaddie/Shared/SwingEventContract.swift`; watch sender
  `GolfCaddieWatch/WatchSession.swift` :26–28; phone `LiveShotCoordinator.handle`.
- **Acceptance.** Re-send the same command id twice → one effect. Unit test alongside
  `ShotReconcilerTests`.
- **Traces-to.** IMPROVEMENTS 3a. (Prerequisite for B4's at-least-once retry safety
  and for B7's reconciliation.)

### B3 — Honest shot provenance + model fields (`watchManual`, `isPutt`, `confidence`) · Phone · S–M
- **Why.** `addShotFromWatch`/`addPuttFromWatch` route through `ingestAutoShot` with
  `source: .watchAuto`, so a deliberate manual watch tap is indistinguishable from an
  auto-detected swing — corrupting per-club stats and making it impossible to measure
  detector precision/recall from real rounds. Reconstruction also needs to distinguish
  detected/reconstructed/manual pins, and to mark putts as putts.
- **Change.** (a) Add `ShotSource.watchManual` (use for `addShotFromWatch`;
  `addPuttFromWatch` → `.watchManual` + `club: .putter`). Keep `.watchAuto` strictly for
  detector-originated shots. Add a `.reconstructed` source for B6/B7 pins. (b) Add
  `isPutt: Bool` and `confidence: Double?` (or an enum) to `Shot` — DESIGN's model calls
  for both (`isPutt`, low-confidence amber pins). Putts today are only `club == .putter`;
  an explicit flag is cleaner for the green-split and "no club, no full-shot distance"
  rules. (c) Audit every shot path so `source` is always truthful — the B7 ingest funnel
  is the natural enforcement point.
- **Where.** `GolfCaddie/Models/Shot.swift` (`ShotSource` :4–10, fields :12–26); shot
  entry points: `markShot` :723, `markPutt` :731, `addCasualStroke` :744,
  `markShotFromActionButton` :748, `logShotFromGlasses` :675, `ingestAutoShot`
  (`LiveShotCoordinator` :112), `addShotFromWatch` :428, `addPuttFromWatch` :437,
  `insertMissingShot` :374.
- **Acceptance.** A round logged via auto-detect + manual taps + reconstruction shows
  the correct `source`/`isPutt` per shot in the DB export; no path writes a misleading
  source. Add source/putt-tagging unit tests.
- **Traces-to.** IMPROVEMENTS 5; DESIGN model ("`Shot` with `club?`, `isPutt`,
  `confidence`").

### B4 — Watch→phone delivery feedback (no silent loss) · Watch · M
- **Why.** `WatchSession.send` calls `transferUserInfo` and ignores the result; there's
  no `didFinish userInfoTransfer` delegate, `refreshOutstanding` counts only
  `outstandingFileTransfers`, and the UI gives the same `.success` whether the phone got
  the command or it's queued for an hour (phone in the bag / dead). RESEND only resends
  *files*.
- **Change.** Implement `session(_:didFinish userInfoTransfer:error:)`; track outstanding
  *command* transfers; show a lightweight on-watch "syncing N" chip on the play screen
  (DESIGN's watch is "your best input device — a missed tap is harmless," which depends
  on the golfer being able to *see* a backlog rather than be falsely reassured). Do NOT
  auto-retry semantically (B2 makes at-least-once safe, but surface the backlog).
- **Where.** `GolfCaddieWatch/WatchSession.swift` (`transferUserInfo` :28,
  `refreshOutstanding` files-only :59, `didFinish fileTransfer` :77–88, `resendAll`
  :49–55); play screen in `WatchRootView`.
- **Acceptance.** With the phone unreachable, marking/advancing shows a queued state;
  on reconnect the backlog drains and clears; no double-applied actions (B2).
- **Traces-to.** IMPROVEMENTS 4.

## P1 — The hero: End-of-hole reconstruction (DESIGN #1)

### B5 — Per-hole track segmentation + stop/dwell detection · Phone · M · ✅ MERGED (night-1; window hardened to shot-time in PR #4)
- **Why.** The track is persisted **round-scoped** (`TracePoint.roundID`), and there's
  no notion of a "stop." Both reconstruction paths need (a) the slice of the track
  belonging to the current hole and (b) the dwell points that are candidate shot
  locations.
- **Change.** Derive per-hole track slices from hole confirm timestamps (or tee/green
  proximity) — no schema change required; query `TracePoint` by round + time window.
  Implement **stop detection**: a dwell of ≥ T seconds within R meters (start T≈8 s,
  R≈5 m; make them tunable for field testing). Expose `stops(forHole:)` returning ordered
  candidate locations with a prominence/confidence score.
- **Where.** New logic near `Capture/` reusing `TracePointRepository`; tunables
  surfaced for field test. Reuse `Utils/Distance.swift`.
- **Acceptance.** For a recorded round, `stops(forHole:)` returns plausible candidate
  pins bounded by tee/green; T/R are adjustable without recompiling shipped logic
  (config or `#if DEBUG` knobs).
- **Traces-to.** DESIGN #1 acceptance ("Stop detection").

### B6 — Path B: phone-only score-driven reconstruction · Phone · L · ✅ MERGED (PR #4)
> **Shipped** as `PathBReconstructor` (engine) + casual `Next ›` → review-sheet flow
> (card in "reconstructed" mode + `HolePinMapSheet` pin corrector). Differs slightly
> from the spec below: rather than a separate collapsed disclosure on the on-course
> screen, casual hole-out reuses the **same** `HoleReviewSheet` as tracked holes (one
> shared review UX for both paths). Score-stepper / collapsed-disclosure polish on the
> live screen (Fig. 1b) remains open and folds into **B9/B13**.
- **Why.** This is DESIGN's **"Phone-only Path B must work first"** — the frictionless
  floor with no watch. Today nothing reconstructs: casual mode has a score stepper
  (`ActiveRoundView` :633–674) but never lays pins; `confirmHoleAndAdvance` :593–603 just
  advances.
- **Change.** On hole-out, the only required interaction is the **score stepper**
  (Fig. 1b). That count seeds reconstruction: **N strokes → N pins** snapped to the N
  most prominent stops (B5), bounded by tee + green anchors; if stops < N, interpolate
  the remainder along the track and flag those pins **amber** (low confidence). Strokes
  whose stop falls **inside the green** (radius around `greenAnchor`, or `greenPolygon`
  if present) classify as **putts** (`isPutt`, no club, no full-shot distance);
  propose the putt split, let the user adjust ±1. Pins stay **collapsed by default**
  behind one disclosure row (`▸ N shots on your track · M putts — Review`); a score-only
  round never expands it. Expanding reveals pins for club assignment. **Graceful
  degradation:** never confirming still yields a correct score + yardages; shot/club data
  stays unconfirmed, never lost. Club distance between consecutive confirmed non-putt
  pins feeds `ClubAverages` (already built).
- **Where.** `Views/ActiveRoundView.swift` (overlay/sheet on hole-out; replace/extend the
  casual stepper path and `HoleReviewSheet`), `Views/ActiveRoundMap.swift` (track + pins
  + collapsed disclosure). Reuse `EditableHoleMap` :206–276 for draggable/long-press/
  tap-to-add pin editing, `ClubAverages` for distances, `confirmHoleAndAdvance` for the
  commit.
- **Acceptance (DESIGN criteria).** Phone-only, no watch: enter a score → that many
  pins appear distributed on the track, greens split as putts, low-confidence pins
  amber; tapping a pin assigns a club; **Save score** with pins collapsed completes the
  hole with full scorecard + yardages and unconfirmed-but-present shot data. Club
  distances appear in per-club averages after a few holes.
- **Traces-to.** DESIGN #1 (Path B, Fig. 1b), #1 acceptance (pin reconciliation, putt
  split, club distance, graceful degradation, editing); subsumes IMPROVEMENTS 3b
  (semantic dedup becomes reconciliation) for the phone-only case.

### B7 — Path A: watch-detected reconstruction + cross-source reconciliation · Phone · L · ✅ MERGED (PR #4)
> **Shipped** as `Reconstructor` (green-split + confidence + count reconciliation),
> `SameSwingDedup` (manual-vs-auto collapse), the `HoleReconstructionCard` ("what we
> tracked"), and the `HolePinMapSheet` draggable corrector. Reframed from the spec:
> `fuse()` already *locates* each watch shot live, so Path A is a hole-out *classify*
> layer, not re-location. The **in-round current-hole map editing** (FT4 #7) is partly
> covered (pins editable from the review sheet's corrector) but not yet from the live
> on-course map — that piece folds into **B9**. Dedup is **device-unverified** (see banner).
- **Why.** With a watch, shots are pre-detected (B1 streams every swing with a
  timestamp). DESIGN's Fig. 1: on hole-out, match each detected swing to the nearest
  **track stop** and present "We tracked N shots" for one-tap confirm. This is also
  where IMPROVEMENTS' **cross-source dedup** lands: the dangerous case (detector fires
  AND the golfer also taps MARK SHOT for the same swing → two rows) is resolved by
  reconciliation, not a separate funnel.
- **Change.** Extend `fuse()` (already matches swing timestamp → nearest breadcrumb) to
  match to **stops** (B5) and produce the pin list. Build the **"We tracked N shots"**
  card (Fig. 1): list shots with club + derived distance, amber the low-confidence pins,
  `Edit pins` / `Looks right →`. Reconcile counts: pins = detected swings; if stop count
  disagrees, prefer the swing count and amber the uncertain pins. **Dedup:** within a
  short time/space window on the active hole, a manual MARK SHOT tap **merges into /
  replaces** the matching auto shot (prefer the manual club), rather than adding a row;
  putts are exempt from collapsing into a non-putt auto shot. Mind async ordering —
  auto shots land via the 3 s debounce + reconciler, possibly *after* a manual tap.
- **Where.** `Capture/LiveShotCoordinator.swift` (`fuse()` :125–137, `commitPending`,
  debounce :30); `Capture/ShotReconciler.swift` :46–59; the new ingest funnel in
  `RoundController`; the card in `Views/ActiveRoundView.swift`/`HoleReviewSheet.swift`.
- **Acceptance.** Auto-detect a swing then tap MARK SHOT within the window → exactly one
  shot, carrying the manual club; two genuinely separate shots (>window apart or a step
  between) → two shots; "We tracked N shots" confirms a hole in one tap; amber marks the
  uncertain pins. Add dedup unit tests alongside `ShotReconcilerTests`.
- **Field signal (FT4 #7).** The golfer wanted to edit shots on the *current* hole
  (club + location) without being forced to advance first. Make the active hole's pins
  editable in-round from the map — not only at hole-out (the B6/B7 card) or post-round
  (`EditableHoleMap`/`HoleDetailView`). Pairs with B9 (on-course map).
- **Traces-to.** DESIGN #1 (Path A, Fig. 1); IMPROVEMENTS 3b (cross-source dedup); FT4 #7.

### B8 — Track as shot-location source of truth; retire the dual GPS-capture path · Phone · S–M
- **Why.** Two strategies coexist: phone/Action buttons use `captureBestFix()` (≤5 s
  ramp) while watch/glasses/auto use `latestLocation`. Once reconstruction sources shot
  *locations from the track* (B5–B7), the per-shot point-fix distinction is mostly moot
  and the slow ramp is an inconsistency liability. IMPROVEMENTS item 6 re-scoped.
- **Change.** Shot locations come from the **track** (reconstruction). For any remaining
  live-logged shot, and for the on-course yardage hero, read the **fast `latestLocation`**
  (continuous best-accuracy tracking already runs during a round). Retire `captureBestFix`
  from the live path (or delete it if the round always tracks). Record `gpsAccuracy`
  honestly on every shot/pin so downstream stats can weight/filter. Don't regress W1
  (no path reintroduces a blocking ramp).
- **Where.** `Capture/LocationManager.swift` `captureBestFix` :113–139; callers
  `markShotInternal`/`markShotFromActionButton`; `LiveShotCoordinator.fuse()` fallback.
- **Acceptance.** All live-logged/reconstructed shots draw location from one mechanism;
  `gpsAccuracy` populated and comparable across sources; no 5 s block anywhere on the
  live path.
- **Field signal (FT4 #6).** "Phone shot marking is slow — glasses and watch mark
  immediately, the phone lags." That lag is this ≤5 s ramp, felt on-course; B8 is
  field-validated — consider pulling it earlier than its P1 slot.
- **Traces-to.** IMPROVEMENTS 6; FT4 #6.

## P2 — On-course & confirm UX (model now in place)

### B9 — Yardage-hero on-course screen; retire "Log Shot" as primary; middle-only · Phone · M
- **Why.** Today "Log shot" is the dominant flag-colored CTA and the distance card is
  one of several translucent cards showing **middle + fabricated FRONT/BACK** (±14 yd).
  DESIGN Fig. 2: make the **to-green middle number the hero**, retire Log Shot now that
  marking is retroactive, restore sun-legible contrast.
- **Change.** Solid ink top bar (`HOLE n · PAR p` left, running score right). Map fills
  the body. **Hero middle-of-green number, centered, very large**, caption `TO GREEN`,
  with a small **armed-club chip** (`▸ 8-iron`) beneath. **Drop FRONT/BACK** (resolves
  IMPROVEMENTS 11 on the phone). A **passive "RECORDING YOUR WALK"** pill (amber dot)
  near the bottom. Bottom thumb-zone row: **`Scorecard`** (primary) + **`Mark here`**
  (secondary/outline — an optional precision tool, not the primary path). A persistent,
  no-confirm **"Undo last"** reachable by thumb. Keep the Logbook aesthetic (it's already
  tokenized — reuse `Palette/Typography/Atoms`); the problem is hierarchy, not style.
  **Map (FT4 #8/#9):** render the green as a visible marker/flag (the data is there —
  `greenAnchor`; today it's an undecorated map), and **orient the map statically
  green-to-north / you-to-south** (no heading rotation) — matching the DESIGN mockups
  (green at top, the track flowing up to it).
- **Where.** `Views/ActiveRoundView.swift` (Log-shot CTA :848–871, distance card +
  FRONT/BACK :445–517/:469–490, undo button :571–574, casual stepper :633–674),
  `Views/ActiveRoundMap.swift`.
- **Acceptance.** Middle number dominates and is readable at arm's length in sun; no
  front/back shown; "Mark here" is clearly secondary; Undo is always reachable; passive
  recording pill present; all four configs still play.
- **Traces-to.** DESIGN #2 (Fig. 2), data contract (one yardage); IMPROVEMENTS 11 (phone); FT4 #8, #9.

### B10 — Auto hole-advance on tee-box crossing · Phone · M
- **Why.** Hole advance is manual (`Next ›` → confirm). DESIGN: when the track crosses
  into the next tee box, advance automatically with a quiet `Hole n+1 — not you? tap to
  fix.` so wrong-hole errors self-correct.
- **Change.** Use the curated tee anchors (B14) / `CourseDetector` to detect tee-box
  entry and advance; show the quiet correctable banner; keep manual advance available.
  Reconcile with B6/B7 hole-out reconstruction (advancing triggers the end-of-hole card).
- **Where.** `Capture/CourseDetector.swift`, `RoundController.confirmHoleAndAdvance`
  :593–603, `Views/ActiveRoundView.swift`.
- **Acceptance.** Walking onto the next tee advances the hole and surfaces a one-tap
  "not you?" fix; phone-only still works (manual advance remains).
- **Traces-to.** DESIGN #2 (auto-advance), #5; depends on B14 (tee anchors).

### B11 — Watch redesign: armed-club prediction, green-aware putts, score stepper, middle-only · Watch · M
- **Why.** DESIGN Fig. 4: four clean states. The armed-club chip must be **predicted
  from distance-to-green using learned averages** so it's never blank and a detected
  swing always has a club. Putts can't be felt, so on the green the watch should swap to
  a one-tap putt counter. And drop the fabricated FRONT/BACK.
- **Change.** (a) **Yardage + armed club:** big middle number + persistent armed-club
  chip predicted from `ClubAverages` (the watch already has `suggestedClubIndex`; wire it
  to *learned* averages, not static); crown changes it. (b) **Confirm card:** delivered
  by B1 (auto-accept ring + correct-club). (c) **Green-aware putts:** when GPS places the
  golfer inside the green, auto-swap to a putt counter (`– 2 +`) with `HOLED OUT`; one
  tap per putt; tag `isPutt` + `.watchManual`. (d) **Score stepper** per hole. (e) **Drop
  FRONT/BACK** (`green − 7 / green + 9` hardcode) — show only the middle number
  (resolves IMPROVEMENTS 11 on the watch). Keep the crown-armed selector gesture.
- **Where.** `GolfCaddieWatch/WatchRootView.swift` (FRONT/BACK :225–226, MARK SHOT
  :233–243, `ClubSelector` :249–346 / `suggestedClubIndex` ~:265), `WatchTheme.swift`,
  `Utils/ClubAverages.swift` (shared).
- **Acceptance.** Armed chip is never blank and tracks distance-to-green; on the green the
  watch shows a putt counter + HOLED OUT; only the middle number is shown; crown still
  changes the club.
- **Traces-to.** DESIGN #3/#4 (Fig. 4), data contract (armed club shared); IMPROVEMENTS 11
  (watch). Depends on B1 (card), B3 (`isPutt`/`watchManual`).

## P3 — Off-course surfaces & course data

### B12 — Home: resume-first · Phone · S
- **Why.** Home shows the last *completed* round; resume only appears post-round. DESIGN
  Fig. 3: if a round is live, lead with a single amber **Resume** card.
- **Change.** If a round is in progress, the masthead leads with `In progress · Hole n →
  Resume round →` (amber). Keep the "Fairway Logbook" masthead, recent-rounds list, and
  `＋ Start new round`.
- **Where.** `Views/HomeView.swift` (last-round block :44–190, begin-new :304–323).
- **Acceptance.** With a live round, Home resumes it in one tap; with none, Home is
  unchanged.
- **Traces-to.** DESIGN #3 (Fig. 3, Home).

### B13 — Scorecard: fast entry + reconstruction inbox · Phone · M
- **Why.** The scorecard exists (table + badges) but is read-only mid-round with no
  "unsure holes" surfacing. DESIGN Fig. 3: it's the 18Birdies-parity feature AND the
  place reconstruction gets confirmed after the round.
- **Change.** Big two-tap score stepper for the active hole (≥44–54 px targets), putts
  optional, columns `H · Par · Score · Putts`, active row highlighted. **Reconstruction
  inbox:** any hole the app is unsure about (amber/low-confidence pins from B6/B7) gets a
  small **amber dot**; tapping opens the reconstruction card (B6/B7 UI) to fix pins after
  the round — "fix pins later, at the bar."
- **Where.** `Views/InRoundScorecardSheet.swift` :1–308 (+ link into the B6/B7 card);
  reuse `Design/Atoms/ScoreBadge.swift`.
- **Acceptance.** Score entry is two taps with large targets; holes with unconfirmed
  reconstruction show an amber dot that opens the fix-pins card.
- **Traces-to.** DESIGN #3/#4 (Fig. 3, scorecard / reconstruction inbox).

### B14 — Course Desk: tee anchors + completeness checklist · Coursedata · M · (parallelizable)
- **Why.** Reconstruction bounds each hole with **tee + green**; today `courses.json`
  holes have only `greenAnchor` (no `tee`, no `greenPolygon`), and the curation tool can
  mark only the green with no publish-time completeness gate — a half-marked course can
  silently ship and leave the golfer with no yardage on the 14th. (Resolves open decision
  D3 — coursedata IS in scope.)
- **Change.** (a) Add a **`tee` anchor per hole** (`{lat,lng}`) to the schema and let the
  curation tool drop/drag it (keep the single middle-of-green marker as the only green
  point; no front/back). Optional: support `greenPolygon` to sharpen putt classification
  (B6). (b) Add an **18-row completeness checklist** (`par ✓ · tee ✓ · green ✓`) and gate
  publish on it. Visual restyle optional (lightest touch: Georgia headings, cream/ink,
  Courier Prime labels).
- **Where.** `golf-caddie-coursedata/data/courses.json` (per-hole schema:
  `number, par, yards, strokeIndex, greenAnchor` → add `tee`), `tools/curate.html`,
  `tools/green-marker.html` (greens `X/18` count exists; add tee + gate).
- **Acceptance.** Each hole can have par + tee + green; publish is blocked until all 18
  are complete (or explicitly overridden); the phone reads `tee` for bounding (B5/B10).
- **Traces-to.** DESIGN #4 (tee anchors), #7 (course desk), data contract (anchors).
  Reconstruction-quality dependency for B5/B7/B10; can land first in parallel.

## P4 — Glasses

### B15 — Full HUD redesign (fixed-hierarchy heads-up display) · Glasses · M
- **Why.** DESIGN Fig. 5: the glasses should carry the whole hole so they're the primary
  glance. Today `hud.ts` renders stacked text lines; DESIGN wants a strict, fixed-corner
  hierarchy on the 576×288 monochrome canvas.
- **Change.** Top frame: `HOLE 7 · PAR 4` (left) — `STROKE 3 · +2` (right), hairline rule.
  Center hero: the **to-green middle number** (large, `YDS · MIDDLE`), vertical divider,
  then a **club block** (`CLUB / 8-iron / ▸ SELECTED`). Bottom frame: hairline rule,
  `LAST` (left) — `S2 · 4-IRON · 168y` (right) **— requires D1/B16**. HUD follows the
  watch (armed club / detected shot). Keep the auto hole-summary flash on hole close, then
  return to HUD. Never add input/scroll/club-picker on the normal-shot path.
- **Where.** `golf-caddie-glasses/src/app/screens/hud.ts` (render :28–74), `display.ts`
  (SDK bridge, 576×288), `format.ts` (pixel-accurate columns), `screens/hole-summary.ts`.
- **Acceptance.** Fixed-corner layout matches Fig. 5; the hero number is the dominant
  element; last-shot shows per D1; output-only invariant intact.
- **Traces-to.** DESIGN #5 (Fig. 5), data contract. Depends on B16 (D1).

### B16 — Reconcile the `lastShot` contract across mapper / types / doc · Phone+Glasses · S · 🔵 D1
- **Why.** Three-way drift + the new HUD need. `GlassesStateMapper.lastShotDTO`
  (:201–207) ships `{club, sequenceNumber}` **no distance**; `shared/types.ts`
  `lastShot` (:45–52) omits `distanceYards`; the contract doc still documents a
  prior-shot+distance variant. DESIGN's HUD shows a distance.
- **Change.** Resolve **D1** (recommended: ship `distanceYards` = realized carry of the
  last *completed* stroke), then make `GlassesStateMapper`, `shared/types.ts`, and
  `IOS_INTEGRATION_CONTRACT.md` agree **verbatim**, and remove/supersede the stale
  field-test-3 text. Preserve wire invariants (omit when nil, short club names).
- **Where.** `GolfCaddie/Glasses/GlassesStateMapper.swift` :201–207;
  `golf-caddie-glasses/src/shared/types.ts` :45–52;
  `golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md`.
- **Acceptance.** A diff of the contract example vs `types.ts` vs the mapper output shows
  no schema mismatch; the HUD (B15) renders the agreed last-shot line.
- **Traces-to.** IMPROVEMENTS 12; DESIGN #5 (HUD last-shot). **Decision D1.**

### B17 — Glasses polling cadence, reconnect honesty, battery visibility · Glasses · S–M
- **Why.** `POLL_MS = 600` is 4× faster than every doc (battery cost on phone + glasses);
  on a dropped link the HUD renders the last-good frame for a 7 s grace
  (`RECONNECT_GRACE_MS`) with **no staleness cue** (frozen yardage reads as live); and
  `battery` is on the wire (`types.ts` :66) but never rendered, so the phone going flat is
  invisible.
- **Change.** Pick one cadence (recommend ~1500 ms) and make code + all three docs agree.
  During the reconnect grace window, show a subtle staleness cue (dim the yardage / "last
  seen Xs ago"). Render `battery` unobtrusively on the HUD (+ a low-battery warning under
  ~15%). Fold into the B15 HUD work since you're already in `hud.ts`.
- **Where.** `golf-caddie-glasses/src/app/api-client.ts` `POLL_MS` :16; `router.ts`
  `RECONNECT_GRACE_MS` :62, grace render :160–162; `hud.ts` (battery render);
  `golf-caddie-glasses/docs/ARCHITECTURE.md` (cadence).
- **Acceptance.** One cadence value across code + docs; a dropped link is visually
  distinguishable from a live HUD within the grace window; phone battery is visible.
- **Traces-to.** IMPROVEMENTS 10.

### B18 — Gate & test the glasses input fallback (keep the 4-way matrix) · Phone+Glasses · M
- **Why.** Glasses input is the "watch died / phone+glasses no watch" lifeboat, but it's
  half-wired: `glassesInputEnabled` is advertised in the read model yet the server's POST
  handlers run mutations **regardless of the flag** (they only check `controller.isActive`),
  and the glasses-side input modules are always parsed/run even on output-only rounds.
- **Change.** (a) Phone server **rejects writes when `glassesInputEnabled == false`**
  (appropriate 4xx) so the flag is the real authority. (b) Glasses **lazily load** the
  input lane (`command-client.ts`, `screens/club.ts`, `screens/actions.ts`, optimistic-
  write/arm router branches) only when the polled state has `glassesInputEnabled === true`
  — not on every output-only round. (c) **Test phone+glasses-no-watch end to end** (sim
  automation drives gestures): log a shot, set a club, advance a hole, see the phone
  reflect it.
- **Where.** `GolfCaddie/Glasses/GlassesServer.swift` POST handlers :169–216 (currently
  flag-blind), `GolfState.glassesInputEnabled` :22–25, `GlassesStateMapper` :54;
  glasses `router.ts` `inputEnabled` :102–104 (consumed :201/:325/:390), `command-client.ts`,
  `screens/club.ts`, `screens/actions.ts`.
- **Acceptance.** With the flag false, `POST /api/shot` etc. are rejected and the glasses
  never enter input mode; with it true and no watch, a full hole is playable from the
  glasses; output-only rounds don't load the input modules (verify via bundle/log).
- **Field signal (FT4 #5).** The watch died mid-round and the glasses became the input
  device — the watch-died lifeboat is real, not hypothetical. It must be gated *and*
  usable; **B23** currently breaks its usability (club-scroll regression).
- **Traces-to.** IMPROVEMENTS 8; DESIGN (output-only HUD + gated lifeboat); FT4 #5.

## P5 — Robustness & hygiene (anytime; lower urgency)

### B19 — Watch background-session resilience + battery duty-cycle · Watch · M
- **Why.** If the HK workout session dies mid-round, motion delivery stops, detections
  stop, but the play screen looks **completely normal** — `lastError` is only shown on the
  *start* screen. With watch-primary detection feeding reconstruction, a silent stop is
  serious. Separately, three motion streams (accel 100 Hz + gyro 100 Hz + deviceMotion
  50 Hz) run continuously for 4–5 hr with no duty-cycling and no `WKExtendedRuntimeSession`
  fallback.
- **Change.** On workout-session failure mid-round: show a clear **play-screen** banner
  ("Tracking paused — tap to resume"), attempt auto-restart of workout + recorder, and make
  the listening meter visibly read "not sensing." Add a `WKExtendedRuntimeSession` keep-
  alive fallback (or document why the workout session alone suffices). Make a deliberate
  battery decision (duty-cycle when stationary / lower deviceMotion if the detector only
  needs accel+gyro) and **record a measured full-round drain figure**.
- **Where.** `GolfCaddieWatch/WorkoutKeeper.swift` `didFailWithError` :44–49;
  `LiveSessionController.onFailure` :58; `WatchRootView` (`lastError` on start screen
  :120–121 → add play-screen banner); `MotionRecorder.swift` rates :81–83.
- **Field signal (FT4 #3).** Apple Watch **Series 6 hit 20 % by ~hole 14** and had to be
  powered off. The test device is *below* the Series 9 / Ultra 2 floor, but the always-on
  100 Hz accel + 100 Hz gyro + 50 Hz deviceMotion capture is the controllable half — this
  is the concrete drain figure B19 asks for, and motivates duty-cycling.
- **Acceptance.** Killing the workout session mid-round produces a visible play-screen
  state + recovery path; a full-round battery figure is recorded.
- **Traces-to.** IMPROVEMENTS 7; FT4 #3.

### B20 — Feature-flag the spike/validation subsystem behind `#if DEBUG` · Watch+Phone · S–M
- **Why.** Raw-motion recording + ground-truth tooling currently ships in production,
  gated only by a runtime `validationMode` flag, not `#if DEBUG`: the `VALIDATION ON/OFF`
  toggle, validation `MARK`, `RESEND n`, raw `dm/accel/gyro.bin` writers, and the phone
  `Debug/SpikeSession*` + Settings export hook.
- **Change.** Wrap all of it in `#if DEBUG … #endif` in both targets so release excludes
  it but dev keeps it for detector re-tuning. Ensure the release watch play screen has no
  validation affordances. Keep `DebugHarness.swift` (already DEBUG-only) as the in-app
  replay path.
- **Where.** `GolfCaddieWatch/WatchRootView.swift` (VALIDATION toggle :125–130, MARK
  :177–184, RESEND :132–134), `MotionRecorder.swift` raw writers :73–75,
  `LiveSessionController.mark()` :176–186; phone `Debug/SpikeSessionReceiver.swift`,
  `Debug/SpikeSessionsView.swift`, the Settings export hook.
- **Acceptance.** A release build contains no spike-recording code paths or UI; a DEBUG
  build is unchanged.
- **Traces-to.** IMPROVEMENTS 9.

### B21 — Doc + flag + dead-code hygiene · All · S
- **Why.** Drift and vestiges.
- **Change.** Update `golf-caddie/DESIGN.md` (it still describes phone-only Phase 1 /
  Watch in "Phase 6") — add a short "Current architecture" section reflecting
  watch-primary detection + reconstruction + output-only glasses, or link this backlog.
  Reconcile `golf-caddie-glasses/docs/ARCHITECTURE.md` poll cadence with B17. Document the
  real meaning of `glassesInputEnabled` once B18 gives it teeth. Remove dead vestiges
  (e.g. `WatchHeader` `accentTime` param; the no-op `justConfirmed.par = currentHole.par`
  in `RoundController.advanceHoleFromGlasses`).
- **Acceptance.** Docs match shipped behavior; named dead code removed.
- **Traces-to.** IMPROVEMENTS 13.

---

## 6. Suggested execution order (one-line)

`B22 + B23` (FT4 glasses blockers — fix before the next round) and `B14` (parallel,
separate repo) lead · then `B1 → B2 → B3 → B4` (P0 foundations) · then `B5 → B6`
(phone-only hero floor) `→ B7 → B8` (watch hero + GPS) · then `B9 → B10 → B11`
(on-course/watch UX) · then `B12 → B13` (off-course) · then `B16 → B15 → B17 → B18`
(glasses; do **B17 with B22** — shared freshness cue) · then `B19 → B20 → B21`
(robustness/hygiene). Ship after each — every item is independently landable, and the
four-config matrix (below) must stay green throughout.

## 7. Config matrix — keep all four green after every change

| Config | Input | Output | Must work |
|---|---|---|---|
| Phone only | score stepper + passive track + `Mark here` | phone screen | ✅ (B6 is the floor) |
| Phone + watch | watch auto-detect (primary) + watch/phone taps | phone screen | ✅ (B7) |
| Phone + glasses (no watch) | glasses input gated on `glassesInputEnabled` + phone | glasses HUD + phone | ✅ (B18) |
| All three | watch primary, phone backstop | glasses HUD + phone | ✅ |

## 8. Verification quick-reference

- **Phone unit tests** (`golf-caddie` target): keep `ShotReconcilerTests`,
  `GlassesStateMapperTests`, `LiveSwingDetectorTests` green; add idempotency tests (B2),
  source/putt-tagging tests (B3), reconstruction + dedup tests (B6/B7).
- **Glasses contract acceptance** (`IOS_INTEGRATION_CONTRACT.md`): the
  `curl 127.0.0.1:8417/api/...` checks for state/shot/undo/club/advance; re-run after B16.
- **Glasses simulator**: `npm run dev:mock` + `npm run dev` + the evenhub simulator; drive
  via `POST :9898/api/input` — use for B18 (no-watch config) and B17 (reconnect/staleness).
- **Watch**: watchOS simulator for the card/haptic/delivery behavior (B1, B4, B19); one
  real-device round before trusting reconstruction end-to-end.
- **Reconstruction**: record a real round's track, then replay through B5–B7 with the
  T/R stop tunables; verify pin counts vs known scores and amber-flag behavior.

## 9. Out of scope (do not start without a new decision)

- Front/back/three-point green distances (deliberately deferred until course data
  supports it).
- Deleting the glasses input path (kept + gated, B18) or the spike tooling (DEBUG-flagged,
  B20).
- New features beyond this brief: voice notes, multi-user, social, deep stats/analysis
  (the per-club averages that fall out of reconstruction are in scope; a full stats
  surface is not).

---

## 10. Traceability — every source-doc item → backlog ID (audit the merge)

**IMPROVEMENTS_HANDOFF.md (1–13):**

| # | IMPROVEMENTS item | Lands in | Note |
|---|---|---|---|
| 1 | Stop dropping concurrent detections | **B1** | Resolved via auto-log model (no FIFO needed) |
| 2 | DetectCard timeout = discard + haptic | **B1** | Timeout → **auto-accept-keep** (DESIGN), haptic requirement kept (D2) |
| 3a | Transport idempotency (UUID on commands) | **B2** | — |
| 3b | Semantic cross-source dedup funnel | **B6/B7** | Becomes hole-out **reconciliation** |
| 4 | Watch→phone delivery feedback | **B4** | — |
| 5 | Distinguish manual vs auto (`watchManual`) | **B3** | + `isPutt`/`confidence`/`reconstructed` |
| 6 | Consistent GPS capture | **B8** | Re-scoped: track = source of truth |
| 7 | Workout failure + battery duty-cycle | **B19** | — |
| 8 | Gate & test glasses input fallback | **B18** | — |
| 9 | Spike/validation behind `#if DEBUG` | **B20** | — |
| 10 | Glasses polling/reconnect/battery | **B17** | Folded into HUD work |
| 11 | Honest front/back yardages | **B9 + B11** | Resolved by middle-only (both surfaces drop it) |
| 12 | `lastShot` contract drift | **B16** | Coupled to D1 (HUD wants distance) |
| 13 | Doc + flag hygiene | **B21** | — |

**design_handoff_frictionless_round (priorities + screens + contract):**

| DESIGN item | Lands in | Note |
|---|---|---|
| #1 End-of-hole reconstruction (Path B first, then Path A) | **B5 + B6 + B7** | The spine; Path B (B6) is the floor |
| #2 Yardage-hero on-course screen | **B9 + B10** | + auto-advance (B10) |
| #3 Auto-accept confirm card (Watch) | **B1** (behavior) + **B11** (UI) | Pulled forward to P0 |
| #3 Home resume-first (Fig. 3) | **B12** | — |
| #3 Scorecard + reconstruction inbox (Fig. 3) | **B13** | — |
| #4 Tee anchors + green-aware putt entry | **B14** (tee) + **B11** (putts) | — |
| #5 Full glasses HUD + auto hole-advance | **B15** (HUD) + **B10** (advance) | — |
| Data contract — one yardage (middle) | **B9 / B11 / B15** | — |
| Data contract — anchors (tee + greenCenter + opt. polygon) | **B14** | — |
| Data contract — armed club shared | **B11 / B15** | predicted from learned averages |
| Data contract — device roles | §4 invariants | preserved |
| Design tokens (reuse existing themes) | guidance in §3 + every UI item | tokens already implemented |

**Field test 4 — Emerald Isle (2026-06-20), `docs/FIELD_TEST_4_EMERALD_ISLE.md`:**

| FT4 # | Finding | Lands in | Note |
|---|---|---|---|
| 1 | Glasses sync freeze (stale HUD several strokes) | **B22** (new) | Likely poll loop; + liveness cue shared w/ B17 |
| 2 | Glasses club over-sensitivity (regression) | **B23** (new) | Bisect since Welk `1e0cc28`/`81d504b` |
| 3 | Watch battery (Series 6 20 % by hole 14) | **B19** | Concrete drain figure; device below floor |
| 4 | Swing tracking + manual putt marking worked | — (positive) | De-risks B1/B7 detector, B11 putts |
| 5 | Watch died → glasses became input | **B18** | Lifeboat is real; B23 blocks its usability |
| 6 | Phone shot-mark latency | **B8** | Field-validates the ≤5 s ramp removal |
| 7 | Edit current hole from map (no advance) | **B7 / B6** | In-round current-hole pin/club editing |
| 8 | Static green-north map orientation | **B9** | Map projection (no heading rotation) |
| 9 | Render green marker on the map | **B9** | `greenAnchor` exists; draw it |

---

*Generated by reconciling `IMPROVEMENTS_HANDOFF.md` and
`design_handoff_frictionless_round/` against a 2026-06-20 read of all three repos, and
updated 2026-06-21 to fold in `FIELD_TEST_4_EMERALD_ISLE.md` (items B22–B23 + §2.5 + FT4
field signals on B7/B8/B9/B18/B19). Supersedes neither source doc as a reference — but
this is the single backlog to implement from.*
