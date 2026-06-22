# Overnight Agent Kickoff — Night 2 (contract + coursedata + hygiene)

> **For the human launching this:** open a Claude Code session in `~/source/golf-caddie`,
> run `/model sonnet` then `/effort high`, allow `xcodebuild`/`xcodegen`/`npm`/`git` (or an
> accept-all/bypass mode — safe, the work is branched and never touches `main`), keep the
> Mac awake (`caffeinate -dimsu`), then tell the agent:
> **"Read `docs/OVERNIGHT_KICKOFF_NIGHT2.md` and follow it exactly."**
> This batch touches THREE repos (golf-caddie, golf-caddie-glasses, golf-caddie-coursedata).
> Review in the morning via `docs/OVERNIGHT_LOG_NIGHT2.md` + the PR in each repo.

---

You are implementing a small, low-risk batch overnight, unattended. Optimize for a clean,
per-item-reviewable result. Correctness and reviewability beat finishing everything.

## Source of truth & decisions already made
Read `docs/RECONCILED_BACKLOG.md` FIRST for the full per-item spec. Night-1 items (B2, B3,
B4, B5, B8, B17, B20) are already merged to `main` — start from current `main`. Locked
decisions for this batch:
- **D1 is DECIDED: keep the glasses `lastShot` CLUB-ONLY, with NO distance.** Do NOT add a
  distance field anywhere. (This is the opposite of the old "ship distanceYards"
  recommendation still written in the backlog — ignore that recommendation; honor this.)
- **B6/B7 reconstruction is NOT in scope** — it's a separate in-the-loop session.

## Scope — do ONLY these 4 items, in order
1. **B16** — Reconcile the `lastShot` contract on **club-only** (golf-caddie + glasses)
2. **B14** — Course Desk: tee anchors + completeness checklist (golf-caddie-coursedata)
3. **B23** — **INVESTIGATE ONLY** the glasses club-scroll regression (golf-caddie-glasses)
4. **B21** — Doc + flag + dead-code hygiene (golf-caddie + glasses)

Do NOT start anything else — especially B6/B7, B1, B18, B19, B22, or any UI redesign
(B9–B15). If you finish early, STOP and write your summary.

### B16 — lastShot contract = club-only (no distance)
The code already agrees on club-only; the **contract doc is stale**. Make all three match
exactly on `lastShot = { club, sequenceNumber }` (NO `distanceYards`):
- `GolfCaddie/Glasses/GlassesStateMapper.swift` (`lastShotDTO`) — confirm club-only; no change expected.
- `golf-caddie-glasses/src/shared/types.ts` (`lastShot`) — confirm club-only; no change expected.
- `golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md` — **fix this**: update the `lastShot`
  example to club-only and **remove/supersede the stale "field-test-3" prior-shot+distance text**.
- **Verify:** phone `GlassesStateMapperTests` stay green; glasses `npm run build && typecheck`;
  a diff of the contract example vs `types.ts` vs the mapper output shows no schema mismatch.

### B14 — Course Desk: tee anchors + completeness checklist (golf-caddie-coursedata)
- Add an additive **`tee: {lat, lng}` per hole** to `data/courses.json` — do NOT touch existing
  `greenAnchor` values (Emerald Isle is `greenAnchor`-only; it must still parse and keep its data).
- In the curation tool (`tools/green-marker.html` and/or `tools/curate.html`), let the user drop
  and drag a **tee anchor per hole**; keep the single middle-of-green marker as the only green point.
- Add an **18-row completeness checklist** (`par ✓ · tee ✓ · green ✓`) and gate publish on it.
- **Verify:** `data/courses.json` stays valid JSON with all existing greenAnchors intact; run any
  coursedata build/typecheck. The browser-tool UI is **not headlessly verifiable** — implement to
  spec and record "needs a visual check in the browser."

### B23 — INVESTIGATE the glasses club-scroll over-sensitivity regression
**Investigation only — a real fix needs the G2 hardware. Do NOT merge a hardware-unconfirmed fix
as "done."**
- The club lane skips past the intended club; it's a regression **since the Welk build** (suspect
  commits `1e0cc28` / `81d504b`). Bisect / diff the glasses input handling (`src/app/input.ts`,
  `src/app/screens/club.ts`) between Welk and current to find the regressing change in the scroll
  delta → step mapping / sensitivity.
- **Deliverable:** `golf-caddie-glasses/docs/B23_INVESTIGATION.md` — root cause, the exact
  commit/diff responsible, and a concrete proposed fix (e.g. a debounce / step-threshold on the
  touchpad delta). You MAY implement the proposed fix on the branch IF it builds clean, but mark it
  **NEEDS G2 CONFIRMATION** and keep B23's status as *partial* — the investigation is the deliverable.
- **Verify:** if a fix is committed, `npm run build && typecheck` pass.

### B21 — Doc + flag + dead-code hygiene
- `golf-caddie/DESIGN.md` — add a short "Current architecture" section (watch-primary detection +
  reconstruction direction + output-only glasses) or link `docs/RECONCILED_BACKLOG.md`.
- `golf-caddie-glasses/docs/ARCHITECTURE.md` — reconcile the poll cadence to the ~1.5 s value B17
  already shipped in code.
- Document the **current** meaning of `glassesInputEnabled` (do NOT assume B18's not-yet-done
  server-gating changes).
- Remove dead vestiges: `WatchHeader` `accentTime` param; the no-op
  `justConfirmed.par = currentHole.par` reassignment in `RoundController.advanceHoleFromGlasses`.
  (The `SpikeSessionReceiver` rename flagged in B20 is optional — only if it's a clean, build-safe
  rename; otherwise note it and defer.)
- **Status hygiene:** update `docs/RECONCILED_BACKLOG.md` — mark **D1 RESOLVED (club-only, no
  distance)** and the night-1 items (B2, B3, B4, B5, B8, B17, B20) as merged/done.
- **Verify:** phone target builds after the dead-code removal.

## Git discipline
- In EACH repo you touch (golf-caddie, golf-caddie-glasses, golf-caddie-coursedata), branch off
  main: `overnight/night2`. Never commit to main, never force-push.
- One commit per backlog item, message prefixed with the ID (e.g. `B16: lastShot contract = club-only`).
  An item that spans two repos gets a commit in each. Each commit self-contained and green.
- Do NOT commit `.zip` files, `.claude/`, or xcodecloud dirs.

## Verification gate (before each commit)
- Phone builds/tests use Xcode 27: prefix with
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. Phone test sim: **iPhone 17 Pro**
  (`xcodebuild test -scheme GolfCaddie -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`).
  Keep `GlassesStateMapperTests` and all existing tests green. Run `xcodegen generate` if you
  add/remove Swift files.
- Glasses: `npm run build && npm run typecheck`.
- Coursedata: validate `courses.json` parses; run any build/typecheck the repo has.
- If a check fails and you can't resolve it cleanly, do NOT commit a broken state — revert and log it.

## Stop-on-blocked rule
If an item needs hardware (G2 / Watch), a browser to verify, or balloons beyond its scope: STOP,
revert partial work so the tree is clean, log it as partial/blocked with specifics, move on.
Skipping cleanly is success; a sprawling speculative diff is failure.

## Known limits (note in the log; don't try to overcome)
- **B14** browser-tool UI and **B23** fix both need a human/hardware check — they're build-green at
  best here. B23 is *investigation-first* by design.

## Morning artifact — maintain `docs/OVERNIGHT_LOG_NIGHT2.md` as you go
Per item: status (done / partial / blocked + why), what changed (files + 1–2 lines), checks run +
result, anything needing my decision or a hardware/browser check. End with a one-paragraph summary:
what's ready to review per repo, and follow-ups.

Begin by reading `docs/RECONCILED_BACKLOG.md`, then start on B16.
