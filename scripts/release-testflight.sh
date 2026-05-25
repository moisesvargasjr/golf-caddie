#!/usr/bin/env zsh
# Build & upload GolfCaddie to TestFlight via App Store Connect API key.
#
# Prereqs (one-time):
#   - App Store Connect app record exists for com.moisesvargasjr.golfcaddie
#   - API key (.p8) at $ASC_KEY_PATH (default ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, chmod 600)
#   - export ASC_KEY_ID=<10-char key id>
#   - export ASC_ISSUER_ID=<uuid issuer id>
#   - Xcode signed into the Apple ID (Keychain has iOS Distribution cert, or
#     -allowProvisioningUpdates will fetch one via the API key on first run)
#
# Usage:
#   ./scripts/release-testflight.sh
#
# After upload, App Store Connect processes for ~5-15 min, then the build is
# attachable to an Internal Testing group under TestFlight in the web console.
set -euo pipefail

: "${ASC_KEY_ID:?Set ASC_KEY_ID (App Store Connect API key ID)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect issuer ID, a UUID)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
SCHEME="${SCHEME:-GolfCaddie}"

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
TS="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="$REPO_ROOT/build/archives/${SCHEME}-${TS}.xcarchive"
EXPORT_PATH="$REPO_ROOT/build/exports/${SCHEME}-${TS}"
EXPORT_OPTS="$REPO_ROOT/ExportOptions.plist"

# --- Preflight ---
[[ -f "$ASC_KEY_PATH" ]] || { echo "Missing API key: $ASC_KEY_PATH" >&2; exit 1; }
[[ -f "$EXPORT_OPTS" ]] || { echo "Missing $EXPORT_OPTS" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "xcodegen not on PATH" >&2; exit 1; }

# xcbeautify is optional pretty-printer; tee-through if not installed.
if command -v xcbeautify >/dev/null; then
  PIPE="xcbeautify"
else
  PIPE="cat"
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$(dirname "$EXPORT_PATH")"

echo "==> xcodegen generate"
xcodegen generate

echo "==> archive (Release, generic/iOS) → $ARCHIVE_PATH"
xcodebuild archive \
  -project GolfCaddie.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | $PIPE

echo "==> exportArchive (destination=upload) → $EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | $PIPE

echo ""
echo "✓ Upload complete. Build will appear in App Store Connect → TestFlight"
echo "  in ~5–15 min, then attach to an Internal Testing group to distribute."
