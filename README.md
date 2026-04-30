# GolfCaddie

Personal golf shot tracker for iPhone. Continuous GPS tracking + one-tap
shot marking + per-hole review for missing data. Built to eventually
replace 18Birdies for personal use.

## Status

Phase 1 in progress: continuous tracking + Mark Shot + club grid + hole
review. iPhone-only, no Watch yet, no satellite map yet. See `DESIGN.md`
for the full plan.

## Architecture

iPhone app with:
- Continuous background location during active rounds
- Big "Mark Shot" button as primary capture
- Club grid for quick currentClub selection (no dropdowns)
- Per-hole review sheet to fix missing club data while walking to next tee
- Action button binding via custom URL scheme

## Build

Sideloaded via free Apple Developer tier. Personal use only.

## Documents

- `DESIGN.md` — architecture, data model, UI layout, day-by-day plan
- `CLAUDE_CODE_KICKOFF.md` — first prompt for Claude Code
