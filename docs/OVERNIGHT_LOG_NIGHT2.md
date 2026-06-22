# Overnight Log — Night 2 (contract + coursedata + hygiene)

> Batch run unattended per `docs/OVERNIGHT_KICKOFF_NIGHT2.md`. Scope (in order):
> **B16** (lastShot contract = club-only), **B14** (Course Desk tee anchors + completeness),
> **B23** (investigate glasses club-scroll regression — investigation-first), **B21** (doc/flag/dead-code hygiene).
> Locked decision **D1 = club-only, NO distance** anywhere. B6/B7 reconstruction explicitly out of scope.

**Branches:** `overnight/night2` in golf-caddie, golf-caddie-glasses, golf-caddie-coursedata (off `main`, started clean except coursedata's pre-existing uncommitted `tools/green-marker.html` satellite-layer edit, which is the user's WIP and is left untouched / unstaged).

**Environment:** Xcode 27.0 (`/Applications/Xcode-beta.app`), test sim **iPhone 17 Pro** (booted). Memory free ~37% at start.

---

## Status board

| Item | Repo(s) | Status | Commit(s) |
|---|---|---|---|
| B16 | glasses (+phone verify) | ✅ done | glasses `1169b0b` |
| B14 | coursedata | ✅ done | coursedata `71c1482` |
| B23 | glasses | 🟡 partial (investigation done; fix NEEDS G2) | glasses `25aa3c3` |
| B21 | golf-caddie + glasses | ✅ done | golf-caddie `83fd661` · glasses `28c3348` |

---

## B16 — lastShot contract = club-only — ✅ done

**Status:** done. Commit `1169b0b` (golf-caddie-glasses). Doc-only — no code change.

**Finding:** the code already agreed on club-only everywhere; only the contract
doc was stale. Verified club-only in: phone `LastShotDTO` (`GolfState.swift:77-86`)
+ `GlassesStateMapper.lastShotDTO` (`:201-207`); glasses `src/shared/types.ts:45-52`;
consumers `hud.ts`/`actions.ts`; mock server. No `distanceYards` exists anywhere on
the `lastShot` path (the field only lives on the separate scorecard `shots[]` type).

**Changed:** `golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md` only:
- GET /api/state example (line 88): replaced the bogus
  `lastShot {club:"Dr", distanceYards:248, ...}` / "PRIOR shot's club" with
  club-only `{ club, sequenceNumber }`.
- Superseded the field-test-3 "lastShot.club = prior shot's club + distance"
  subsection with a club-only note (most-recently-swung club; no distance;
  per-stroke distances live on `holes[].shots[].distanceYards`). Wire invariants
  (omit-when-nil, short club names) preserved.

**Checks:** glasses `npm run build && typecheck` → pass. Phone
`xcodebuild test -only-testing:GolfCaddieTests/GlassesStateMapperTests`
(iPhone 17 Pro) → **21/21 pass**, incl. `test_lastShot_isMostRecentSwungClub`,
`test_lastShot_singleShotShowsThatClub`.

**No decision/hardware needed.**

## B14 — Course Desk: tee anchors + completeness checklist — ✅ done

**Status:** done (build-green; **needs a visual check in the browser** — the
curation UI is not headlessly verifiable). Commit `71c1482` (coursedata).

**Key decision — field name is `teeAnchor`, not `tee`.** The kickoff said
`tee:{lat,lng}`, but the canonical optional field already exists across the
lockstep contract: `src/schema.ts` (`teeAnchor?: GeoPoint`), `validate.ts`
(validates it), `server.ts` save (applies it), and the **iOS decoder**
(`CuratedHole.teeAnchor`, default Codable key). Writing `teeAnchor` keeps
phone↔coursedata lockstep with **no schemaVersion bump**. A new `tee` field
would have broken that. No tee coords were fabricated; existing `greenAnchor`
data is untouched (server merges field-by-field); `courses.json` unchanged.

**Changed (3 files):**
- `tools/green-marker.html` — Green/Tee **mode toggle**; drop+drag a **tee
  marker per hole** (distinct blue pin), seeded from existing `teeAnchor`s; the
  hole list is now an **18-row par/tee/green checklist**; dual greens/tees
  counters; Save writes `greenAnchor` and/or `teeAnchor` per hole.
- `tools/server.ts` — `/api/courses` returns a `tees` count; **`/api/publish`
  gates on completeness** (409 + missing-hole list unless `override:true`).
- `tools/curate.html` — per-course **tees badge** + catalog completeness line;
  **Publish disabled** until every hole has par+tee+green, or override ticked.

**User-WIP handling:** `green-marker.html` had the user's uncommitted
satellite-layer edit. I `git stash`-ed it (path-scoped), did B14 in
non-overlapping regions, committed, then `git stash pop` — clean auto-merge,
no conflicts. Verified: the B14 commit contains **zero** satellite code; the
only remaining uncommitted diff is the user's satellite WIP, intact.

**Checks:** `npm run validate` → courses.json valid; `npm run typecheck` →
pass; both tools' inline JS `node --check` → parse OK.

**Needs:** a visual pass in the course-curation web app (drop a tee, drag it,
watch the checklist + publish gate) before trusting end-to-end.

## B23 — Glasses club-scroll over-sensitivity (INVESTIGATE) — 🟡 partial

**Status:** partial by design (investigation is the deliverable; the fix is
committed but **NEEDS G2 CONFIRMATION** — no hardware to tune/verify). Commit
`25aa3c3` (glasses). Full write-up: `golf-caddie-glasses/docs/B23_INVESTIGATION.md`.

**Root cause (triple-verified, unanimous):** the input lanes step the cursor
**once per raw SDK `SCROLL` event** with **no debounce/accumulator/threshold**.
The G2 touchpad fires a **burst** of `SCROLL` events per physical swipe → one
swipe = N steps → skips past the intended club. It's the step mapping in
**`router.ts`**, **not** `input.ts`/`screens/club.ts` (the backlog's pointers —
both proven inert: `input.ts` untouched since the initial commit; `club.ts` is a
pure render module). The 1:1 mapping is latent/pre-existing; commit **`e9d27dc`**
reintroduced the club lane that **`1e0cc28`** had deleted at Welk, re-exposing
it. It bit at FT4 because that was the first input-mode round since the lane
returned (watch died → glasses became input).

**Backlog correction:** suspect `81d504b` is **not in the glasses repo** (it's
the phone yardage-consistency fix). The only post-Welk commits touching the
input path are `1e0cc28` and `e9d27dc`.

**Fix (guarded):** a single **scroll-burst coalescer** in `handleGesture` —
a leading-edge "quiet window" (`SCROLL_QUIET_MS=150`, every scroll event resets
the window) so one swipe = one step across **all** lanes (club, screen,
output-only scorecard), robust to long inertial bursts. Clicks/double-clicks
untouched.

**Checks:** `npm run build && npm run typecheck` pass.

**Needs (decision/hardware):** tune `SCROLL_QUIET_MS` on a real G2 and confirm
the club lane lands on the intended club end-to-end (ties to B18 no-watch test).
Do **not** mark "done" until that hardware pass.

## B21 — Doc + flag + dead-code hygiene — ✅ done

**Status:** done. Commits `83fd661` (golf-caddie) + `28c3348` (glasses).

**Dead code removed (phone):**
- `WatchHeader.accentTime` param (no longer draws a clock) + its one call site
  (`WatchRootView.swift`).
- The no-op `justConfirmed.par = currentHole.par` in
  `RoundController.advanceHoleFromGlasses` (`justConfirmed` is a copy of
  `currentHole`; par already equal — only `confirmedAt` changes).

**Docs:**
- `golf-caddie/DESIGN.md`: added a "Current architecture (2026)" section
  (watch-primary detection → hole-out reconstruction → output-only glasses;
  phone = source of truth; four configs; middle-only yardage) and flagged the
  old Phase 1–6 framing as historical → `docs/RECONCILED_BACKLOG.md`.
- `golf-caddie/docs/RECONCILED_BACKLOG.md`: Build-status banner (night-1
  B2/B3/B4/B5/B8/B17/B20 merged; night-2 B16/B14/B23/B21 in review) + **D1
  marked RESOLVED** (club-only, no distance; old "ship distanceYards" rec
  superseded).
- `golf-caddie-glasses/docs/ARCHITECTURE.md`: new "Input gating
  (`glassesInputEnabled`)" section documenting the **current** meaning
  (client-side lane gating + read-model advertisement; phone server does **not**
  yet reject writes — that's the open B18). **Poll cadence needed no change** —
  line 39 already reads "~1.5s (B17)", matching `api-client.ts` `POLL_MS=1500`.

**Deferred (decision for you):** the `SpikeSessionReceiver` rename. A symbol-only
rename is build-safe, but the class now serves the **production**
WatchConnectivity path (not just spike debug) and the committed `.pbxproj`
hard-references the file by path, so a clean rename wants an `xcodegen` regen —
better done in-the-loop than unattended. Noted in the commit; not done.

**Checks:** `GolfCaddie` scheme **BUILD SUCCEEDED** (iPhone 17 Pro) — both
`RoundController.swift` and `WatchRootView.swift` compile (one pre-existing,
unrelated actor-isolation warning at `WatchRootView.swift:652`).

---

## Summary

**All 4 items handled; 3 fully done, 1 partial-by-design (B23 needs G2).**
Each is an independent, build-green commit prefixed with its ID, on
`overnight/night2` in each repo. Nothing touched `main`; no force-pushes; no
`.zip`/`.claude`/xcodecloud committed. Branches are **local only — not pushed**
(open a PR per repo to review/merge).

**Ready to review, per repo:**
- **golf-caddie-glasses** (`overnight/night2`): `1169b0b` B16 (contract doc
  club-only) · `25aa3c3` B23 (investigation + guarded scroll-burst fix,
  **NEEDS G2**) · `28c3348` B21 (glassesInputEnabled doc).
- **golf-caddie-coursedata** (`overnight/night2`): `71c1482` B14 (tee anchors +
  completeness gate). _Needs a browser visual check._ The user's uncommitted
  `green-marker.html` satellite-layer WIP was preserved (stash dance) and is
  **still uncommitted** in the working tree — commit it wherever you like.
- **golf-caddie** (`overnight/night2`): `83fd661` B21 (dead code + DESIGN.md +
  backlog status/D1) + this log (`docs:` commit).

**Decisions honored:** D1 = club-only, no distance (no distance field added
anywhere). B6/B7 left untouched (out of scope). B14 uses the existing
`teeAnchor` field (not a new `tee`) to stay in iOS lockstep — **deviation from
the kickoff's literal `tee` wording, on purpose; flag if you disagree.**

**Follow-ups / needs you:**
1. **B23 fix needs a real-G2 pass** — tune `SCROLL_QUIET_MS` (150 ms blind
   default) and confirm the club lane lands on the intended club. Keep B23
   *partial* until then.
2. **B14 needs a browser visual check** in the curation web app (drop/drag a
   tee, watch the 18-row checklist + the publish gate/override).
3. **SpikeSessionReceiver rename** deferred — decide whether to do the
   symbol/file rename in-the-loop (it's now a production WC delegate).
4. Decide if you want the night-2 branches opened as PRs (mirrors night-1's
   per-repo PR flow).
