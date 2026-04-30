# GolfCaddie — Homelab Dev Environment Setup

Handoff note for the Claude session running on `homelab` (Mac Mini M4).
Read this first, then `CLAUDE_CODE_KICKOFF.md`, then `DESIGN.md`.

## Architecture (already decided — do not relitigate)

- **Mac Mini M4 (`homelab`, `192.168.1.101`) is the dev box.** Xcode 26.4.1
  installed, Apple ID signed in, license accepted, iOS 26.4 simulator
  runtime present.
- **MacBook is a thin client.** SSH + tmux + `claude` is the primary path;
  VS Code Remote-SSH is a fallback when terminal-only gets painful.
- **Repo lives only on the Mini.** GitHub is the sync layer (private repo
  `moisesvargasjr/golf-caddie`). No working copy on the MacBook — `gh repo
  clone` to a scratch dir if read-only access is ever needed.
- **Simulator policy:** deploy to the physical iPhone 16 Pro Max for most
  Phase 1 work (GPS / Action button needs a real device). Screen-share
  into the Mini for simulator UI work as a fallback.
- **Reproducibility:** `Brewfile` + `.xcode-version` + a bootstrap script
  in the repo. Not a Docker devcontainer — pure-Linux containers cannot
  build SwiftUI/UIKit/CoreLocation apps. The Brewfile + Xcode-on-host is
  the macOS equivalent.

## Current state of the Mini

- macOS 26.4.1
- Xcode 26.4.1 at `/Applications/Xcode.app`, CLT path set, license accepted
- Homebrew 5.1.7 at `/opt/homebrew/bin/brew`
- `claude` 2.1.123 at `~/.local/bin/claude`
- `git` present (Apple-shipped at `/usr/bin/git`)
- `gh` — NOT installed yet
- `~/source/` exists; `golf-caddie` will be created here

## Next-step checklist (do these in order)

### 1. Install dev toolchain via Homebrew

Create `Brewfile` in the repo root with:

```ruby
brew "gh"
brew "xcbeautify"
brew "swiftformat"
brew "swiftlint"
brew "xcodes"
```

Then `brew bundle`. This pins the toolchain in the repo so the Mini is
re-provisionable.

### 2. Pin Xcode version

Write `.xcode-version` containing `26.4.1` so future `xcodes` runs match
what's currently installed.

### 3. Initialize git + GitHub remote

```sh
gh auth login              # GitHub CLI auth, one-time
git init
git add .
git commit -m "chore: project skeleton + handoff docs"
gh repo create moisesvargasjr/golf-caddie --private --source=. --push
```

### 4. Verify the toolchain end-to-end

```sh
xcodebuild -version
xcrun simctl list devices available | head
swiftformat --version
swiftlint --version
```

All four should print versions cleanly.

### 5. Then start Day 1 from CLAUDE_CODE_KICKOFF.md

The kickoff prompt assumes a clean directory. Running from the just-init'd
repo on the Mini is the correct entry point. Read `DESIGN.md` end-to-end
first as the kickoff prompt instructs.

## Things explicitly out of scope right now

- Watch app target (Phase 6)
- Tailscale Funnel / external access (not needed for personal sideload)
- Docker / OrbStack involvement — the iOS toolchain is native macOS only
- VS Code Remote-SSH config — set up only if/when terminal flow gets painful

## Open items to confirm with user before scaffolding the Xcode project

The kickoff prompt already asks these — surface them in the first reply:

1. Bundle ID prefix (e.g. `com.moisesvargasjr.golfcaddie`)
2. Deployment target (DESIGN.md suggests iOS 17 minimum; macOS 26 is the
   build host so iOS 18 is also fine — confirm)
3. Apple ID team for signing — Personal Team

## SSH access pattern

From the MacBook:

```sh
ssh homelab
cd ~/source/golf-caddie
tmux new -A -s golf
claude
```

The MacBook never holds a working copy.
