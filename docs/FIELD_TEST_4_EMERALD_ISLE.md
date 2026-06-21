# Field Test 4 — Emerald Isle (Oceanside)

**Date:** 2026-06-20
**Course:** Emerald Isle, Oceanside — par-18, shot 55
**Devices:** Glasses (output), Apple Watch Series 6 (input), Phone

> Feedback captured raw from the round. **Not yet triaged or acted on.**

---

## 🕶️ Glasses (HUD output)

1. **Sync still breaking — suspected bug.**
   The HUD sometimes freezes on a previous hole/stroke and stays stale for *several*
   strokes, then eventually re-syncs on its own. No known trigger. Made the glasses
   essentially unusable as an output-only device.
   - **Ask:** add a visual "polling is running / sync alive" indicator on the phone
     and/or glasses so it's clear when the feed is actually live.
   - **Resolved:** the freeze is on *everything* (both hole and stroke stall together),
     so it's **likely the poll loop**, not the render.

2. **Club selection now too sensitive — suspected regression.**
   Constantly skipping past the intended club. So unreliable that the workaround was to
   pick *any* club and fix it later on the phone.
   - **Resolved:** this is **new since the Welk field test** — did not happen there.
     Points at a change in the `.ehpk` build / glasses input handling since Welk
     (1e0cc28 / 81d504b) as the likely cause.

## ⌚ Watch (Series 6)

3. **Battery still a problem.** Down to 20% by ~hole 14 → had to power off.
   Consistent with the Series 6 being below the Series 9 / Ultra 2 floor.
4. **Working well:** swing tracking is good; manual putt marking worked.
5. After the watch died, fell back to the glasses as the input device.

## 📱 Phone

6. **Shot marking is slow.** Glasses and watch both mark *immediately*; the phone lags,
   leaving you standing there waiting for it to register.
7. **Edit the current hole from the map.** Want to modify club / stroke location for the
   hole you're *currently* on — not be forced to advance to the next hole before you can
   correct a previous shot.
8. **Satellite view orientation.** Always orient green-to-north, you-to-south
   (static — don't rotate with heading).
9. **Add a green marker on the map.** Currently it's just an undecorated map you have to
   decode visually.

---

## Quick triage hints (for later)

| # | Area | Type | Severity |
|---|------|------|----------|
| 1 | Glasses sync freeze | Bug | High — blocks output use |
| 2 | Glasses club over-sensitivity | Regression | High — blocks input use |
| 3 | Watch battery | Known hardware limit | Med (dev device below floor) |
| 6 | Phone shot-mark latency | Perf | Med |
| 7 | Edit current hole from map | Feature | Med |
| 8 | Static green-north orientation | Feature | Low |
| 9 | Green marker on map | Feature | Low |
