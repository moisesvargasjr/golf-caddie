---
name: duo-v2-build-plan
description: "The approved Duo v2 / iPhone UI redesign: plan doc, mockup canvas, PR order, and where to resume"
metadata:
  node_type: memory
  type: project
  originSessionId: e44df6fa-87db-4e56-b16b-80a81da8ff55
  modified: 2026-10-24T12:56:28.868Z
---

After the Native Oaks field test (2026-10-23), the user and I designed the "one map screen everywhere" redesign. The user approved the build plan and its three decisions on 2026-10-24.

- **Plan:** `docs/DUO_V2_BUILD_PLAN.md` (architecture, nine PRs, how each is checked, decisions).
- **Mockups:** the canvas at https://claude.ai/artifact/CkajugC4bRY2ZDxZDFo7Wk ("Golf Caddie — Duo v2 (after Native Oaks)"), about 27 interactive screens.
- **Start:** PRs 1 (layout foundations) and 2 (data + HoleSession) in parallel worktrees. Then 3 (HoleMap), then 4/5/6, then 7, then 8; 9 (Home) can go any time after 1.

**Status (overnight 2026-10-24):** all nine PRs built, tested on the Duo sim and opened, none merged: #28 (1), #29 (2), #31 (3, on #28), #33 (4, on #31 + #29), #34 (5, on #33), #32 (6, on #29), #35 (7, on #34 + #32), #36 (8, on #35), #30 (9, on #28). Screenshots live on the `duo-v2-screenshots` branch. Worktrees are in `../golf-caddie-wt/pr1..pr9`. A fix to a lower PR has to be merged forward into every branch stacked on it.

**Sim lessons:** the iOS 27.1 runtime only accepts the iPhone Duo, and the Duo sim only runs folded from the CLI. Screenshots use PR 1's `-DebugWindowSize WxH` plus `-DebugAutoHide off`. A hard `.shadow` needs `.compositingGroup()` first, or the text draws twice.

**Why:** The field test showed hard-to-reach corner buttons, a separate review screen the user didn't want, a map confined to a card, and no way to score holes before a late start.

**How to apply:** Build from the canvas, not from memory. Each canvas title and sticky note states the rule for that screen. If something isn't on the canvas, mock it up and get the user's OK before coding it. Merges need explicit approval per set. See [[parallel-subagents]] and [[duo-redesign-priority]].
