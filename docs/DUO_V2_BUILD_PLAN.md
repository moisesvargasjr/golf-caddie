# Duo v2 build plan: one map screen, everywhere

Source of truth for the design: the "Golf Caddie — Duo v2 (after Native Oaks)" canvas
(https://claude.ai/artifact/CkajugC4bRY2ZDxZDFo7Wk). This plan turns that canvas into
the app. It covers the iPhone Duo (folded, fully open wide, fully open portrait, book
pose) and the regular iPhone (portrait, landscape).

## What the canvas decided

1. **One map screen.** The live hole, a past hole mid-round, and a finished round's
   review are the same screen in different modes. `HoleReviewSheet` (Finish Hole
   review), `HoleDetailView` (past-hole editor) and `RoundReviewView` (post-round
   list) go away.
2. **The map is the background.** No map card. The hole is framed into the space the
   controls leave free and shrinks a little when they show.
3. **Controls by device.**

   | Layout | Controls |
   |---|---|
   | Duo fully open, wide | Command panel on the right (yardage/result, shot list, + SHOT / + PENALTY, Finish hole), club list down its right edge |
   | Duo fully open, portrait | Same panel on the right, full height; nothing across the bottom |
   | Book pose | Hole on the left page, command panel on the right page |
   | Duo folded | Yardage/result card bottom-left; two stacked boxes on the right (actions on top, club list or round scores below) |
   | iPhone portrait | One bottom panel in thumb reach; clubs scroll sideways |
   | iPhone landscape | Panel on the right |

4. **Rules that apply everywhere.**
   - Controls sit at least 24 pt from every edge, more at the corners. Nothing straddles the hinge.
   - Every tap target is at least 44 pt.
   - No full-width buttons along the bottom on the open Duo.
5. **Auto-hide.** It is on for the folded Duo and iPhone portrait, after 5 s with no
   touch; tapping the map brings the controls back. It is off for the open Duo, book
   pose and iPhone landscape, which keep a manual hide button. It pauses while a
   question, a selected pin or a drag is open.
6. **Shots.**
   - Drag any pin to move it, on the live hole or a past one, and it snaps to the walking path within 8 m. A dragged pin counts as placed by hand, so the trail re-placement never overwrites it.
   - Hold the map to add a shot, numbered by its position along the hole.
   - Tap a shot, then a club, to change the club.
   - **+ MISSED** goes away (holding the map replaces it). **+ SHOT** stays, but small.
7. **Finishing a hole.**
   - Tracking: Finish hole asks only for putts (0–4+), the same as the watch. PUTT +1 goes away.
   - Casual: Finish hole opens a 1–10+ score grid plus a putts row, in the same panel or sheet.
8. **Penalty.**
   - **+ PENALTY** asks what happened: OB or lost (stroke and distance), water, unplayable, wrong ball (+2), or other.
   - On the open Duo, book pose and iPhone the button is in the panel. Elsewhere it is in ···.
9. **Late start.** Holes before the starting hole show "not tracked" with a strokes/putts entry, and the scorecard shows ADD.
10. **Map rotation.** Pinch-rotate, plus a compass button that resets to hole-up.
11. **Scorecards.**
    - The traditional double-ruled card on the fully open Duo, for the live round and for finished rounds.
    - Front over back on open portrait.
    - Front/back tabs on folded and iPhone portrait.
    - A front-over-back paper card on iPhone landscape.
12. **After the round.**
    - **Path:** Logbook → the round's card → tap a hole → the same map screen in review mode.
    - **Review mode:**
      - the result card instead of yardage;
      - **Next hole ›** instead of Finish hole;
      - no + SHOT, watch status or auto-hide.
    - **Round actions:** share, resume, course and delete live in ···.
    - **The card's MAP button:** opens a satellite view of the whole course with every hole's shots. Tapping a hole glides the camera in, and that same map becomes the hole's review. **COURSE MAP** glides back out.
13. **Home.**
    - Open Duo: the bag (tap it to change the clubs in play) and Start a round on the left page; the title, last entry and logbook on the right page, mirroring the folded screen.
    - Track shots or casual is chosen at Begin, along with the course and the starting hole.

## Architecture changes

### A. One map component: `HoleMap`
Merge `ActiveRoundMap` (live, follows the user) and `EditableHoleMap` (draggable, fixed
camera) into one `UIViewRepresentable` over the single `MKMapView` that
`AdaptiveRoundLayout` already moves between layouts.
- **Modes:** `.live` (follows the user, shows "you" and the aim line), `.hole` (fixed framing) and `.course` (all holes).
- **Draggable pins:** reuse `EditableHoleMap`'s drag code. On drop, call `ShotPlacement.pinned` (8 m snap, watch points first) so the pin is saved as `.manual`.
- **Long-press:** reports the coordinate up; it is not saved inside the map.
- **Framing:** rotation is enabled. `fitHole(unobstructedInsets:)` frames tee and green into the area the layout reports as free of controls. The insets animate when auto-hide toggles.
- **Course mode:** one polyline per hole plus hole badges. Selecting a hole animates `MKMapCamera` to that hole's bounding region; the screen then switches to `.hole` for review.

### B. One editor for every hole: `HoleSession`
An `@Observable` view model for "the hole on screen", whether live, past in this round,
or in a finished round. It replaces the private state and repository writes inside
`HoleDetailView` and `HoleReviewSheet`.
- **Reads:** shots, penalties, putts, par, score, whether the hole was tracked, and the trail.
- **Writes:**
  - `moveShot`, `setClub`, `insertShot(at:)`, `deleteShot`;
  - `addPenalty(type)`, `removePenalty`;
  - `setPutts`, `setHandScore(strokes:putts:)` for holes that weren't tracked.
- **Routing:** live-hole writes go through `RoundController` (`updateShotClub`, `removeShot`, `insertMissingShot` generalised, `addPenaltyToCurrentHole`). Past-hole writes go through the repositories, then `refreshCurrentHoleShots`.
- **Re-placement:** while the hole is open it is in `HolesUnderEdit`, so the trail re-placement skips it. That rule already exists.

### C. One screen: `RoundMapScreen`
Replaces the body of `ActiveRoundView` and the review screens.
- **Inputs:** `mode` (`.tracking`, `.casual`, `.review`), `HoleSession`, `DisplayContext`, and `AutoHidePolicy`.
- **Layouts:** one struct per layout, reusing the role-tagged children pattern from `ExpandedRoundLayouts`. The panel pieces are shared components, so each layout only arranges them:
  - `ResultOrYardageCard`, `ShotList`, `ClubList` (vertical and horizontal), `ActionRow`;
  - `PuttsQuestion`, `PenaltyQuestion`, `ScoreGrid`, `RoundScoresList`.

### D. Data changes (one migration)
- **`v10_hole_score_source`:** `hole.scoreSource` (`tracked` | `hand`), plus `hole.handStrokes` and `hole.handPutts`, all nullable. This makes late-start and casual-entered holes explicit instead of storing placeholder strokes. `docs/WATCH_OWNS_ROUND.md` also wants v10, so renumber whichever ships second.
- **`PenaltyType`:** add `.wrongBall` (2 strokes) and keep `.obOrLost`. If a stroke count isn't stored per penalty yet, add `Penalty.strokes` with a default of 1.
- **Starting hole:** `startRound(startingHole:mode:)` takes the mode, which replaces the casual default in Settings. Holes before the starting hole get rows only when the user adds a score, so there are no empty rows.

### E. Deletions once the replacements are in
- **Screens:** `HoleReviewSheet`, `HoleDetailView`, `RoundReviewView`.
- **Sheets:** `HolePinMapSheet`, `MissingShotPinSheet` (holding the map replaces it), `PenaltySheet` (the inline question replaces it).
- **Moved:** the round-level sections (course link, resume, delete, share) go into a `RoundActionsMenu`.
- **Kept:** `PhysicalScorecardView` grows into the traditional card for both live and finished rounds.

## PRs, in order

Each PR has tests first (TDD) and goes through the Duo simulator check described under "How each PR is checked" below. Tracks marked ∥ can run at the same time in separate worktrees.

| # | PR | Depends on | Contents |
|---|---|---|---|
| 1 ∥ | **Layout foundations** | — | `SafeChrome` insets (24 pt, corners, hinge exclusion) used by every layout; `AutoHideController` (5 s timer, pause reasons, policy per `DisplayContext`); a DEBUG-only runtime posture switch (fold, unfold or book while the app runs, triggered from a test or a launch argument plus a timer) so tests can fold mid-hole without the Simulator's own controls; unit tests for the policy table and timer, and a UI test that round state survives switching postures mid-hole. |
| 2 ∥ | **Data + `HoleSession`** | — | v10 migration, `PenaltyType.wrongBall` + strokes, `setHandScore`, generalised insert-at-coordinate, `HoleSession` with live/past routing; tests for ordering of inserted shots, hand scores in totals, penalty strokes, `HolesUnderEdit`. |
| 3 | **`HoleMap`** | 1 | Merged map: drag + snap, long-press, rotation + compass reset, unobstructed-rect framing, `.course` mode; tests for framing math and snap. |
| 4 ∥ | **Tracking screen, all layouts** | 2, 3 | `RoundMapScreen(.tracking)` for open wide, open portrait, book, folded (stacked boxes), iPhone portrait (bottom panel), iPhone landscape; putts-only Finish; penalty question; ‹ › to past holes with full editing; late-start entry. Removes PUTT +1, + MISSED, `HoleReviewSheet`, `MissingShotPinSheet`, `PenaltySheet`. |
| 5 ∥ | **Casual screen, all layouts** | 2, 3 | `RoundMapScreen(.casual)`: round-so-far list / chips / squares, Finish → score grid; auto-hide per policy. |
| 6 ∥ | **Scorecards** | 2 | Traditional card (open wide, live + finished, ADD for untracked, tap a hole number), open-portrait split, folded and iPhone tabs, iPhone landscape card. |
| 7 | **Review = same screen** | 4, 6 | `RoundMapScreen(.review)`; Logbook → card → hole; `RoundActionsMenu`; deletes `HoleDetailView`, `RoundReviewView`, `HolePinMapSheet`. |
| 8 | **Course map** | 3, 7 | MAP on the card; `.course` mode with every hole's shots; tap a hole → camera glide → review on the same map; COURSE MAP back; Next hole glides along. |
| 9 ∥ | **Home** | 1 | Open Duo (bag + Start on the left, logbook on the right), folded, iPhone; Track / Casual at Begin; Course row; bag sheet over `ClubsInPlaySheet`. |

Merge order: 1 and 2 → 3 → 4, 5 and 6 together → 7 → 8, with 9 at any point after 1.
Each merge needs your OK, as before. The Xcode Cloud "Dev Build (Just Me)" workflow
builds every pushed branch, so each PR can go onto your phone through TestFlight before
it merges.

## How each PR is checked
- **Tests:** `xcodebuild test` passes on the iPhone Duo 27.1 simulator and on an iPhone 17 Pro simulator. The test suite currently has 350 tests, and every PR adds tests for its own logic.
- **Screenshots:** the iPhone Duo simulator in every pose (folded, open wide, open portrait, book), using the `-DebugLayoutClass` / `-DebugPosture` flags, plus the iPhone in portrait and landscape. Each screenshot is compared with its canvas mockup.
- **State across poses:** fold and unfold mid-hole and confirm the hole, selection and any open question survive.
- **Accessibility:** VoiceOver labels on pins, badges and score cells.
- **On the course:** a round that exercises dragging on the live hole, a late start, penalty types, casual mode, and the course-map flow afterwards.

### Simulator notes
- Recreate the simulators first (see "How to resume").
- **Folding:** `simctl` has no command to fold or unfold, or to set the hinge angle (checked on Xcode 27.1). Unattended runs use the debug flags and PR 1's runtime posture switch. A real fold in the Simulator app, or on the phone, is a manual spot check, done once for each PR that changes a layout.
- **Unattended runs:**
  - Never merge and never use computer use. Stack each PR's branch on the branches it depends on.
  - Delete each worktree's build cache once its PR is open.
  - When unsure, decide and write the assumption into the PR.
- **Drive the screens with the DEBUG launch flags.** These skip setup and force a layout, so a screenshot run doesn't depend on fold state:
  - `-DebugLayoutClass` and `-DebugPosture` force the layout and pose; book pose has no real hinge angle in the simulator.
  - `-DebugOpen <screen>` opens a screen directly. Extend it for each new screen: `-DebugOpen review`, `course`, `casual`, `card`, `home`.
- **Fake movement.** Play a walking route with `xcrun simctl location <udid> start …` (or a GPX file), so the live hole, the aim line and holding the map can be exercised.
- **Watch input.** The watch can't be paired in the simulator. Feed recorded shots and trail data through the existing test fixtures and DebugHarness rather than a live watch.
- **Known quirk.** A fresh install opens on Bag Setup first, so seed the bag in the harness or pass the debug flag that skips setup.
- **TestFlight only.** The watch stream, trail delivery, battery and readability in sunlight can only be checked on a real phone, through TestFlight, on the course.

## Not designed yet (needs a mockup before or during the build)
- **iPhone screens:** the iPhone Home and the iPhone course map.
- **Open portrait screens:** Home and review on the fully open Duo held in portrait.
- **Book pose screens:** casual and review in book pose.
- **Folded course map:** the course map on the folded Duo.
- **Rounds without a matched course:** the course map has no tee/green anchors, so it can only draw the shots, not the holes.

## Decisions (approved 2026-10-24)
1. **OB and lost ball stay one penalty type** (`.obOrLost`, stroke and distance). Add `.wrongBall` (+2).
2. **Holes before the starting hole count toward the round total only once the user enters their scores.** Until then the scorecard shows them as ADD and leaves them out of the totals.
3. **Show a one-time tip** the first time a round uses holding the map to add a shot.

## How to resume in a new session
- Read this file, then open the canvas link at the top. Every mockup there can be clicked through with Play.
- Start with PRs 1 and 2 in parallel worktrees. Every merge needs the user's explicit OK, and so does each set of PRs.
- The iPhone Duo simulator needs the 27.1 runtime. All simulators were deleted on 2026-10-23, so recreate one with `xcrun simctl create "iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1`, and create an iPhone 17 Pro simulator the same way.
