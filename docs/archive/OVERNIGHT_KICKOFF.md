# Overnight Agent Kickoff — Foundations Batch (night 1)

> **For the human launching this:** open a Claude Code session in `~/source/golf-caddie`,
> run `/model sonnet` then `/effort high`, allow `xcodebuild`/`xcodegen`/`npm`/`git` (or
> use an accept-all/bypass mode — safe here because the work is branched and never touches
> `main`), keep the Mac awake (`caffeinate -dimsu`), then tell the agent:
> **"Read `docs/OVERNIGHT_KICKOFF.md` and follow it exactly."**
> In the morning, review via `docs/OVERNIGHT_LOG.md` + `git log`/`git diff` on the
> `overnight/foundations-0621` branch in each repo.

---

You are implementing a curated batch of backlog items overnight, unattended. Work
autonomously and optimize for a clean, per-item-reviewable result in the morning.
Correctness and reviewability matter more than finishing everything.

## Source of truth
Read `docs/RECONCILED_BACKLOG.md` (in this repo) FIRST. It has the full spec — Why /
Change / Where (file:line) / Acceptance / Traces-to — for every item below. Skim
`docs/FIELD_TEST_4_EMERALD_ISLE.md` for field context. Implement strictly to each
item's **Change** and **Acceptance**. The file:line anchors are starting points —
confirm by reading the code.

## Scope — do ONLY these 7 items, in order
Phone/watch repo (`~/source/golf-caddie`):
  1. B2  — Transport idempotency (UUID on watch→phone commands)
  2. B3  — Honest shot provenance + model fields (watchManual, isPutt, confidence, reconstructed)
  3. B4  — Watch→phone delivery feedback ("syncing N" chip)        [needs B2 first]
  4. B5  — Per-hole track segmentation + stop/dwell detection
  5. B8  — Track as shot-location source of truth; retire the dual GPS-capture path
  6. B20 — Feature-flag the spike/validation subsystem behind #if DEBUG
Glasses repo (`~/source/golf-caddie-glasses`):
  7. B17 — Glasses polling cadence (→~1500ms) + reconnect staleness cue + battery render

Do NOT start any other item — especially B6/B7 (reconstruction), any UI redesign
(B9–B15), the FT4 bug items (B22/B23), or B16 (needs an unresolved product decision).
If you finish all 7 early, STOP and write your summary. Do not pull in more work.

## Git discipline
- In EACH repo you touch, branch off main: `overnight/foundations-0621`. Never commit
  to main, never force-push, never touch other branches.
- In golf-caddie the planning docs are untracked — make your FIRST commit on the branch:
  `git add docs/RECONCILED_BACKLOG.md docs/IMPROVEMENTS_HANDOFF.md docs/FIELD_TEST_4_EMERALD_ISLE.md docs/OVERNIGHT_KICKOFF.md docs/design_handoff_frictionless_round`
  → commit "docs: reconciled backlog + FT4 + kickoff (handoff reference)". Do NOT commit
  the .zip files, .claude/, or xcodecloud dirs.
- One commit per backlog item, message prefixed with the ID (e.g. "B2: idempotent watch
  commands"). Each commit must be self-contained and green.

## Verification gate — MANDATORY before each commit
- Discover the setup first: `xcodebuild -list` (schemes) and
  `xcrun simctl list devices available` (pick an installed iPhone + Apple Watch sim).
  This project uses xcodegen — if you add/remove Swift files, run `xcodegen generate`
  before building.
- iOS items (B2,B3,B4,B5,B8,B20): build the phone scheme AND run the test target, e.g.
  `xcodebuild test -scheme <PhoneScheme> -destination 'platform=iOS Simulator,name=<iPhone>'`.
  Also build the watch scheme for B2/B3/B4/B20. Existing tests (ShotReconcilerTests,
  GlassesStateMapperTests, TracePointRepositoryTests, ClubAveragesTests,
  LiveSwingDetectorTests) must stay green. ADD tests where Acceptance calls for them
  (B2 idempotency, B3 source/putt tagging, B5 stop detection). For B20, also build
  `-configuration Release` and confirm the spike code compiles out.
- Glasses item (B17): `npm install` if needed, then `npm run build && npm run typecheck`
  must pass.
- If build or tests fail and you can't resolve it cleanly, do NOT commit a broken state.
  Revert that item's changes and log it as blocked.

## Stop-on-blocked rule
If an item needs real hardware (Watch / G2 glasses), a field repro, or balloons beyond
its stated scope, or you're genuinely unsure of intended behavior: STOP that item,
revert partial work so the tree is clean, record it as partial/skipped with specifics in
the log, and move on. Skipping cleanly is success; a sprawling speculative diff is failure.

## Known verification limits (note in the log; don't try to overcome)
- B4 (watch delivery UI) and B17 (glasses HUD render) have runtime/visual behavior not
  fully unit-testable here. Implement to spec, get build + typecheck green, and record
  "needs on-device/sim visual check."

## Morning artifact — maintain `docs/OVERNIGHT_LOG.md` as you go
Per item: status (done / partial / skipped + why), what changed (files + 1–2 lines),
tests run + result, anything needing my decision or a hardware check. Update after each
item so it's accurate even if interrupted. End with a one-paragraph summary: what's ready
to review, in what order, and any follow-ups.

Begin by reading `docs/RECONCILED_BACKLOG.md`, then start on B2.
