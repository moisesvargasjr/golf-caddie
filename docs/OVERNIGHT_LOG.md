# Overnight Agent Log — Foundations Batch (night 1, 2026-06-21)

Branch: `overnight/foundations-0621` (both repos). Commits are **local only** (no push);
review in the morning via `git log`/`git diff` on the branch in each repo.

Scope: 7 items in order — B2, B3, B4, B5, B8, B20 (phone/watch repo) + B17 (glasses repo).

Environment discovered:
- Phone scheme `GolfCaddie`, test target `GolfCaddieTests`, watch scheme `GolfCaddieWatch`.
- Test/build sim: **iPhone 17 Pro** (iOS 27). Watch sim: **Apple Watch Series 11 (46mm)** (watchOS 27).
- `xcodegen` 2.45.4 + `project.yml` present — run `xcodegen generate` if Swift files are added/removed.
- Glasses repo at `~/source/golf-caddie-glasses` (TypeScript/Vite).
- RAM-constrained Mac → builds run strictly one at a time.

Legend: ✅ done · ◑ partial · ⏭️ skipped/blocked.

---

## Status board

| Item | Title | Status | Tests |
|---|---|---|---|
| B2  | Transport idempotency (UUID on watch→phone commands) | … | … |
| B3  | Honest shot provenance + model fields | … | … |
| B4  | Watch→phone delivery feedback ("syncing N" chip) | … | … |
| B5  | Per-hole track segmentation + stop/dwell detection | … | … |
| B8  | Track as shot-location source of truth | … | … |
| B20 | Feature-flag spike/validation behind `#if DEBUG` | … | … |
| B17 | Glasses polling cadence + staleness cue + battery | … | … |

---

## Per-item detail

(filled in as each item lands)
