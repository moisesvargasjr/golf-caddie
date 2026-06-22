# Handoff: Frictionless Round — Cross-Device UX

## Overview
This package specifies a UX overhaul for the GolfCaddie ecosystem (iPhone app,
Apple Watch app, Even Realities G2 glasses app, and the course-data web tool).
The goal is a **frictionless round** comparable to 18Birdies (yardage + score)
and Arccos (automatic shot data), without Arccos's club sensors.

The single most important change: **stop requiring the golfer to mark each stroke
at the spot it was hit.** Replace on-the-spot marking with **end-of-hole
reconstruction** driven by the continuously-recorded GPS track. Everything else
in this document supports that shift.

This handoff covers four surfaces and the data contract between them. Implement
in priority order (see *Priority* at the end) — Section 1 (reconstruction) is the
spine; the rest can follow.

---

## About the Design Files
The file in this bundle — `Golf Caddie UX Review.dc.html` — is a **design
reference created in HTML**. It is a review document with annotated mockups
("before/after" device frames), *not* production code to copy.

Your task is to **recreate the intended layouts and behaviors in the existing
codebases**, using their established patterns:

- **iPhone app** — SwiftUI (`GolfCaddie/`). Reuse `Design/Palette.swift`,
  `Typography.swift`, `Theme.swift`, and the existing `Design/Atoms`.
- **Apple Watch app** — SwiftUI (`GolfCaddieWatch/`). Reuse `WatchTheme.swift`.
- **G2 glasses app** — TypeScript text-renderer (`golf-caddie-glasses/src/app/`).
  All rendering goes through `display.ts`; screens are pure
  `state → string` functions in `src/app/screens/`. Sizing is pixel-accurate via
  the `@evenrealities` SDK helpers in `format.ts`.
- **Course-data tool** — static web (`golf-caddie-coursedata/tools/curate.html`,
  data in `data/courses.json`).

Do **not** ship the HTML. The HTML's hex values and fonts mirror the Logbook
aesthetic but the source of truth for tokens is each app's existing theme file.

## Fidelity
**High-fidelity intent, illustrative pixels.** The *hierarchy, layout, copy,
behavior, and interaction model* are the specification and should be matched
closely. The exact pixel measurements in the HTML are a reference for proportion
and emphasis — pull final color/type/spacing values from the app's existing
design tokens (`Palette.swift`, `WatchTheme.swift`, `format.ts`), not from the
HTML literals.

---

## The Hero Feature — End-of-Hole Reconstruction

> This is the crux. Read this section as acceptance criteria.

### Problem
Today, club-distance data depends on the golfer opening the phone, standing on
the exact spot of each shot, and tapping *Log Shot*. People forget, so the data
is unreliable and the club-distance feature is effectively dead.

### Model
The phone already records a **continuous GPS track** for the hole. Treat that
track as the source of truth and make shot marking **retroactive and optional**.
There are two input paths that converge on the same confirmation:

**Path A — With Apple Watch (auto):**
1. The watch's swing detection timestamps each impact (phone stays in pocket).
2. On hole-out, each detected swing is matched to the nearest **track stop**
   (a dwell point in the GPS polyline) → that becomes the shot location.
3. The phone shows a confirmation card: *"We tracked N shots."* The golfer
   confirms, drags any pin that's off, or ignores it (defaults are kept).

**Path B — Phone-only (score-driven):** *(must work with no watch)*
1. The golfer plays the hole; the phone records the track passively.
2. On hole-out, the golfer enters their **score** (the same number they'd enter
   for the scorecard). This is the only required interaction.
3. That count seeds reconstruction: **N strokes → N pins** distributed across the
   track's stops, bounded by the tee and green anchors.
4. The pins stay **collapsed by default** behind a single disclosure row
   (`▸ N shots on your track · M putts — Review`). A score-only round never
   expands it. Expanding reveals the pins for club assignment.

### Acceptance criteria / decisions to make
- **Stop detection:** define a "stop" as a dwell of ≥ T seconds within R meters
  (suggest starting T≈8s, R≈5m; tune in field test). Stops are candidate shot
  locations.
- **Pin count reconciliation:**
  - Path A: pins = detected swings; if track-stop count disagrees, prefer the
    swing count and flag low-confidence pins in amber.
  - Path B: pins = entered score; snap to the N most prominent stops; if stops <
    N, place remaining pins by interpolation along the track and flag amber.
- **Putt split:** strokes whose stop falls **inside the green polygon** are
  classified as putts (no club, no full-shot distance). Propose the split from
  GPS; let the user adjust ±1 putt. (Green polygon / anchor comes from course
  data — see *Data Contract*.)
- **Club distance:** distance between two consecutive confirmed (non-putt) pins
  is attributed to the club on the earlier pin. Feeds per-club rolling averages.
- **Graceful degradation:** if the golfer never confirms/expands, the round still
  has a correct score and yardages. Shot/club data simply stays unconfirmed —
  never lost, never blocking.
- **Editing:** pins are draggable; long-press deletes; tapping empty map adds a
  pin; tapping a pin assigns/changes its club. Available during the round and
  later from Review.

### Where this lands in code (iPhone)
- `Views/ActiveRoundView.swift` / `ActiveRoundMap.swift` — host the track
  polyline, the pins, the end-of-hole card, and the collapsed disclosure.
- Round/shot model — add: per-hole GPS track (polyline), `Shot` with
  `location`, `club?`, `isPutt`, `confidence`; derive club distances from
  confirmed shots.
- Replace the primary *Log Shot* action with passive recording + a secondary
  *Mark here* precision tool (see *iPhone On-Course*).

---

## Screens / Views

### 1. iPhone — On-Course (Active Round)
**Purpose:** glance at yardage to the green; everything else recedes.
**File:** `Views/ActiveRoundView.swift`, `Views/ActiveRoundMap.swift`

**Layout (top → bottom):**
- **Solid ink top bar** (not translucent) — `HOLE n · PAR p` left, running score
  (`+2`) right. Solid background restores contrast over the satellite map in
  sunlight.
- **Map** fills the body (satellite under the Logbook chrome).
- **Hero yardage**, centered, very large (the dominant element on screen):
  caption `TO GREEN`, then the number (single distance to the **middle** of the
  green — see *Data Contract*; no front/back). Below it, a small **armed-club
  chip** (`▸ 8-iron`).
- **Passive recording pill** near the bottom: amber dot + `RECORDING YOUR WALK`.
  Reassures the golfer the track is being captured — no action required.
- **Bottom action row** (thumb zone): `Scorecard` (primary) and `Mark here`
  (secondary/outline). *Mark here* is an optional precision tool, **not** the
  primary path.

**Behavior:**
- **Auto-advance holes:** when the track crosses into the next tee box, advance
  automatically and show a quiet `Hole n+1 — not you? tap to fix.`
- **Always-there Undo:** a persistent, no-confirm "Undo last" reachable by thumb.
- All primary actions live in the bottom third (one-handed use, club in the
  other hand).

**Keep:** the Logbook aesthetic — Georgia serif, crimson flag, paper cards. The
problem was hierarchy, not style.

---

### 2. iPhone — End-of-Hole Reconstruction Card
**Purpose:** settle the hole in one interaction. *(See Hero Feature above.)*
**File:** `Views/ActiveRoundView.swift` (overlay/sheet on hole-out)

**Path A card (watch present):** label `HOLE n · RECORDED`, heading
*"We tracked N shots."*, a list of shots (`1 · Driver — 241y`, `2 · 8-iron —
148y`, `3 · Wedge · tap to set club — 32y`, `4 · Putt — —`), buttons
`Edit pins` (secondary) / `Looks right →` (primary).

**Path B card (phone-only):** label `HOLE n · HOW MANY STROKES?`, a large
**score stepper** (`–  5  +`, Georgia numeral, `STROKES` caption), a **collapsed
disclosure row** (`▸ 5 shots on your track · 2 putts` … `REVIEW`), and a
full-width primary `Save score →`. Map shows **only the walk** (dotted track +
tee/green dots) until Review is expanded.

---

### 3. iPhone — Home (masthead)
**Purpose:** resume in one tap; surface recent rounds + reconstruction review.
**File:** `Views/HomeView.swift`

- Keep the "Fairway Logbook" masthead (double-rule, Georgia italic).
- If a round is live, lead with a single **amber Resume** card (`In progress ·
  Hole n` → `Resume round →`).
- **Recent rounds** list (course name italic, score mono).
- `＋ Start new round` at the bottom.

---

### 4. iPhone — Scorecard
**Purpose:** fast score entry; doubles as the reconstruction "inbox".
**File:** new or existing scorecard view; ties to round model.

- Logbook scorecard grid: columns `H · Par · Score · Putts`, double-rule header,
  active hole row highlighted (amber border, cream fill).
- **Big stepper** for the active hole's score (`–  6  +`, 54px circular targets,
  Georgia numeral). Two-tap entry, large hit targets. Putts optional.
- **Reconstruction inbox:** any hole the app is unsure about gets a small amber
  dot on its row; tapping it opens the reconstruction card (Screen 2) to fix
  pins after the round.

---

### 5. Apple Watch — Glances + Input
**Purpose:** the primary input device; make a missed tap cost nothing.
**File:** `GolfCaddieWatch/WatchRootView.swift`, `WatchTheme.swift`

Four states (OLED black, warm Logbook ink, amber accent, Georgia serif):

- **Yardage + Armed Club:** caption `Hn · to green`, big middle-distance number,
  and a persistent **armed-club chip** (`▸ 8-iron`). The chip is **predicted from
  distance-to-green** using the per-club averages the app is learning, so it's
  never blank; the crown changes it. This is the answer to "which club is
  selected?" — it's always visible, pre-filled, and never required.
- **Confirm (shot detected):** `SHOT DETECTED`, predicted club (`8-iron?`),
  `turn crown to change`, and an **auto-accept ring** (countdown). **On timeout,
  the shot is saved with the predicted club** — ignoring the card is a valid
  action. The card is for correction, not confirmation.
- **Putts (green-aware):** when GPS places the golfer inside the green, the watch
  auto-swaps to a putt counter (`–  2  +`) with a `HOLED OUT` button. Swings
  can't be felt on a putt, so the watch doesn't try — one tap per putt instead.
- **Score:** per-hole score stepper (`–  6  +`).

**Keep:** the crown-armed club selector gesture.

---

### 6. G2 Glasses — Full Heads-Up Display
**Purpose:** carry everything the golfer would otherwise look down for, so the
glasses become the **primary glance** and watch/phone are backups.
**File:** `golf-caddie-glasses/src/app/screens/hud.ts` (render), `display.ts`
(SDK bridge), `format.ts` (pixel-accurate columns). 576 × 288 monochrome,
**output-only** — no input at address.

Strict, fixed-position hierarchy (the eye learns where to look once):
- **Top frame:** `HOLE 7 · PAR 4` (left) — `STROKE 3 · +2` (right). Hairline rule
  beneath.
- **Center (hero):** the **to-green number** (large) with caption `YDS · MIDDLE`,
  a vertical divider, then a **club block**: `CLUB` / `8-iron` / `▸ SELECTED`.
- **Bottom frame:** hairline rule above, then `LAST` (left) — `S2 · 4-IRON ·
  168y` (right).

Data shown: to-green, par, current stroke, armed club, last stroke + club, score.
When the watch updates the armed club or detects a shot, the HUD follows. Keep
the existing auto hole-summary flash on hole close, then return to the HUD.
**Never** add input/scroll lanes/club picker to the glasses during a normal shot.

---

### 7. Course-Data Web Tool
**Purpose:** pre-round prep that produces the anchors reconstruction needs.
**File:** `golf-caddie-coursedata/tools/curate.html`, `data/courses.json`
**Visual restyle optional.** Two functional upgrades:

- **Mark the tee box, not just the green.** You already drop a single
  middle-of-green marker — keep that as the only green point. Add a **tee anchor
  per hole**: it's the second bookend reconstruction needs to bound each hole's
  track (green + tee is sufficient; no front/back).
- **Completeness checklist before publish:** an 18-row status grid (`par ✓ ·
  tee ✓ · green ✓`) so a half-marked course can't silently ship and leave the
  golfer with no yardage mid-round.

---

## Data Contract (cross-device)

- **One yardage number everywhere:** distance to the **middle of the green**.
  This matches the curated course data (a single middle-of-green marker per
  hole). **Do not** introduce front/back green distances — that would require
  marking three points per green by hand, which is deliberately out of scope
  until the course data supports it. The same middle number renders identically
  on phone, watch, and glasses.
- **Anchors per hole:** `tee` (to add in the curation tool) and
  `greenCenter` (existing). Optional `greenPolygon` improves putt classification
  if available; otherwise use a radius around `greenCenter`.
- **Armed club** is shared state: predicted on the watch from distance-to-green,
  editable via crown, surfaced read-only on the glasses, attached to detected/
  reconstructed shots.
- **Device roles:** iPhone = source of truth (records track, owns map/round/
  scorecard/reconstruction; fully usable alone). Watch = primary input (detect/
  confirm/club/putts). Glasses = primary glance (read-only HUD). Course tool =
  pre-round prep.

---

## Design Tokens
Pull final values from the existing theme files; these are the Logbook values the
mockups used, for reference:

**iPhone / paper (Logbook):** map to `Design/Palette.swift`
- Paper background `#E3D9BF`; card paper `#F4EDDA`; card alt `#EFE7D0`
- Ink `#1E3A29`; deep ink `#13251A`; soft ink `#5C6B54`
- Amber accent `#C07C1E` (bright `#D8941F`); rule line `#C7BB99` / `#D2C6A6`
- Alert/barn-red `#9E3B2E`; green-felt `#5E7C40`; flag crimson `#C8202A`

**Watch / glasses (OLED):** map to `WatchTheme.swift` / glasses renderer
- Black `#000` (glasses panel `#05080A`); warm ink `#F4EDDA`/`#EDE4CE`
- Amber `#D8941F`; muted green text `#7E8B72` / `#9BA890`
- Glasses monochrome mint `#D9F2DF` (hero) / `#A8D8B4` / `#8FC79E` / `#5E8A6A`

**Type:**
- Serif display/numerals: **Georgia** (italic for headings/labels)
- Mono stamp labels: a typewriter mono (mockups use **Courier Prime**), uppercase,
  letter-spacing ~1–3px — map to the app's existing mono.

**Spacing/shape:** card radius ~12–20px; pill/stepper targets ≥ 44px (watch
hit-targets and phone steppers use 50–54px circles).

---

## Priority (implement in this order)
1. **End-of-hole reconstruction** (iPhone + Watch) — kills the "forgot to mark"
   problem. *High effort, highest value.* Phone-only Path B must work first.
2. **Yardage-hero on-course screen** (iPhone) — big to-green number, solid
   chrome, thumb-zone actions, retire *Log Shot* as primary. *Medium.*
3. **Auto-accept confirm card** (Watch) — timeout saves the shot. *Low.*
4. **Tee anchors + green-aware putt entry** (Course tool + Watch). *Medium.*
5. **Full glasses HUD + auto hole-advance** (Glasses + iPhone) — polish once the
   model above is in place. *Low.*

---

## Files
- `Golf Caddie UX Review.dc.html` — the annotated design review (open in a
  browser). Figures: Fig. 1 (reconstruction, with watch), Fig. 1b (phone-only,
  score-driven, collapsed pins), Fig. 2 (on-course before/after), Fig. 3 (Home &
  scorecard), Fig. 4 (watch states), Fig. 5 (glasses HUD).
