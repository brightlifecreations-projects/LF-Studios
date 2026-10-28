#!/bin/bash
# The update feed (appcast.xml) for one release, signed with the Sparkle key
# in this Mac's Keychain. publish-release.sh runs it; it uploads nothing.
#
#   bash generate-appcast.sh <version> /path/to/LF-Studios.zip
#
# Writes appcast.xml (and the update window's notes, from that version's
# CHANGELOG section) next to the zip. The zip's download link is the
# version's release on the public releases repo, where publish-release.sh
# uploads it with appcast.xml; the app's SUFeedURL reads appcast.xml from the
# latest release there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/.env.local" ]; then
    set -a
    source "$SCRIPT_DIR/.env.local"
    set +a
fi

VERSION="${1:-}"
ZIP_PATH="${2:-}"
APPCAST_BIN="${LFSTUDIOS_GENERATE_APPCAST_BIN:-$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
SPARKLE_ACCOUNT="${LFSTUDIOS_SPARKLE_ACCOUNT:-ed25519}"
RELEASES_REPO_URL="${LFSTUDIOS_RELEASES_REPO_URL:-https://github.com/brightlifecreations-projects/LF-Studios-Releases}"

if [ -z "$VERSION" ] || [ -z "$ZIP_PATH" ] || [ ! -f "$ZIP_PATH" ]; then
    echo "Usage: bash generate-appcast.sh <version> /path/to/LF-Studios.zip"
    exit 1
fi

if [ ! -x "$APPCAST_BIN" ]; then
    echo "✗ Sparkle generate_appcast not found or not executable: $APPCAST_BIN"
    echo "  Run swift build once so SwiftPM downloads Sparkle's tools."
    exit 1
fi

OUT_DIR="$(cd "$(dirname "$ZIP_PATH")" && pwd)"
ZIP_NAME="$(basename "$ZIP_PATH")"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp "$ZIP_PATH" "$STAGING_DIR/$ZIP_NAME"
# Same name as the zip: generate_appcast embeds it in the feed, and Sparkle
# shows it in the update window.
python3 "$SCRIPT_DIR/scripts/changelog-html.py" "$SCRIPT_DIR/CHANGELOG.md" "$VERSION" > "$STAGING_DIR/${ZIP_NAME%.*}.html"

echo "▶ Signing the zip and writing the update feed…"
"$APPCAST_BIN" \
    --account "$SPARKLE_ACCOUNT" \
    --embed-release-notes \
    --download-url-prefix "$RELEASES_REPO_URL/releases/download/v$VERSION/" \
    --link "$RELEASES_REPO_URL" \
    "$STAGING_DIR"

APPCAST="$STAGING_DIR/appcast.xml"
[ -f "$APPCAST" ] || { echo "✗ Sparkle did not create appcast.xml"; exit 1; }
grep -q "sparkle:edSignature=" "$APPCAST" || { echo "✗ The update feed has no signature: is the Sparkle key in this Mac's Keychain?"; exit 1; }
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST" || { echo "✗ The update feed isn't for $VERSION"; exit 1; }

cp "$APPCAST" "$OUT_DIR/appcast.xml"
cp "$STAGING_DIR/${ZIP_NAME%.*}.html" "$OUT_DIR/release-notes.html"
echo "✓ Update feed: $OUT_DIR/appcast.xml"
