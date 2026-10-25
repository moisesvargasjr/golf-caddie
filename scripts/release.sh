#!/usr/bin/env bash
# Cut a TestFlight release by pushing a tag. Xcode Cloud only builds for
# TestFlight when it sees one of these tags, never on a plain branch push.
#
#   alpha/<version>-<n>  → Xcode Cloud "Alpha" workflow → internal group (just me)
#   beta/<version>-<n>   → Xcode Cloud "Beta"  workflow → external group (friends)
#
# Usage:
#   scripts/release.sh version            # print the current marketing version
#   scripts/release.sh bump minor         # 1.0 → 1.1.0 (also: major | patch | X.Y.Z)
#   scripts/release.sh alpha              # tag HEAD as alpha/<version>-<n> and push
#   scripts/release.sh beta               # tag HEAD (must be on origin/main) as beta/<version>-<n>
#
# `bump` only edits files; commit it through a PR like any other change, then
# tag once it's merged. See docs/RELEASING.md for the App Store Connect setup.
set -euo pipefail

cd "$(dirname "$0")/.."

# The marketing version lives in project.yml (source of truth) and both
# generated Info.plists; the watch app must match the iOS app.
VERSION_FILES=(project.yml GolfCaddie/Info.plist GolfCaddieWatch/Info.plist)

current_version() {
  sed -n 's/^ *CFBundleShortVersionString: "\(.*\)"$/\1/p' project.yml | head -n1
}

die() { echo "error: $*" >&2; exit 1; }

cmd_bump() {
  local arg="${1:-}" cur major minor patch new
  cur="$(current_version)"
  IFS=. read -r major minor patch <<<"$cur"
  minor="${minor:-0}"; patch="${patch:-0}"
  case "$arg" in
    major) new="$((major + 1)).0.0" ;;
    minor) new="$major.$((minor + 1)).0" ;;
    patch) new="$major.$minor.$((patch + 1))" ;;
    [0-9]*.[0-9]*.[0-9]*) new="$arg" ;;
    *) die "usage: release.sh bump major|minor|patch|X.Y.Z" ;;
  esac

  perl -pi -e "s/(CFBundleShortVersionString: )\"[^\"]*\"/\${1}\"$new\"/" project.yml
  perl -0pi -e "s|(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*|\${1}$new|" \
    GolfCaddie/Info.plist GolfCaddieWatch/Info.plist

  echo "Version $cur → $new in: ${VERSION_FILES[*]}"
  echo "Commit this through a PR, merge it, then run: scripts/release.sh beta"
}

cmd_tag() {
  local channel="$1" version head n tag
  version="$(current_version)"
  [[ -n "$version" ]] || die "couldn't read CFBundleShortVersionString from project.yml"

  [[ -z "$(git status --porcelain)" ]] || die "working tree is dirty; commit or stash first"
  git fetch --quiet --tags origin
  head="$(git rev-parse HEAD)"

  if [[ "$channel" == beta ]]; then
    git fetch --quiet origin main
    git merge-base --is-ancestor "$head" origin/main \
      || die "beta builds must come from main; merge first (HEAD isn't on origin/main)"
  else
    [[ -n "$(git branch -r --contains "$head")" ]] \
      || die "HEAD isn't pushed yet; push the branch first so Xcode Cloud can fetch it"
  fi

  # Next sequence number for this version on this channel.
  n="$(git tag --list "$channel/$version-*" | sed "s|^$channel/$version-||" \
        | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"
  n="$(( ${n:-0} + 1 ))"
  tag="$channel/$version-$n"

  echo "Tagging $(git rev-parse --short HEAD) as $tag"
  git tag -a "$tag" -m "$channel $version ($n)"
  git push origin "$tag"
  echo "✓ Pushed $tag. Xcode Cloud will build it and send it to TestFlight."
}

case "${1:-}" in
  version) current_version ;;
  bump) cmd_bump "${2:-}" ;;
  alpha|beta) cmd_tag "$1" ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
