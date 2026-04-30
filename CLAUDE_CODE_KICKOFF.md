# Claude Code Kickoff Prompt

Paste this as your first message in a fresh `claude` session inside the
project directory.

---

I'm starting a new iOS project called GolfCaddie. Please read DESIGN.md
in this directory first — it has the full architecture, data model, UI
layout, and day-by-day Phase 1 plan.

We are starting Phase 1, Day 1: project skeleton. iPhone-only target
(no Watch app in Phase 1), free Apple Developer tier signing, GRDB
configured but with empty migrations, location permission strings in
Info.plist, Background Modes capability enabled for location updates.

Before writing any code, please:

1. Read DESIGN.md end to end
2. Confirm you understand the Phase 1 scope is intentionally narrow:
   continuous GPS tracking + a Mark Shot button + club grid + hole review.
   No map (Phase 2), no pin marking (Phase 3), no voice (Phase 4), no
   Watch (Phase 6).
3. Tell me what you need from me before scaffolding the Xcode project:
   - Bundle ID prefix preference (e.g. `com.moisesvargasjr.golfcaddie`)
   - Deployment target (I'm thinking iOS 17 minimum since I have a
     16 Pro Max and don't need to support older devices)
   - Apple ID team for signing (Personal Team is fine)
4. List the steps I'll need to do manually in the Xcode GUI (signing
   team selection, Background Modes capability, anything else pbxproj
   editing can't reliably do for a fresh project)

Once we agree on those, scaffold the project per the file structure in
DESIGN.md. Expected deliverable for Day 1: app launches on simulator
or device, requests location permission, and shows a placeholder root
view that says "round not started". GRDB is integrated and the empty
Database.swift has the migration framework wired up but no tables yet
(those come Day 2).

After you scaffold, give me a clear checklist of what to verify in
Xcode before I hit Cmd+R.

I prefer direct, professional output. Skip hedging like "I'll do my
best" or "let me try" — describe what you'll do and do it. If something
is ambiguous, ask one targeted question rather than guessing. When
something requires my action in the Xcode GUI, give me precise click
paths (Project Settings → Signing & Capabilities → ...).
