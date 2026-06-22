# GolfCaddie — Phase 1 Design

## What This Is

A personal iPhone app for tracking golf shots. The on-course experience is
deliberately minimal: continuous GPS in the background, one big "Mark Shot"
button, a grid of your clubs to set what you're hitting next. Between holes,
a quick review confirms the data. After the round, a full review with map
and stats.

Built for personal use, sideloaded via the free Apple Developer tier.
No App Store submission. iPhone 16 Pro Max is the target device (Action
button support, dual-frequency GPS).

## Current architecture (2026)

> The "Phase 1 … Phase 6" framing below is the original 2025 plan and is now
> **historical** — the app moved well past it (the watch and glasses, listed as
> far-future phases, both ship today). The single source of truth for current
> direction and the live backlog is **`docs/RECONCILED_BACKLOG.md`**; this
> section is the short orientation.

Three devices, clear roles (see `docs/RECONCILED_BACKLOG.md` §4):

- **iPhone — source of truth.** Records the continuous GPS track, owns the
  round/map/scorecard, and runs hole-out **reconstruction** (the spine: the
  hole is settled once, at hole-out, from the track + swing timestamps + the
  entered score, so forgetting to mark can't cost the data).
- **Apple Watch — primary input.** On-wrist swing **detection** is the primary
  detection path (auto-log + undo); manual tap is a backstop. Detection now
  *feeds reconstruction* rather than being the final word.
- **Even Realities G2 glasses — primary glance.** A read-only **output-only**
  HUD on the live path; the gesture-input lane stays as a gated "watch died"
  lifeboat (`glassesInputEnabled`), not deleted.

Everything must still work **phone-only** (four configs are first-class:
phone-only, phone+watch, phone+glasses-no-watch, all three). One yardage number
everywhere: distance to the **middle** of the green.

## What This Is Not (Yet)

Out of scope for Phase 1, deferred to later phases:

- Satellite map / course imagery (Phase 2)
- Pin location marking + trilateration (Phase 3)
- Voice notes per shot (Phase 4)
- Distance/score statistics, trend graphs, AI analysis (Phase 5)
- Apple Watch companion (Phase 6)

The point of Phase 1: capture clean, reliable shot data. Everything else
sits on top of that data layer once it exists.

## Goals

By end of Phase 1, Moises can:

1. Open the app at the first tee, hit "Start Round"
2. Tap a club in the grid, walk to ball, tap "Mark Shot"
3. Repeat for the whole hole
4. Hit "Next Hole" → quickly fix any missing club selections, see the score
5. Continue through 18 holes
6. Hit "End Round" → review the full round on a map, edit anything
7. Trust the data enough to start replacing 18Birdies for shot-distance tracking

## Core Concepts

### Continuous tracking is always on during a round

When a round is active, the app holds an `.authorizedAlways` location
permission and runs CoreLocation continuously in the background with
`allowsBackgroundLocationUpdates = true`. The phone records GPS samples
into a per-round trace at moderate accuracy (~10-15m, low battery cost).
On `MARK SHOT`, accuracy temporarily ramps to best (~1-3m on 16 Pro Max)
to capture a high-quality fix for that specific moment.

This dual-mode approach: trace is continuous and cheap; shot markers are
precise and on-demand.

### Marking a shot ≠ selecting a club

Two separate UI affordances:

- **Club grid (small buttons)**: sets `currentClub` state. Does NOT log
  anything. You change clubs as you walk to the ball.
- **MARK SHOT button (large)**: captures GPS + timestamp + currentClub.
  This is the only action that creates a Shot record.

This separation prevents accidental shots from being marked when the user
is just thinking ahead about club selection.

### Per-hole review catches missing data

Between holes, when the user taps "Next Hole," a sheet shows the shots
from the just-completed hole. Any shot without a club gets a quick picker.
The score is displayed (shots + penalties). User taps Confirm and walks to
the next tee.

This is the single most important UX decision in Phase 1: it moves the
"I forgot to set the club" problem from "lost data forever" to "30 seconds
of fixup while walking."

### Action button as primary mark trigger

The iPhone 16 Pro Max Action button is bound (via a user-installed Shortcut)
to call a URL scheme that triggers a Mark Shot in the app. Single-press,
physical, doesn't require unlocking. Marks with `currentClub = null` (the
Action button can't know what club is selected without app foreground
state). Missing club is fixed in the hole review.

The on-screen button still works identically and can be used when the
phone is out.

## Data Model

```
Round
  id: UUID
  startedAt: Date
  endedAt: Date?
  courseName: String?           -- manual, optional
  notes: String?

Hole
  id: UUID
  roundID: UUID
  holeNumber: Int
  par: Int?                     -- manual entry, optional
  confirmedAt: Date?            -- set when user taps Confirm in review
  -- score is computed: shots.count + penalties.totalStrokes

Shot
  id: UUID
  holeID: UUID
  sequenceNumber: Int           -- order within hole
  timestamp: Date
  latitude: Double?             -- nil if added retroactively
  longitude: Double?
  gpsAccuracy: Double?          -- horizontalAccuracy in meters
  hadGPS: Bool                  -- false for retroactively added shots
  club: ClubID?                 -- nullable; filled in hole review
  source: ShotSource            -- .button | .actionButton | .manual
  notes: String?                -- post-round text notes (Phase 1 keeps simple)

Penalty
  id: UUID
  holeID: UUID
  type: PenaltyType             -- .obOrLost | .water | .unplayable | .other
  strokeCount: Int              -- usually 1, sometimes 2 for OB
  timestamp: Date
  notes: String?

TracePoint
  id: UUID
  roundID: UUID
  timestamp: Date
  latitude: Double
  longitude: Double
  accuracy: Double
  -- continuous samples; can be downsampled or dropped after round if needed

ClubConfiguration              -- singleton per user
  bag: [ClubID]                 -- ordered list of clubs the user carries
  -- ClubID enum: .driver, .threeWood, .fiveWood, .threeHybrid,
  --             .fourHybrid, .fiveHybrid, .threeIron ... .pitchingWedge,
  --             .gapWedge, .sandWedge, .lobWedge, .putter
```

Score per hole computed on read: `shots.count + penalties.sum(strokeCount)`.

## File Structure

```
GolfCaddie/
├── GolfCaddie.xcodeproj
├── DESIGN.md                          -- this file
├── README.md
└── GolfCaddie/                        -- iPhone app target
    ├── GolfCaddieApp.swift
    ├── Info.plist
    ├── Models/
    │   ├── Round.swift
    │   ├── Hole.swift
    │   ├── Shot.swift
    │   ├── Penalty.swift
    │   ├── TracePoint.swift
    │   ├── Club.swift                  -- ClubID enum + display names
    │   └── ClubConfiguration.swift
    ├── Persistence/
    │   ├── Database.swift              -- GRDB setup, migrations
    │   └── Repositories.swift          -- query helpers
    ├── Capture/
    │   ├── LocationManager.swift       -- continuous + on-demand precise
    │   ├── RoundController.swift       -- orchestrates active round state
    │   └── URLSchemeHandler.swift      -- handles Action button trigger
    ├── Views/
    │   ├── RootView.swift              -- routes to setup / round / review
    │   ├── BagSetupView.swift          -- one-time club configuration
    │   ├── ActiveRoundView.swift       -- main on-course screen
    │   ├── ClubGridView.swift          -- 2-row club picker
    │   ├── MarkShotButton.swift
    │   ├── PenaltySheet.swift
    │   ├── HoleReviewSheet.swift       -- between-holes review
    │   ├── RoundListView.swift         -- post-round list
    │   ├── RoundReviewView.swift       -- full-round map + shots
    │   └── ShotEditView.swift
    └── Utils/
        ├── Distance.swift              -- Haversine, meters↔yards
        └── Haptics.swift
```

## On-Course Screen Layout

```
┌─────────────────────────────────────┐
│  Hole 4   ●                  [End]  │  ← context bar
│                                     │     (●  = GPS fix indicator)
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │     [map placeholder]       │    │  ← Phase 2 satellite;
│  │     Phase 1: simple stats   │    │     Phase 1 shows last shot
│  │     "Last: Driver, 248 yds" │    │     distance + shot count
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  Current: 7-iron                    │  ← currentClub state
│                                     │
│  ╔═════════════════════════════╗   │
│  ║                             ║   │
│  ║         MARK SHOT           ║   │  ← primary action
│  ║                             ║   │
│  ╚═════════════════════════════╝   │
│                                     │
│  ┌──┬──┬──┬──┬──┬──┬──┐           │
│  │Dr│3W│5H│4i│5i│6i│7i│           │  ← club grid (configured bag)
│  ├──┼──┼──┼──┼──┼──┼──┤           │
│  │8i│9i│PW│SW│LW│Pt│  │           │
│  └──┴──┴──┴──┴──┴──┴──┘           │
│                                     │
│  [+ Penalty]      [Next Hole →]    │
└─────────────────────────────────────┘
```

Layout principles:

- **Mark Shot is the largest tap target.** Spans full width, ~120pt tall,
  high-contrast. Bottom-thumb-reachable on 16 Pro Max.
- **Club grid uses 2 rows.** Configured bag has up to 14 clubs; 2x7 fits.
  Tap = sets currentClub. Selected club has a visible state (filled
  background, accent color).
- **Penalty and Next Hole are secondary.** Smaller buttons at the bottom,
  less prominent. Penalty opens a sheet with the four types; Next Hole
  opens the review sheet.
- **No dropdowns, no scrolling required during a shot.** Everything you
  need to tap is visible at once.
- **GPS fix indicator** in the context bar: green dot when accuracy is
  good, yellow when degraded, gray when no fix. Confidence at a glance.

## Hole Review Sheet

Triggered by "Next Hole" button. Modal sheet:

```
┌─────────────────────────────────────┐
│  Hole 4 — Review                    │
│                                     │
│  Par: [4]   ←  tap to edit          │
│                                     │
│  Shot 1   Driver         245 yds    │
│  Shot 2   7-iron         148 yds    │
│  Shot 3   SW              22 yds    │
│  Shot 4   Putter           6 yds    │
│  Shot 5   ●●● tap to set club       │  ← missing club; required to confirm
│                                     │
│  Penalties: 0    [+ Add Penalty]    │
│                                     │
│  Score: 5  (Bogey)                  │
│                                     │
│  [+ Add Missing Shot]               │
│                                     │
│  [Cancel]              [Confirm]    │
└─────────────────────────────────────┘
```

Behavior:

- Shots without a club show "tap to set club" — Confirm is disabled until
  all shots have clubs (or the user explicitly leaves them blank, with a
  warning).
- "Add Missing Shot" inserts a shot with `hadGPS = false`, no coordinates,
  user picks club + position in sequence. Used when a tap was missed.
- "Add Penalty" opens the penalty type picker.
- Score updates live as edits are made.
- Confirm sets `confirmedAt` on the Hole, increments hole counter, returns
  to active round screen on Hole + 1.

## End of Round Flow

When user taps "End Round":

1. If on a hole with unconfirmed data, prompt: "Review hole N first?" → yes
   shows the hole review sheet, no proceeds.
2. Set `Round.endedAt`.
3. Navigate to RoundReviewView.

## Round Review View

Full-round summary, mostly read-only with edit affordances:

- Round name (editable, default = course name + date)
- Hole-by-hole scorecard with par + score
- Total score
- A simple list of all shots (Phase 1; map view comes in Phase 2)
- Per-shot details on tap → `ShotEditView` (change club, add notes,
  delete shot)

## Background Location Configuration

Critical iOS bits to get right:

**Info.plist keys:**
- `NSLocationWhenInUseUsageDescription`: "GolfCaddie tracks your shot
  locations during a round."
- `NSLocationAlwaysAndWhenInUseUsageDescription`: "GolfCaddie keeps
  tracking your round in the background while your phone is in your
  pocket."

**Capabilities:**
- Background Modes → Location updates

**LocationManager behavior:**
- Request `.authorizedAlways` when user starts their first round.
- During an active round:
  - `desiredAccuracy = kCLLocationAccuracyHundredMeters` baseline
  - `distanceFilter = 10` (meters between trace samples)
  - `allowsBackgroundLocationUpdates = true`
  - `pausesLocationUpdatesAutomatically = false`
- On `markShot()`:
  - Bump `desiredAccuracy = kCLLocationAccuracyBest`
  - Wait up to 2s for accuracy ≤ 5m, otherwise capture best available
  - Restore baseline after capture

**Battery target:** ≤ 25% drain on a 4-hour round on 16 Pro Max with this
profile. Validated in Day 7 field test.

## Action Button Integration

The Action button cannot directly invoke an app. The pattern is:

1. User creates a Shortcut: "Mark Golf Shot" → URL: `golfcaddie://mark`
2. User binds Action button → Run Shortcut → Mark Golf Shot
3. App registers `golfcaddie` URL scheme in Info.plist
4. App handles `URL(string: "golfcaddie://mark")` in `URLSchemeHandler`
5. Handler calls `RoundController.markShotFromActionButton()`

If no round is active when the URL fires, the app shows a brief alert
and ignores the trigger. If round is active, mark proceeds with
`source = .actionButton, club = nil` per the agreed behavior.

## Edge Cases & Failure Modes

- **No GPS fix at mark time**: store the shot with `latitude = nil`,
  show a warning haptic. User can manually edit position later (or just
  accept that this shot has no distance data).
- **App killed mid-round**: restore round on next launch from SQLite.
  Active round is whichever round has `endedAt = nil`.
- **Phone reboots**: same as above. Background location resumes when
  app is relaunched. Some trace points lost between reboot and relaunch.
- **Permission denied for background location**: explain the impact,
  prompt user to grant; round can still work in foreground only.
- **Mark Shot tapped with no club selected**: shot is recorded with
  `club = nil`, hole review will require fix. Haptic confirms capture.
- **Two Mark Shots within 2 seconds**: ignore the second (likely a
  double-tap). Threshold configurable.
- **Storage corruption / migration failure**: GRDB has good migration
  story; design migrations to be reversible where possible.

## Day-by-Day Build Plan

**Day 1 — Project skeleton**
- Xcode project, iPhone-only target, free tier signing
- GRDB via Swift Package Manager
- Database.swift with empty migrations registered
- RootView placeholder
- Info.plist with location permission strings
- Background Modes capability

Deliverable: app launches, requests location permission, prints "round
not started" on screen.

**Day 2 — Persistence + bag setup**
- Models: Round, Hole, Shot, Penalty, TracePoint, ClubConfiguration
- Migrations creating tables
- Repositories.swift with basic CRUD
- BagSetupView: toggle clubs, drag to reorder, save to ClubConfiguration

Deliverable: configure bag once, see it persist across app launches.

**Day 3 — Continuous tracking + Mark Shot button**
- LocationManager with the dual-mode logic
- RoundController: start round, mark shot, end round
- ActiveRoundView with just MARK SHOT button + GPS indicator
- Shots persist to SQLite

Deliverable: start a round, tap Mark Shot 5 times walking around the
yard, verify GPS coordinates and accuracy are reasonable.

**Day 4 — Club grid + currentClub state**
- ClubGridView reads from ClubConfiguration
- Tapping a club sets RoundController.currentClub
- Mark Shot uses currentClub if set
- Selected club has visible state in grid

Deliverable: tap club, tap Mark Shot, shot is logged with club.

**Day 5 — Holes, penalties, hole review**
- Next Hole button + Hole transitions
- HoleReviewSheet with missing-club fix, score calculation
- PenaltySheet for adding penalties
- Add Missing Shot retroactively
- "Add Penalty" flow

Deliverable: play through 3 simulated holes (walk around the block),
review each, see correct scores.

**Day 6 — Round review + Action button + polish**
- RoundReviewView: scorecard, shot list
- ShotEditView: change club, notes, delete
- URL scheme handler
- User-facing instructions for setting up the Shortcut
- Failure haptics, GPS indicator polish, double-tap protection

Deliverable: end-to-end flow works: start round, play holes, end round,
review. Action button binding documented.

**Day 7 — Field test at the range or a par-3 course**
- Sideload to real device
- Play a round
- Note actual battery drain
- Identify any UI issues only visible in real use (sun glare on screen,
  one-handed reach, sweat on screen, etc.)

Deliverable: real round logged + list of refinements.

## Open Decisions (resolved)

1. **Course name and par per hole** → manual entry, optional ✓
2. **Putter handling** → treated identically to other shots; one Mark Shot
   per putt, club = putter ✓
3. **Mark Shot with no club selected** → allow it, flag in hole review for
   fix ✓
4. **Action button mark behavior** → records with `club = nil`, gets fixed
   in hole review ✓

## Future Phases (out of scope for Phase 1)

**Phase 2 — Satellite map + on-course visualization**
- MKMapView with `.imagery` map type
- Live trace overlay
- Distance-to-marker pins
- Replaces the placeholder in the active round screen

**Phase 3 — Pin marking + trilateration**
- Long-press the screen button (or new dedicated button) to mark pin
  location when laser-confirmed
- Least-squares trilateration for unmarked pins from shot-distance calls
- Distance-to-pin live display

**Phase 4 — Voice notes**
- Hold-to-record voice memo per shot
- Post-round transcription (Whisper local on homelab via Tailscale, or
  Apple Speech on-device)
- Claude parses transcript for shot quality / conditions / notes

**Phase 5 — Stats and analysis**
- Per-club distance distributions and trend graphs
- Strokes-gained-style analysis (DIY using personal baseline, not PGA
  Tour averages)
- Export to CSV
- Claude-powered round analysis: paste history, get insights

**Phase 6 — Apple Watch companion**
- WatchConnectivity sync
- On-watch Mark Shot + club picker
- Eliminates the need to pull out the phone for most shots

## Tech Stack

- **Language/UI:** Swift, SwiftUI, MapKit (for Phase 2+)
- **Persistence:** GRDB.swift (SQLite)
- **Location:** CoreLocation, background mode
- **Distribution:** Free Apple Developer tier, sideloaded
- **Source control:** Private GitHub repo, chezmoi-managed config

Phase 4+ adds: Tailscale to homelab, faster-whisper, Claude API,
optional FastAPI service for batch processing.
