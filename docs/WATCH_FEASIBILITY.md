# Apple Watch companion — feasibility & recommendation

> **Status:** analysis only, no code. Decision doc for a future build/no-build
> call. Based on a full read of the iOS app, the glasses repo, and the
> `golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md` / `ARCHITECTURE.md`.

## TL;DR

A watchOS companion is **structurally cheap to scaffold** (XcodeGen makes the
target a few lines of `project.yml`) but **expensive to make useful**, because
feature parity needs a shared-model refactor *and* a `WatchConnectivity` layer
that does not exist today.

The headline question — *"leave the phone on the cart, let the glasses get
position from the watch"* — is **not possible**, and not because of GPS range.
It's architectural (see below). So a watch is only worth building as a
**standalone, no-glasses wrist experience**, not as a GPS relay for the
glasses. Recommended: **defer the build**; if pursued later, scope it to the
standalone no-glasses case first.

## The decisive finding: the glasses are permanently phone-tethered

The Even Realities G2 app is **not** a program running on the glasses talking
to GolfCaddie. It is a web app running in a **WebView inside the Even App on
the phone**, which talks to GolfCaddie over the phone's **`127.0.0.1` loopback**
HTTP server (`GolfCaddie/Glasses/GlassesServer.swift`, bound to loopback per the
integration contract). The G2 lenses are a Bluetooth display driven by that
phone-side app.

Consequences:

- **The phone must be present and running GolfCaddie for the glasses to show
  anything at all.** There is no glasses↔watch path; the watch cannot serve the
  loopback API and cannot reach the Even App.
- **If the phone is on the cart, the glasses are already dead** — so "watch
  feeds the glasses position instead" has nothing to feed. Range is moot.
- All GPS today is phone-sourced: `LocationManager.latestLocation` →
  `GlassesStateMapper.gpsDTO` → `GET /api/state`. There is exactly one GPS
  source in the system and it is the iPhone's `CLLocationManager`.
- There is **zero** watch code in the repo today — no `WatchConnectivity`,
  `WCSession`, watchOS target, or handoff logic (grep-confirmed).

So the watch and the glasses are **mutually exclusive value propositions**, not
complementary: the glasses already require the phone (and thus its GPS); a
watch's only unique value is when there are **no glasses**.

## Where a watch *is* worth it

A **standalone no-glasses round controller on the wrist**, mirroring the
existing `RoundController` entry points so the phone can stay pocketed:

| Action | Today's entry point |
|---|---|
| Mark shot | `RoundController.markShot()` / `markShotFromActionButton()` |
| Set club | `setCurrentClub(_:)` |
| Undo | `removeLastShot()` |
| Next hole | `confirmHoleAndAdvance(par:)` |
| Glance: hole #, shot count, score, GPS quality | `GlassesStateMapper`-style snapshot |

This is essentially the same surface the glasses app already consumes — the
contract is a good template for what a watch would mirror. Secondary value: a
wrist remote when the phone is pocketed but the golfer doesn't wear glasses.

It does **not** replace the glasses for glasses users, and it cannot extend the
glasses' range.

## Effort sketch (the real cost is not the target)

1. **Add the watchOS target** — *small*. XcodeGen: one target block in
   `project.yml` (`platform: watchOS`, own sources path, own Info.plist,
   `embed: true` on the iOS app), then `xcodegen generate`. Maybe a day.
2. **Extract a shared module** — *medium*. `Round`/`Hole`/`Shot`/`ClubID` and
   the GRDB repositories are currently compiled only into the iOS app
   (`sources: - path: GolfCaddie`). The watch needs the domain types; pulling
   them into a shared SPM package or shared sources group, without disturbing
   the iOS build or the GRDB dependency, is the first real refactor.
3. **`WatchConnectivity` from scratch** — *the dominant cost*. There is none
   today. The watch is a *second writer* into round state that authoritatively
   lives on the phone (DB + the single `@MainActor RoundController` the UI and
   glasses server share). Reliable bidirectional sync (live state push to the
   wrist, actions pushed back, reachability/latency/queued-while-unreachable,
   reconciling with the phone as source of truth) is a substantial,
   correctness-sensitive subsystem — the same "two writers, one truth" problem
   the glasses contract had to solve, but over WC instead of loopback HTTP.
4. **Watch GPS question** — Apple Watch GPS is roughly comparable to iPhone
   GPS, sometimes worse (wrist vs. pocket, body blocking). It does **not**
   improve on the phone, and it cannot help the glasses (see above). A
   watch-only round would need its own capture + sync-to-phone model.

## Recommendation

- **Defer building the watch app now.** It does not unlock the "phone on the
  cart" scenario (architecturally impossible with the glasses), and for glasses
  users it adds nothing. Current effort is better spent on the phone + glasses
  experiences.
- **If/when revisited, scope v1 to standalone no-glasses use** — wrist mark
  shot / club / undo / next hole + a glance screen — and budget the
  shared-model extraction and `WatchConnectivity` as the bulk of the work, not
  the target setup.
- **Reuse the glasses contract as the design template.** The watch consumes
  essentially the same state/action surface; `IOS_INTEGRATION_CONTRACT.md` and
  `GlassesStateMapper`/`GlassesServer` are the proven shape to mirror over WC.

## Open questions for a future decision

- How often is the golfer **without** glasses but **with** the watch? That
  population size is the entire ROI of this feature.
- Is a watch round fully **standalone** (capture on the wrist, sync to phone
  later) or strictly a **remote** for an active phone round? The former needs a
  watch-side capture + conflict model; the latter only needs the phone
  reachable, which is a much smaller build.
- Acceptable correctness model for two writers (phone always wins? last-write?
  queued actions on reconnect?) — decide before any code.
