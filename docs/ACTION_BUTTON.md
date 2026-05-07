# Action Button → Mark Shot

Bind the iPhone 16 Pro Max Action button to mark a shot in the
foreground or with the screen locked. The Action button can't invoke
an app directly — the bridge is a Shortcut that opens our custom
URL scheme `golfcaddie://mark`.

## One-time setup on the iPhone

### 1. Build the Shortcut

1. Open **Shortcuts** (the built-in app, not Settings).
2. Tap the **+** in the top right to create a new shortcut.
3. Tap **Add Action**.
4. Search **Open URL** and pick the action.
5. Replace the placeholder URL text with `golfcaddie://mark`.
6. Tap the shortcut name at the top (auto-generated like "URL") and
   rename it to **Mark Golf Shot**.
7. Tap **Done**.

You can sanity-check the wiring by tapping the shortcut from the
Shortcuts library — GolfCaddie should launch and (if a round is
active) record a shot. If you get an "untrusted shortcut" warning,
allow it once in **Settings → Shortcuts → Allow Untrusted Shortcuts**.

### 2. Bind the Action button

1. Open **Settings → Action Button**.
2. Swipe to the **Shortcut** dial.
3. Tap **Choose a Shortcut**.
4. Pick **Mark Golf Shot**.
5. Back out of Settings.

## Behavior

- A single press fires the shortcut, which opens the URL, which marks a
  shot via `RoundController.markShotFromActionButton()`.
- Action-button shots always store `club = nil` regardless of what's
  selected on screen — the button can't know your current club.
  Fix the missing club in the per-hole review or the round review.
- `Shot.source` is recorded as `actionButton` so you can tell them
  apart from on-screen marks.
- If no round is active, the URL handler is a no-op.
- Double-press protection: any mark within 2 seconds of the previous
  one is dropped (catches accidental double-tap; see
  `RoundController.doubleTapThreshold`).
- Background marks: if the screen is locked, the Action button still
  fires the shortcut. iOS will briefly bring GolfCaddie to the
  foreground to handle the URL; with `.authorizedAlways` location
  permission, GPS capture continues working.

## Troubleshooting

- **"Mark Golf Shot" doesn't appear in the Action button picker.** The
  Shortcut wasn't saved. Re-open Shortcuts, confirm the shortcut is in
  your library, then redo step 2.
- **Tapping the shortcut shows "Cannot Open URL".** Either the app
  isn't installed (re-Cmd+R from Xcode) or the `golfcaddie` URL scheme
  isn't registered. Check `Info.plist` for `CFBundleURLTypes` with
  scheme `golfcaddie`.
- **First press after the screen has been locked for a while doesn't
  capture GPS.** The location stack is cold. Either pre-warm it by
  pressing the on-screen MARK SHOT once, or accept that the first
  cold-start mark may have a degraded fix.
