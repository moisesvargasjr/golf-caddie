# GolfCaddie ⇄ Glasses — iOS Integration Contract

> **Status:** Implemented (commit `f59a736`). This file is the iOS-side copy of
> the canonical contract. Source of truth lives in the glasses repo at
> `golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md`; keep the two in
> lockstep. The glasses app's `src/shared/types.ts` is the canonical
> TypeScript form of the schema.
>
> **Where it's built:** `GolfCaddie/Glasses/` (`GolfState.swift`,
> `GlassesStateMapper.swift`, `GlassesServer.swift`), plus
> `GolfCaddie/Views/GlassesSettingsView.swift`, the `glasses` case in
> `ShotSource`, and `logShotFromGlasses()` / `undoLastActionFromGlasses()` on
> `RoundController`. Enable via Settings (gear on the idle screen) →
> "Glasses server" (`@AppStorage("glassesServerEnabled")`, default off).

## What this is

A small embedded HTTP server inside the GolfCaddie iOS app exposing **one read
endpoint and two write endpoints**, serving the active round to the Even
Realities G2 glasses app (a WebView in the Even App on the same phone).

**Coupling reality:** the server is *removable* (delete `GolfCaddie/Glasses/`,
the `ShotSource.glasses` case + its switch arms, the two `RoundController`
methods + the double-tap-guard gate, `GlassesSettingsView`, and the `RootView`
wiring). But the write endpoints are **not zero-coupling and not
behavior-free**: to satisfy read-after-write *and* be visible in the phone UI,
the POST handlers drive the **same live `@MainActor RoundController` the UI
owns** (not a snapshot), via a non-MainActor listener bridging onto the
MainActor.

## Transport & binding

- Bound to **`127.0.0.1` (loopback) on port `8417`**. Never `0.0.0.0` — round
  data must not be exposed on the WiFi network.
- Plain HTTP (no TLS) — loopback only, same device, no secrets in transit.
- The consumer is the Even App's WebView on the **same phone**; loopback is
  reachable across apps on iOS. **Validate on real hardware Day 2, not Day 6** —
  cleartext reachability is governed by **App Transport Security on the client
  (the Even App's WKWebView)**, which GolfCaddie does not control. GolfCaddie's
  listener needs **no** ATS change on its side, and loopback vs LAN does not
  affect ATS. Loopback (`127.0.0.1`) is *more* likely than an arbitrary LAN IP
  to receive an implicit ATS exemption. **There is no LAN "fallback"** — if the
  Even App's WebView ATS-blocks cleartext loopback, a LAN IP (also cleartext,
  also ATS-governed, less likely exempt) will not help. The only real options
  if blocked are: the Even App declares an ATS exception, or serve TLS on
  loopback (self-signed). This is the one binary platform unknown.
- Single low-frequency client: ~1 GET / 1.5 s, occasional POSTs. No auth, no
  rate limiting. `Access-Control-Allow-Origin: *` echoed; `OPTIONS` → 204.

## Background execution (critical)

iOS suspends backgrounded apps. The server **stays responsive for the whole
round** while GolfCaddie is backgrounded by riding on the existing **location
background mode** (continuous GPS during a round keeps the process alive; the
HTTP server lives in that same process). When no round is active and the app is
backgrounded, the server may stop responding — that is fine; the glasses show
the idle screen. No `BGTask`, no new entitlement.

## Endpoints

### `GET /api/state`

Returns the current round read model. Poll target. **200** always (even when no
round). Body = `GolfState`:

```jsonc
{
  "contractVersion": 1,
  "active": true,
  "round":  { "id": "…", "startedAt": "ISO-8601", "courseName": "…" },
  "hole":   { "number": 7, "par": 4, "shotCount": 3, "penalties": 0, "score": 3,
              "distanceToGreenYards": 142 },  // OMITTED unless curated course + green anchor + fix
  "currentClub": "7i",                      // short club form, or omitted
  "lastShot": { "club": "Dr", "distanceYards": 248, "sequenceNumber": 2 },  // club = PRIOR shot's club (traveled the distance)
  "scoring": { "totalStrokes": 24, "totalPar": 28, "toPar": -1, "holesCompleted": 6 },
  "gps": { "accuracyMeters": 3.2, "stale": false },   // accuracyMeters OMITTED = no fix
  "battery": 84,                                       // phone battery 0–100
  "holes": [ { "number": 1, "par": 4, "score": 4, "confirmedAt": "ISO-8601",
               "shots": [ { "sequenceNumber": 1, "club": "Dr", "distanceYards": 248 } ] } ]
}
```

When no round is active: `{ "contractVersion": 1, "active": false }` (all other
fields omitted). `score` = `shotCount + penalties`. `gps.stale` = last fix
> 10 s old. `holes[].confirmedAt` present ⇒ the hole is finalized (drives the
glasses' auto hole-summary). The in-progress hole appears in `holes[]` once it
has shots, with `confirmedAt` omitted (not yet finalized).

#### Field encoding rules (Swift `Codable` ⇄ TypeScript)

- **No JSON `null`.** Dates/UUIDs are pre-converted to `String` in the mapper
  and `GolfState` is plain `Encodable`, so the default `JSONEncoder` **omits**
  nil optionals; it never emits `"key": null`. The mock server and
  `fixtures.ts` must likewise **omit** absent keys. TypeScript must treat a
  field as optional/absent and **never** test `x === null`.
- **`gps.accuracyMeters`** — `CLLocation.horizontalAccuracy` is negative when
  invalid; iOS coerces `<= 0` to the field being **absent**. Glasses GPS render
  precedence: **`stale` → `no fix` (accuracyMeters absent) → `±Xm`**.
- **`currentClub` / `lastShot.club` / `shots[].club`** — iOS sends the **short**
  club form (`"SW"`, `"7i"`, `"Dr"`), matching the screen mockups and the
  46-char line budget.
- **`scoring`** — `totalPar`/`toPar` aggregate **only confirmed holes that have
  a par** (omit both if none); `totalStrokes` covers all confirmed holes;
  `holesCompleted` = confirmed count. `toPar` may briefly lag `totalStrokes`;
  tolerate, do not treat as an error. (Deliberately differs from the in-app
  `RoundReviewView.totalPar`, which requires every hole to have a par.)
- **`hole.penalties`** — iOS sends the **stroke-sum** of penalties (so
  `score = shotCount + penalties` matches the in-app scorecard). OPEN: if the
  glasses team means penalty *row count*, it's a one-line mapper change.
- **`holes[]`** — iOS trims the eagerly-created trailing empty Hole N+1 before
  building `holes[]`/`scoring`; the mock must mimic.
- **`round.startedAt` / `holes[].confirmedAt`** — ISO-8601 **without**
  fractional seconds (`2026-05-07T14:32:11Z`). Mock fixtures must match.

### `POST /api/shot`

Log one shot on the **currently active hole**. Empty request body (club
selection from glasses is future scope). Effect:

- Increment the active hole's shot count; recompute `score`/`scoring`.
- **Fast: < ~500 ms p99.** Does **not** reuse the 5s-GPS-blocking shot path
  (`captureBestFix`). During an active round continuous best-accuracy location
  is already running, so the handler logs immediately with the best currently
  available fix (`source = .glasses`, `club = nil`, `hadGPS` from the latest
  fix). The glasses' ~5 s timeout is a true **error bound**, not the expected
  duration — keeping POST fast is what prevents the slow-success-then-user-retry
  double-log.
- The glasses tap **bypasses** the in-app double-tap dedupe guard (that guard
  is for the physical Action button / screen double-press; it is gated to
  `.button`/`.actionButton` only).

Response: **200** with the updated full `GolfState`. If no round/hole is
active: **409** `{ "error": "no_active_hole" }`.

### `POST /api/shot/undo`

Revert the **most recent** shot or penalty on the active hole. Empty body.

- Delete **whichever of {newest shot, newest penalty} on the active hole has
  the later timestamp** — not "pop the last shot." If the last action was a
  penalty, undo removes the penalty. After a shot delete, `currentHoleShots` is
  resynced from the repo so the in-app UI stays consistent.
- Nothing to undo: **200** no-op with current `GolfState` (safe to call
  redundantly).

Response: **200** with the updated full `GolfState`. No round/hole active:
**409** `{ "error": "no_active_hole" }`.

### `GET /api/health`

**200** `{ "ok": true }`. Lets the glasses distinguish "server up, no round"
from "server down."

## Semantics & guarantees

- **One gesture = exactly one POST; never coalesced or auto-fired.** The
  command-client in-flight guard rejects a second write while one is pending.
- **Writes are user-initiated, never auto-retried.** No silent retry on
  timeout. A `FOREGROUND_EXIT_EVENT` mid-write does not trigger a resend on
  `FOREGROUND_ENTER_EVENT` — iOS still applies an in-flight POST and the glasses
  reconcile from the next poll. No idempotency key is sent.
- **Read-after-write:** the `GolfState` returned by a POST already includes that
  write's effect (the handler mutates then maps in one MainActor hop, no await
  between); a subsequent `GET /api/state` never regresses it.
- **Single writer:** only the glasses client writes via HTTP; concurrent
  phone-side edits are allowed and reflected on the next GET.

## Out of scope

Club selection / penalty entry / hole confirmation from glasses; discovery or
pairing UI; multi-client; auth. Only the four endpoints above.

## Acceptance (iOS side)

```bash
curl -s 127.0.0.1:8417/api/health | jq .ok                # true
curl -s 127.0.0.1:8417/api/state  | jq .active            # false with no round, true mid-round
curl -s -X POST 127.0.0.1:8417/api/shot | jq .hole        # shotCount +1, score recomputed
curl -s -X POST 127.0.0.1:8417/api/shot/undo | jq .hole   # back to prior shotCount
# add a penalty in-app, then POST /api/shot/undo removes the penalty (newer), not a shot
curl -s 127.0.0.1:8417/api/state | grep -c null           # 0
# Backgrounded mid-round (location active): GET still responds within ~1s.
```

Headless-verified at `f59a736`: health, idle-state shape (no nulls,
`contractVersion`), 409 idle gate, 404 unknown route. Active-round assertions
(POST increments, undo, penalty-precedence) verified on device during the joint
field test — the simulator cannot drive a real round/GPS.
