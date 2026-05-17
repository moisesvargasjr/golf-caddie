# Glasses Integration — iOS Server Side

How GolfCaddie exposes live round state to the Even Realities G2 glasses
companion app (`golf-caddie-glasses`, separate repo).

## Principle: Minimal, Removable Footprint

This integration is intentionally a thin, isolated layer. If the G2
hardware is returned, the entire feature is removed by:

1. Deleting the `GolfCaddie/Glasses/` folder
2. Removing one settings toggle and its call site in `RootView`

No model changes, no persistence changes, no changes to capture or
review logic. The glasses app consumes data that `RoundController` and
the repositories already produce.

## Architecture

```
RoundController (@Observable, existing)
        │  read-only snapshot
        ▼
GlassesStateMapper  ──►  GolfState (Codable)
        │
        ▼
GlassesServer (embedded HTTP, local network)
        │  GET /api/state  → JSON
        ▼
golf-caddie-glasses web app (Even Hub WebView)
```

The server is read-only. It never mutates rounds, shots, or holes.
Phase 1 is display-only; two-way control (mark shot from glasses) is a
later phase and explicitly out of scope here.

## New Files

```
GolfCaddie/
└── Glasses/
    ├── GlassesServer.swift        # NWListener-based HTTP server
    ├── GlassesStateMapper.swift   # RoundController + repos → GolfState
    └── GolfState.swift            # Codable structs (the API contract)
```

Three files, one folder. That is the entire footprint besides the
settings toggle.

## HTTP Server Choice

Use **`Network.framework` `NWListener`** — no third-party dependency,
no SPM addition, available iOS 13+. A single GET endpoint does not
justify pulling in Telegraph or Swifter.

- Bind to the local network interface on a fixed port (default
  `8080`, configurable)
- Serve only `GET /api/state`
- Respond `200` with `application/json`, `404` for anything else
- CORS header `Access-Control-Allow-Origin: *` (the Even App WebView
  is a different origin)
- No auth in Phase 1 (LAN only, personal use); a shared token can be
  added later if needed — the glasses app already plans for a token in
  its connection URL pattern

The server lifecycle is tied to the app being foreground + a round
being active (or always-on if the setting prefers). Background
operation is not required: the glasses only matter while playing, and
the phone is already running continuous location then.

## The Contract: `GolfState.swift`

Must stay byte-for-byte compatible with
`golf-caddie-glasses/src/shared/types.ts`. Mirror exactly:

```swift
struct GolfState: Codable {
    var active: Bool
    var round: RoundInfo?
    var hole: HoleInfo?
    var currentClub: String?
    var lastShot: LastShot?
    var scoring: Scoring?
    var gps: GPS
    var battery: Int?
    var holes: [HoleSummary]?
}

struct RoundInfo: Codable {
    var id: String
    var startedAt: String          // ISO 8601
    var courseName: String?
}

struct HoleInfo: Codable {
    var number: Int
    var par: Int?
    var shotCount: Int
    var penalties: Int
    var score: Int                 // shotCount + penalties
}

struct LastShot: Codable {
    var club: String?
    var distanceYards: Int?
    var sequenceNumber: Int
}

struct Scoring: Codable {
    var totalStrokes: Int
    var totalPar: Int?
    var toPar: Int?
    var holesCompleted: Int
}

struct GPS: Codable {
    var accuracyMeters: Double?    // raw horizontalAccuracy
    var stale: Bool
}

struct HoleSummary: Codable {
    var number: Int
    var par: Int?
    var score: Int
    var shots: [ShotSummary]
}

struct ShotSummary: Codable {
    var sequenceNumber: Int
    var club: String?
    var distanceYards: Int?
}
```

## Mapping (`GlassesStateMapper.swift`)

Pure function: takes the current `RoundController` + repository reads,
returns a `GolfState`. No side effects.

| GolfState field          | Source |
|--------------------------|--------|
| `active`                 | `RoundController.isActive` |
| `round.id/startedAt`     | `RoundController.currentRound` |
| `round.courseName`       | `Round.courseName` |
| `hole.number/par`        | `RoundController.currentHole` |
| `hole.shotCount`         | `RoundController.currentHoleShots.count` |
| `hole.penalties`         | `PenaltyRepository.forHole(...)` sum of `strokeCount` |
| `hole.score`             | shotCount + penalties (same rule as `DESIGN.md`) |
| `currentClub`            | `RoundController.currentClub?.longName` |
| `lastShot`               | `currentHoleShots.last` + distance from prior shot |
| `lastShot.distanceYards` | `Distance` helper (Haversine, meters→yards), prior→last shot |
| `scoring.*`              | aggregate over `HoleRepository.holesForRound` |
| `gps.accuracyMeters`     | `LocationManager.latestLocation?.horizontalAccuracy` |
| `gps.stale`              | last fix timestamp > 10s old (same rule as `ActiveRoundView`) |
| `battery`                | `BatteryMonitor.percent` |
| `holes`                  | confirmed holes only, for the scorecard screen |

`lastShot.distanceYards`: distance from the previous shot's coordinate
to the last shot's coordinate, reusing `Utils/Distance.swift`. Null
when either shot lacks GPS (`hadGPS == false`).

`gps.accuracyMeters` is the raw `horizontalAccuracy` value — the same
number the on-screen context bar renders as `GPS ±Xm`. The glasses app
formats it; iOS just passes the number through.

## Settings Toggle

Add a single `@AppStorage("glassesServerEnabled")` bool, default
`false`. Surface it wherever app settings live (or a minimal inline
toggle in `RootView` if there is no settings screen yet). When true,
`GlassesServer` starts on round start and stops on round end. When
false, the server type is never instantiated.

Removal = delete the toggle, delete the `Glasses/` folder, delete the
start/stop calls in `RoundController.startRound()` / `endRound()`.

## Build Order

### Step 1 — Contract types
- Add `GolfState.swift`
- Verify it encodes to JSON matching the glasses repo's `types.ts`
  (round-trip a hand-written fixture, diff against the mock server's
  output)

### Step 2 — State mapper
- Add `GlassesStateMapper.swift`
- Unit test: construct a known round/hole/shot fixture in an in-memory
  GRDB, assert the mapped `GolfState` JSON
- Reuse `Distance.swift` for `lastShot.distanceYards`

### Step 3 — Embedded server
- Add `GlassesServer.swift` (NWListener, single GET route)
- Wire start/stop into `RoundController` behind the setting
- Manual test: `curl http://<iphone-ip>:8080/api/state` while a round
  is active, diff shape against the glasses mock server

### Step 4 — End-to-end
- Run the real `golf-caddie-glasses` app pointed at the iPhone's IP
- Play a simulated round (walk the block), confirm the G2 HUD tracks
  hole, club, last-shot distance, score, and `±Xm` GPS live

### Step 5 — Robustness
- Handle WiFi unavailable / port in use gracefully (log, don't crash)
- Confirm zero behavioral/battery impact when the toggle is off
- Confirm server stops cleanly on round end and app background

## Out of Scope

- Marking shots / selecting clubs from the glasses (two-way) — future
- Auth tokens — LAN + personal use only for now
- Background server operation — glasses only used mid-round, foreground
- Course/pin distances — depends on Phase 2 (satellite map) data

## Related

- Glasses app + full screen designs:
  `golf-caddie-glasses/docs/IMPLEMENTATION_PLAN.md`
- Scoring rule, data model: `DESIGN.md`
