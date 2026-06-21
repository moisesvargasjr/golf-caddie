# Golf Caddie — Improvements Handoff

> Cross-repo work brief for a coding agent. Covers three repos:
> - `golf-caddie/` — iOS phone app (the brain) + `GolfCaddieWatch/` target
> - `golf-caddie-glasses/` — Even Realities G2 HUD app (TypeScript/Vite)
> - `golf-caddie-coursedata/` — curated course data (no code changes here; reference only)
>
> Paths below are **relative to each repo's root** and labelled `[phone]`,
> `[watch]`, `[glasses]`. Line numbers are from the review snapshot
> (2026-06-20) — treat them as starting points, not gospel; confirm by reading.

## Product decisions driving this work (already made — do not relitigate)

1. **Auto-detect is the PRIMARY capture path.** The watch swing detector is the
   main way shots get logged. Manual tap (watch MARK SHOT, phone button, Action
   button) is a **backstop for false negatives only**. This means the detector
   must be trustworthy enough to replace 18Birdies — no lost shots, no silent
   phantom shots, no double-counts.
2. **Glasses are output-only on the live path, but the input fallback STAYS** as
   a real "watch died / playing phone+glasses with no watch" lifeboat. It must be
   properly gated and tested, not deleted.
3. **Spike/validation tooling is feature-flagged behind `#if DEBUG`**, not
   deleted — detector re-tuning may still need it.
4. The "works in any combination" promise must hold: **phone-only**,
   **phone+watch**, **phone+glasses (no watch)**, **all three**. Each config is a
   first-class supported mode (see "Config matrix" at the bottom — keep all four
   green).

## Invariants — do NOT break these while doing the work

- **Glasses wire contract encoding** (`golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md`):
  no JSON `null` (omit absent keys), short club names, `score = shotCount +
  penalties`, ISO-8601 without fractional seconds, trailing-empty-hole trimmed.
  The phone `GlassesStateMapper` and the TS `shared/types.ts` are lockstep.
- **Read-after-write**: any POST to the phone server returns a `GolfState` that
  already includes the write's effect.
- **W1 fast-path discipline**: glasses/watch shot logging must NOT block on the
  5s `captureBestFix` GPS ramp. Only the phone on-screen button / Action button
  may use the slow precise capture (and see item 6 about consistency).
- **Phone-only must keep working** with no watch and no glasses present.

---

# Prioritized backlog

Ranked. Items 1–6 are on-course correctness (do first; each independently
shippable). 7–9 are robustness. 10–13 are simplification / hygiene / drift.

---

## 1. Stop dropping concurrent swing detections (no lost shots) — CRITICAL

**Problem.** `[watch] GolfCaddieWatch/LiveSessionController.swift:~142`
(`handleDetection`) guards `pending == nil`, so while a `DetectCard` is showing
(up to its 5s timeout) **any new detection is silently discarded**. With
auto-detect as the primary path, a real shot struck within ~5s of a prior
detection is lost. It also means the phone's step-gate reconciler usually never
sees the bursts it was built to collapse.

**Fix.**
- Replace the single `pending` slot with a **FIFO queue** of detected swings.
  Each detection enqueues; the card shows the head; resolving (confirm/discard)
  pops and shows the next.
- A detection must NEVER be dropped on the floor. If the UI can't keep up, the
  swing still gets sent to the phone (the phone reconciler + cross-source dedup,
  items 2–3, are the safety net) — losing a real shot is worse than an extra one.
- Reconsider whether the per-swing card is even right for an "always-on primary"
  detector. Strong recommendation: **decouple detection→log from the card.**
  Auto-log every detection immediately (tagged `source=.watchAuto`) and let the
  card become a *non-blocking "Not a shot — undo" toast* (5s, default = keep).
  This removes the queue-stall class of bug entirely and makes the phone
  reconciler the real practice-swing collapser. If you keep a blocking card,
  the queue above is mandatory.

**Acceptance.**
- Simulate 3 detections 1.5s apart: all 3 reach the phone (verify
  `currentHoleShots` / `GET /api/state` shot count), none dropped.
- Reconciler still collapses zero-step bursts to the real shot (existing
  `ShotReconcilerTests` stay green).

---

## 2. DetectCard timeout = DISCARD, and haptic on every auto-log

**Problem.** `[watch] GolfCaddieWatch/WatchRootView.swift:~619` — the DetectCard
**auto-confirms** after a 5s timeout, and `confirmPending()`
(`LiveSessionController.swift:~151`) plays **no haptic**. Wrist-down on the
course, a practice swing or waggle pops a card the golfer never sees and it
logs silently. Worst case for data trust.

**Fix.** This depends on item 1's card decision:
- If you keep a blocking confirm card: **timeout must DISCARD**, not confirm.
  Only an explicit tap logs.
- If you adopt the "auto-log + undo toast" model: the toast timeout **keeps**
  the shot (it's already logged); the only action is "Not a shot" → undo.
- **Either way: play a distinct haptic at the moment a shot is auto-logged**
  (not only when a card is raised). The golfer must feel every shot that lands
  in the data without looking. Use a different haptic from the manual-tap
  `.success` so the two are distinguishable by feel.

**Acceptance.** No shot is ever written to the DB without either an explicit
user tap OR a felt haptic. Verify on the watchOS simulator + a real-device pass.

---

## 3. Cross-source shot dedup + idempotency (no double-logs) — CRITICAL

**Problem.** Nine shot-creation entry points across five `ShotSource` values
(`[phone] GolfCaddie/Models/Shot.swift:4-9`) with **no cross-source dedup**. With
auto-detect primary AND a manual backstop, the dangerous case is: detector fires
for a swing **and** the golfer (not trusting it yet) also taps MARK SHOT →
**two `Shot` rows for one swing**. Separately, watch→phone commands carry no id,
so a flaky link + user re-tap can double-log or double-advance.

**Fix — two independent layers:**

a) **Transport idempotency (watch→phone).** Add a `UUID` to every
   `WatchCommand` (`[phone] GolfCaddie/Shared/SwingEventContract.swift`, and the
   watch sender). `SwingEvent` already has an `id` — extend the same discipline
   to `.addShot`, `.advanceHole`, `.previousHole`, `.puttPlusOne`,
   `.removeStroke`. The phone (`LiveShotCoordinator.handle`) keeps a small
   recently-applied-id set and ignores duplicates. This kills double-advance and
   double-log from retried `transferUserInfo`.

b) **Semantic cross-source dedup (the funnel).** Route ALL shot creation
   (`ingestAutoShot`, `addShotFromWatch`, `markShotInternal`,
   `logShotFromGlasses`, `markPutt`, casual stroke) through a single ingest
   funnel in `[phone] RoundController` that rejects a new shot if one already
   exists on the active hole within a **time window** (recommend ~4s, tunable)
   AND, when both have fixes, a small spatial window — UNLESS the caller marks
   it as an explicit distinct stroke. Manual backstop tap inside the window
   should **merge into / replace** the auto shot (preferring the manual club
   selection) rather than add a second row. Putts (`.putter`) are exempt from
   collapsing into a non-putt auto shot.

   Be careful with async ordering: auto shots arrive via the 3s debounce +
   reconciler (`LiveShotCoordinator.commitPending`), so the funnel must dedup
   against shots that may land slightly after a manual tap, not only before.

**Acceptance.**
- Auto-detect a swing, then tap MARK SHOT within 4s → exactly **one** shot,
  carrying the manually-selected club if one was set.
- Re-send the same `addShot` command id twice → one shot.
- Two genuinely separate shots >4s apart (or with a step between) → two shots.
- Add unit tests alongside `ShotReconcilerTests`.

---

## 4. Watch→phone delivery feedback (no silent loss)

**Problem.** `[watch] GolfCaddieWatch/WatchSession.swift:~26-29` calls
`transferUserInfo` and ignores the result; there's no `didFinishUserInfoTransfer`
delegate, and the UI gives the same `.success` haptic whether the phone received
the command or it's queued for an hour (phone in the bag, 40ft away, or dead).
The `RESEND` button only resends *files*, not queued commands.

**Fix.**
- Implement `session(_:didFinish userInfoTransfer:error:)` and track outstanding
  command transfers (not just file transfers — current `refreshOutstanding`
  reads `outstandingFileTransfers` only).
- Surface a lightweight on-watch indicator when commands are queued/unconfirmed
  (e.g. a small "syncing N" chip on the play screen), distinct from "delivered."
- Do NOT auto-retry semantically — idempotency from item 3a makes at-least-once
  safe, but the user should be able to *see* a backlog rather than be told
  everything's fine.

**Acceptance.** With the phone unreachable, marking shots / advancing holes shows
an unconfirmed/queued state on the watch; when the phone reconnects, the backlog
drains and the indicator clears. No double-applied actions (item 3a).

---

## 5. Distinguish manual taps from auto-detections in the data

**Problem.** `[phone] RoundController.addShotFromWatch` and `addPuttFromWatch`
route through `ingestAutoShot` with `source: .watchAuto` — so a deliberate
manual watch tap is indistinguishable from an auto-detected swing. This
undermines the per-club stats and "trust the data" goal, and makes it impossible
to later measure detector precision/recall from real rounds.

**Fix.**
- Add `ShotSource.watchManual` (and use it for `addShotFromWatch`). Keep
  `.watchAuto` strictly for detector-originated shots. `addPuttFromWatch` →
  `.watchManual` with `club: .putter`.
- Audit every shot path so `source` is always truthful (the funnel in item 3
  is a natural place to enforce this).

**Acceptance.** A round logged via auto-detect + a couple manual taps shows the
correct `source` per shot in the DB export. No path writes a misleading source.

---

## 6. Consistent GPS capture within a round

**Problem.** Two strategies coexist: the phone button / Action button use
`captureBestFix()` (a ≤5s best-accuracy ramp), while watch/glasses/auto paths use
`location.latestLocation` (whatever's fresh). Shots in one round therefore have
inconsistent positional accuracy depending on which device logged them — noise
straight into distance stats. With auto-detect primary, **most** shots will use
the fast `latestLocation` path, so the slow precise path is now the outlier.

**Fix.**
- Standardize on the **fast `latestLocation`** path for all live logging
  (continuous best-accuracy tracking already runs during a round, so fixes are
  fresh). Keep `captureBestFix` only where there's genuinely no continuous
  tracking pressure, or drop it entirely if the round always tracks.
- Record `gpsAccuracy` honestly on every shot so downstream stats can weight or
  filter by it.
- Do not regress W1 (no path should reintroduce a 5s block on the watch/glasses
  flow).

**Acceptance.** All live-logged shots in a round draw their fix from the same
mechanism; `gpsAccuracy` is populated and comparable across sources.

---

## 7. Surface watch background-session failure + battery duty-cycle

**Problem.** `[watch] WorkoutKeeper.workoutSession(didFailWithError:)` reports a
message but `LiveSessionController` `onFailure` only sets `lastError`, shown on
the **start** screen, not the play screen. If the HK session dies mid-round,
motion delivery stops, the listening meter freezes, detections stop — and the
play screen looks **completely normal**. Separately, three motion streams
(accel 100Hz + gyro 100Hz + deviceMotion 50Hz, `MotionRecorder.start:~81-83`)
run continuously for a 4–5hr round with no duty-cycling and no
`WKExtendedRuntimeSession` fallback.

**Fix.**
- On workout-session failure mid-round: show a clear banner on the **play**
  screen ("Tracking paused — tap to resume"), attempt auto-restart of the
  workout + recorder, and stop pretending the listening meter is live (it should
  visibly read "not sensing").
- Add a `WKExtendedRuntimeSession` as a fallback keep-alive, or document why the
  workout session alone is sufficient.
- Battery: the production capture rates need a deliberate decision. The
  *detector* needs its rates; but consider duty-cycling (e.g. drop to a low-rate
  "armed" mode when stationary detection of address isn't needed, or lower
  deviceMotion when the detector only consumes accel+gyro). Measure drain on a
  real 4–5hr round and record the number.

**Acceptance.** Killing the workout session mid-round produces a visible play-
screen state and a recovery path; a full-round battery figure is recorded.

---

## 8. Properly gate & test the glasses input fallback (keep the 4-way matrix)

**Problem.** Glasses are output-only on the live path, but the input fallback
("watch died / phone+glasses with no watch") is half-wired: the
`glassesInputEnabled` flag is advertised in the read model
(`[phone] GolfCaddie/Glasses/GolfState.swift:~22-25`) but the server's POST
handlers (`GlassesServer.swift:~169-216`) run the mutations **regardless of the
flag**. And the glasses-side input modules are dead weight on the hot path.

**Fix.**
- `[phone]` Server **rejects writes when `glassesInputEnabled == false`**
  (return the contract's 409/appropriate error), so the flag is the real
  authority for whether glasses input is allowed. When the watch is the active
  input device, the flag is false and the server refuses glasses writes; when
  the user flips to the no-watch fallback, the flag flips true and writes work.
- `[glasses]` Code-split the input lane (`command-client.ts`,
  `screens/club.ts`, `screens/actions.ts`, the optimistic-write/arm router
  branches) so it is **lazily loaded only when `glassesInputEnabled` is true**
  in the polled state — not parsed/run on every output-only round.
- **Test the phone+glasses-no-watch config end to end** (the simulator
  automation API can drive gestures; see the glasses README). This config is the
  whole reason the code stays — prove it works.

**Acceptance.**
- With `glassesInputEnabled=false`, `POST /api/shot` etc. are rejected and the
  glasses never enter input mode.
- With it true and no watch, a full hole can be played from the glasses (log
  shot, set club, advance hole) and the phone reflects it.
- Output-only rounds don't load the input modules (verify via bundle/log).

---

## 9. Feature-flag the spike/validation subsystem behind `#if DEBUG`

**Problem.** Raw-motion recording + ground-truth tooling ships in production:
`[watch]` `MotionRecorder` raw `dm/accel/gyro.bin` writers, the
`VALIDATION`/`MARK`/`RESEND` UI in `WatchRootView`, `transferFile`/`resendAll`,
and `[phone]` `Debug/SpikeSessionReceiver.swift`, `Debug/SpikeSessionsView.swift`,
plus the Settings export UI hook.

**Fix.**
- Wrap all of it in `#if DEBUG … #endif` (both targets) so release builds
  exclude it but dev builds keep it for detector re-tuning.
- Make sure the watch play screen has **no** validation affordances in release
  (the `VALIDATION ON/OFF` toggle, `RESEND n`, the validation-only `MARK`
  button must compile out).
- Keep `DebugHarness.swift` (DEBUG-only already) as the in-app way to replay
  swing events through `LiveShotCoordinator`.

**Acceptance.** A release build contains no spike-recording code paths or UI; a
DEBUG build is unchanged.

---

## 10. Glasses polling, reconnect honesty, and battery visibility

**Problem.** `[glasses] src/app/api-client.ts:~16` `POLL_MS = 600` — 4× faster
than every doc (0.6 / 1.5 / 2–3s) and a real battery cost on phone + glasses over
a round. On a dropped link, `router.ts:~160-162` keeps rendering the last-good
HUD for a 7s grace window (`RECONNECT_GRACE_MS`) **with no staleness cue** — the
golfer sees live-looking yardage/GPS that's actually frozen. And `battery` is on
the wire (`types.ts:~66`) but never rendered, so the phone (single source of
truth) going flat is invisible.

**Fix.**
- Pick one poll cadence (recommend ~1500ms — green-distance was the reason it
  was lowered; 600ms is overkill) and make code + all three docs agree.
- During the reconnect grace window, show a subtle staleness indicator (e.g. dim
  the GPS/yardage or a small "last seen Xs ago") so a frozen HUD never reads as
  live.
- Render `battery` somewhere unobtrusive on the HUD (and/or a low-battery
  warning under ~15%).

**Acceptance.** One cadence value across code + docs; a dropped link is visually
distinguishable from a live HUD within the grace window; phone battery is
visible.

---

## 11. Honest front/back-of-green yardages

**Problem.** `[watch] WatchRootView.swift:~225-226` shows front/back as
`green − 7` / `green + 9` hardcoded offsets, presented as if they were real
front/back distances.

**Fix.** Either compute true front/back from curated green-anchor geometry when
available (the coursedata repo's `greenAnchor`), or stop labelling the offsets as
front/back and show only the single center-of-green distance. Don't present
fabricated precision.

**Acceptance.** Any front/back number shown is either geometry-derived or removed.

---

## 12. Reconcile the `lastShot` contract drift across three places

**Problem.** Three sources disagree:
- `[phone] GlassesStateMapper.swift:~201-207` ships `lastShot = { club: latest
  swing, sequenceNumber }`, **no `distanceYards`**.
- `golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md:~87` still documents
  `lastShot = { club: PRIOR shot, distanceYards: 248, sequenceNumber }`.
- `[glasses] src/shared/types.ts:~45-53` omits `distanceYards`.

The doc was flipped twice (field-test-3 said prior-club+distance; the 2026-06-19
note reverted to last-swing club, no distance).

**Fix.** Decide the intended semantic (the iOS code's current "club you last
actually swung, no distance" is the most recent decision and the simplest), then
make the contract doc + `types.ts` + mapper all match it verbatim, and remove the
stale field-test-3 resolution text or mark it superseded.

**Acceptance.** All three agree; a diff of the contract example vs `types.ts` vs
the mapper output shows no schema mismatch.

---

## 13. Doc + flag hygiene

- Update `[phone] golf-caddie/DESIGN.md` — it still describes phone-only Phase 1
  with Watch in "Phase 6." Add a short "Current architecture" section reflecting
  watch-primary auto-detect + output-only glasses, or link this handoff.
- `golf-caddie-glasses/docs/ARCHITECTURE.md` poll cadence (2–3s) → reconcile with
  item 10.
- Document the `glassesInputEnabled` flag's real meaning once item 8 gives it
  teeth (it now actually gates server writes).
- Remove dead vestiges noted in review (e.g. `WatchHeader` `accentTime` param;
  the no-op `justConfirmed.par = currentHole.par` reassignment in
  `RoundController.advanceHoleFromGlasses`).

---

# Config matrix — keep all four green after every change

| Config | Input | Output | Must work |
|---|---|---|---|
| Phone only | phone buttons + Action button + casual mode | phone screen | ✅ |
| Phone + watch | watch auto-detect (primary) + watch/phone taps | phone screen | ✅ |
| Phone + glasses (no watch) | glasses input (gated on `glassesInputEnabled`) + phone | glasses HUD + phone | ✅ (item 8) |
| All three | watch primary, phone backstop | glasses HUD + phone | ✅ |

# Verification quick-reference

- **Phone unit tests**: `golf-caddie` test target — keep
  `ShotReconcilerTests`, `GlassesStateMapperTests`, `LiveSwingDetectorTests`
  green; add dedup tests (item 3) and source-tagging tests (item 5).
- **Glasses contract acceptance** (`IOS_INTEGRATION_CONTRACT.md` "Acceptance"):
  the `curl 127.0.0.1:8417/api/...` checks for state/shot/undo/club/advance.
- **Glasses simulator**: `npm run dev:mock` + `npm run dev` + the evenhub
  simulator; drive via `POST :9898/api/input`. Use it for item 8's no-watch
  config test and item 10's reconnect/staleness behavior.
- **Watch**: watchOS simulator for the queue/timeout/haptic behavior (items 1–2,
  4, 7); one real-device round before trusting auto-detect as primary.

# Out of scope (do not start without a new decision)

- Deleting the glasses input path (we chose to keep + gate it).
- Deleting the spike tooling (we chose DEBUG-flag).
- New features (voice notes, stats/analysis, multi-user). This brief is
  correctness + simplification only.
