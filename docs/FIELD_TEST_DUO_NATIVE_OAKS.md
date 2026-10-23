# Field Test — iPhone Duo + watch-first GPS · Native Oaks (2026-10-23)

The first round on the iPhone Duo. Two things are under test:

1. **The Duo layouts.** Does the unfolded screen beat a letterboxed golf app?
2. **The watch owns location.** With the phone left in the cart, the shots and the trail should
   still come from the watch.

Keep this open on the old phone or in Notes. Don't debug on the course; write it down.

## Builds under test

- **iOS + watch:** the latest TestFlight build from `main`, built by Xcode Cloud with Xcode 27.1.
  The build number shows in TestFlight.
- It includes:
  - clubs in play (#16)
  - move a stroke to another hole (#19)
  - Finish Hole stays on screen on the watch (#20)
  - watch GPS for watch shots (#17)
  - watch GPS first everywhere (#18)
  - the watch trail as the trail (B38), **if it merged before the build**; otherwise the map
    trail is still the phone's breadcrumbs
  - the Duo layouts and the physical scorecard (B36)

---

## A. Before you leave the house (new phone setup, ~15 min)

- [ ] Set up the Duo by transferring from the old iPhone. When asked, **move the Apple Watch pairing**
      to the Duo.
- [ ] App Store → install **TestFlight** → sign in with your tester Apple ID → install
      **GolfCaddie**. No Developer Mode is needed: TestFlight builds are distribution-signed.
- [ ] Watch app on the Duo → **Available Apps** → install GolfCaddie on the watch.
- [ ] Open GolfCaddie on the Duo once, so the course catalog syncs to the watch.
- [ ] Location = **Always**. Motion & Fitness = on. The watch app has location permission.
- [ ] **Check that round history transferred** (Logbook shows past rounds). Don't wipe the old
      phone until this is confirmed.
- [ ] **Five-minute smoke test in the yard:**
  - [ ] Start a round. Take 3 practice swings with the watch. Check that each one arrives on the
        phone and shows the WATCH source.
  - [ ] Fold and unfold the phone. Check that the round, the club and the yardage don't reset.
  - [ ] Try Finish Hole once. Then end and delete the test round.

## B. Duo layouts: check on the course

Rate each one 👍 / 👎 / note. The question to keep asking: **is this better than a letterboxed app?**

**Folded (cover screen)**
- [ ] Yardage readable at a glance, in sun, one-handed.
- [ ] Club row: nothing cut off next to the Bag cell.
- [ ] PUTT +1 and Finish hole reachable with your thumb.
- [ ] Controls (bottom bar: ↶ · + SHOT · + MISSED, then PUTT +1 · Finish hole): is the bottom bar
      OK, or would a right-edge rail be better? (The rail is deferred; this build has the bottom bar.)

**Fully open, wide (H4: panorama map + command rail)**
- [ ] The hole map reads well, turned so tee → green runs left to right, with 200/150/100 yd rings
      around the green and the dotted walked trail. If the first framing looks off, tap FOLLOW.
- [ ] The yardage card shows the source as **WATCH GPS** when the watch is on.
- [ ] Club grid + this hole's strokes are both visible without scrolling.
- [ ] Nothing important sits on the hinge.

**Fully open, portrait (command center)** — not yet seen on a live pose; check carefully
- [ ] Map, yardage, clubs, strokes, and the two-row bottom bar all fit.

**Book pose (partly closed, hinge down the middle)**
- [ ] The hole is on the left page and the command center on the right. Does it switch on its own?
- [ ] Is it useful propped up in the cart's cup holder or on the dash?

**Tabletop (half-folded, hinge across)** — not yet seen on a live pose; check carefully
- [ ] Huge yardage on top, readable from the cart seat.
- [ ] Controls below the hinge are usable.

**Fold/unfold mid-hole** (do it at least 3 times)
- [ ] Round state survives: same hole, same club, same strokes, no reset.

**Finish Hole review (unfolded)**
- [ ] The two-column layout (pin map left, review right) is easier than on the folded screen.
      It only appears when the hole has GPS-located shots.
- [ ] Dragging pins feels precise.
- [ ] No putts picker or score stepper yet: the score is the shots + penalties you see.

**Physical scorecard (unfolded, CARD)**
- [ ] All 18 holes are on one row. Score marks: circle = birdie, double circle = eagle,
      square = bogey, double square = double bogey or worse.
- [ ] PLAYER is blank (the app has no player name); DATE is filled in.
- [ ] Unplayed holes are blank and the current hole is tinted.
- [ ] Tap a hole: the story line and "Open hole" work.
- [ ] Is it the paper-card feel you wanted? What's missing (handicap row? real tee yardages?)

## C. Watch-first GPS: the cart test

Do **both** setups for at least 3 holes each, and write down which holes.

**Holes ___ : phone left in the cart (the real test)**
- [ ] Walk the hole with only the watch. Let the watch auto-detect; MARK and PUTT on the watch.
- [ ] Back at the cart, open the hole on the phone:
  - [ ] The **trail matches where you walked**, not the cart path. It may take a few seconds to
        arrive.
  - [ ] Shots sit at your swing spots, not on the cart path.
  - [ ] Finish Hole review: tap near the trail to place a missed shot. Does it snap onto the trail?
- [ ] Phone yardage: while you're away from the cart, does the phone screen show WATCH or PHONE?
      (Expect PHONE when the watch is out of Bluetooth range.)

**Holes ___ : phone in your pocket (control)**
- [ ] Yardage on the watch, the phone and the glasses (if worn) agree within about 3 yd.
- [ ] Note any hole where the phone and watch disagree noticeably (≥10 m). We log this now as
      `locationDisagreementMeters`.

**Back nine, one hole with Bluetooth OFF on the phone** (still untested)
- [ ] Watch yardage keeps updating. After Bluetooth is back on, the trail and shots arrive.

## D. Expected, not bugs (don't chase these on the course)

- **The phone yardage says PHONE GPS while you're far from the cart.** The live watch fix only
  reaches the phone in Bluetooth range. The trail and shots catch up when you're back.
- **The trail appears a few seconds or holes late.** The watch queues it and delivers when
  reconnected.
- **Only the wide (H4) map is turned tee-left/green-right.** The other layouts keep the usual
  green-up map.
- **The cover screen uses a bottom bar, not a right-edge rail.** The rail was deferred; there is no
  SwiftUI "bars are vertical" signal to gate it on yet.
- **The Home screen looks the same unfolded.** The two-column Home was cut for tonight.
- **Handicap row and real tee yardages are missing from the scorecard.** We may not have that
  course data.

## E. Real bugs (record for the debrief)

Note the hole number, time, pose (folded/wide/book/tabletop), what you did, and what happened.
Screenshot if you can (side button + volume up).

- Anything cut off, overlapping the hinge, or unreachable in any pose.
- The round resets or loses strokes on fold/unfold.
- The trail stays on the cart path after you're back at the cart for 1+ minute.
- A watch-detected or watch-marked shot is missing, doubled, or on the cart path.
- Finish Hole score doesn't match what you entered.
- Crash, freeze, or DB error banner.
- Watch battery drops faster than about 10%/hour (field test 1: 95 → 85% over 2 h).

## Post-round

- [ ] Note phone and watch battery start/end, and round duration.
- [ ] Settings → Watch GPS Log → export the session. Also export the round DB.
- [ ] Bring both back. We'll run `scripts/compare-watch-track.py`, which now reports `locationSource`
      counts and the phone/watch disagreement.
- [ ] Pick the folded control layout (rail or bottom bar) and any Duo changes for the next build.
