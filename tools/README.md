# Duo v2 verification tools

Helpers used overnight on 2026-10-24 to build, test and screenshot the Duo v2 PRs.
They live on this orphan branch so they stay out of the app. Run them from a checkout of this branch.

- `verify.sh <worktree> <tag> [tourfile]` runs the PR serially.
  - It checks free disk (≥10 GB) and builds for testing once.
  - It tests on the "iPhone Duo" iOS 27.1 sim, and on an "iPhone 17 Pro" if a runtime supports one.
  - It then runs the screenshot tour, one clean install per tour group.
  - Results go to `$RESULTS/<tag>` (default `tools/results`).
- **Tour files** (`tours/tour-*.tsv`): each line is `group<TAB>name|portrait|launch args`.
  - `-DebugWindowSize WxH` renders a pose at that window size.
  - `-DebugLayoutClass`/`-DebugPosture` force the pose.
  - `-DebugAutoHide off` keeps the controls up.
- `publish-shots.sh <tag> [tours/map-*.tsv]` copies the shots as JPEGs into `<tag>/` on this branch and pushes. It prints the markdown table for the PR.
- `lane-wait.sh` waits until `~/.sim-lane-free` exists or the sim lane has been idle for 15 min.
- `memory-duo-v2-build-plan.md` is a snapshot of the project memory note.
