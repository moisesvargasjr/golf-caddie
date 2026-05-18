# Field Test Checklist — first course run

Personal field test of GolfCaddie iOS + the G2 glasses. Covers the new
course auto-detect and the two glasses UX fixes. Keep this open on your phone.

## Builds under test

- **iOS:** latest `main` (course auto-detect on round start; signing in
  `project.yml`). Installed via Xcode → device.
- **Glasses:** `golfcaddie.ehpk` **v0.1.1**, built with
  `VITE_API_BASE=http://127.0.0.1:8417`, installed as a private build via the
  Even Hub portal. (One-gesture club select + last-shot on Actions screen.)

---

## A. Dress rehearsal at home (the real gate — do this BEFORE driving out)

The point: prove the **standalone, no-Mac** path. Every prior test had the
glasses app served from the Mac mini.

- [ ] Mac dev server **off**; phone **off the Mac's network** (cellular/other
      WiFi is fine — just not the dev LAN).
- [ ] iOS app: Settings → **glasses server enabled**.
- [ ] Location permission = **Always** (not "While Using").
- [ ] Start a round on the phone.
- [ ] Glasses HUD loads — **not** stuck on "Connecting…". *(Confirms the
      packaged origin reaches `127.0.0.1:8417` — the one untested variable.)*
- [ ] **One-tap a club** on the glasses → it sets **and** returns to the HUD in
      a single gesture (old build needed a double-tap back). *Tell that the
      0.1.1 build took.*
- [ ] Glasses **Actions** screen shows `Last: <club> · <yds>` (or `Last: —`
      with nothing logged). *Second tell of 0.1.1.*
- [ ] Mark a shot **on the glasses** → it appears in the iOS app.
- [ ] Phone fully charged before leaving.

**If the HUD won't leave "Connecting…":** the packaged build isn't reaching the
loopback. Don't debug on the course. Fastest fallback for that day = the dev-QR
path (needs a laptop + hotspot on-site); otherwise abort the glasses portion and
field-test the phone alone.

---

## B. Course day — setup at the first tee

- [ ] Phone charged; battery pack in the bag (continuous GPS + the loopback
      server is the real drain).
- [ ] Glasses charged.
- [ ] Location = **Always**; glasses server enabled.
- [ ] **Bring the phone and keep it on you.** The glasses are a phone-tethered
      display — no phone, no glasses. This is the architecture, not a bug.
- [ ] Stand on/near the first tee with a clear sky view, then **Start Round**.
- [ ] Within a few seconds, the course name should auto-fill (top bar, round
      list). If wrong/blank, tap the hole/course area in the top bar to edit —
      this is expected and fine, not a failure.

---

## C. During the round — what to actually check

- [ ] Course name is correct (or you corrected it once; it should stick).
- [ ] Marking shots on the **phone** works as before (no regression).
- [ ] Marking shots on the **glasses** lands in the iOS app, fast.
- [ ] One-gesture club select feels right walking up to a shot.
- [ ] Before tapping **Undo** on the glasses, the `Last:` line matches the shot
      you mean to remove.
- [ ] Next-hole (2-step arm/confirm) on the glasses advances correctly; auto
      hole-summary pops.
- [ ] GPS doesn't flap to "stale" while you're standing still over a putt.
- [ ] Battery drop over a few holes is tolerable (note rough %/9).

---

## D. Expected (NOT bugs) — don't chase these on-course

- **No course name / wrong course at a multi-course facility.** Detection is
  fail-safe by design: it silently no-ops on poor GPS / no result / offline,
  and picks the nearest named golf POI. The top-bar edit is the fix. It never
  blocks or delays the round.
- **Course name only appears once, near the start.** Detection runs once at
  round start; it does not re-detect later or on resume (deliberate — a manual
  edit must win).
- **Brief "Club set" on the glasses before it flips to the HUD.** Intended —
  the confirmation toast then auto-returns.

## E. Real bugs — record for debrief

For anything below: note hole #, time, what you did, what happened, GPS quality
shown. Don't troubleshoot mid-round.

- Glasses stuck "Connecting…" mid-round (loopback dropped).
- A glasses shot **not** landing in the iOS app, or landing twice.
- Round won't start / app crash / DB error banner.
- Course edit doesn't persist.
- Wrong club tagged on a glasses-logged shot.
- GPS persistently "stale" while moving.

---

### Post-round
- Open the round in Review — scorecard/shots look right; course name shows as
  the title.
- Jot battery used and total round duration.
- Bring notes back; we debrief and file fixes.
