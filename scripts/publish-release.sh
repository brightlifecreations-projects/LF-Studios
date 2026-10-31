#!/bin/bash
# Publishes an LF Studios release from this Mac (no GitHub Actions minutes):
# sets the version, builds one app for Apple Silicon and Intel, zips it,
# signs it with the Sparkle update key, checks that the version users have
# now really updates to it (scripts/rehearse-update.sh), and creates the
# GitHub Releases: on
# the public LF-Studios-Releases repo (LF-Studios.zip and appcast.xml, the
# feed installed apps check for updates) and on this repo (the zip, for the
# record).
#
# It needs this Mac's Sparkle key: the public half in .env.local
# (LFSTUDIOS_SPARKLE_PUBLIC_ED_KEY), the private half in the login Keychain.
# Without them it publishes nothing (see CLAUDE.md, "Publishing").
#
#   bash scripts/publish-release.sh 1.0.1
#   bash scripts/publish-release.sh          # asks for the version
#
# Run it on main, with everything committed and pushed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PLIST="$ROOT/Info.plist"
CHANGELOG="$ROOT/CHANGELOG.md"
APP="$ROOT/.build/app.noindex/LF Studios.app"
DIST="$ROOT/.build/release-dist"
REPO_URL="https://github.com/brightlifecreations-projects/LF-Studios"
RELEASES_REPO="brightlifecreations-projects/LF-Studios-Releases"
RELEASES_URL="https://github.com/${RELEASES_REPO}"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

fail() { echo "✗ $*" >&2; exit 1; }

# MARK: GitHub CLI

GH="$(command -v gh || true)"
[ -n "$GH" ] || [ ! -x "$HOME/.local/bin/gh" ] || GH="$HOME/.local/bin/gh"
if [ -z "$GH" ]; then
    cat >&2 <<'EOF'
✗ The GitHub CLI (gh) isn't installed. Set it up once:
    brew install gh
  (no Homebrew? download the macOS installer from https://cli.github.com)
  then log in:
    gh auth login
  and choose GitHub.com → HTTPS → "Login with a web browser". The account
  needs write access to brightlifecreations-projects/LF-Studios.
EOF
    exit 1
fi
if ! "$GH" auth status >/dev/null 2>&1; then
    cat >&2 <<'EOF'
✗ The GitHub CLI isn't logged in. Run:
    gh auth login
  and choose GitHub.com → HTTPS → "Login with a web browser". The account
  needs write access to brightlifecreations-projects/LF-Studios.
EOF
    exit 1
fi

# MARK: The update key

# Every release must be able to update itself: no key, no release.
if [ -f "$ROOT/.env.local" ]; then
    set -a
    source "$ROOT/.env.local"
    set +a
fi
PUBLIC_KEY="${LFSTUDIOS_SPARKLE_PUBLIC_ED_KEY:-}"
[ -n "$PUBLIC_KEY" ] || fail "LFSTUDIOS_SPARKLE_PUBLIC_ED_KEY isn't set in .env.local, so the app couldn't check for updates. Restore the key first (CLAUDE.md, \"Publishing\")."
[ -x "$SPARKLE_BIN/generate_keys" ] || swift package resolve >/dev/null
KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" --account "${LFSTUDIOS_SPARKLE_ACCOUNT:-ed25519}" -p 2>/dev/null || true)"
[ -n "$KEYCHAIN_KEY" ] || fail "The Sparkle private key isn't in this Mac's Keychain. Restore it first: \"$SPARKLE_BIN/generate_keys\" -f <backup file> (CLAUDE.md, \"Publishing\")."
[ "$KEYCHAIN_KEY" = "$PUBLIC_KEY" ] || fail "The Keychain's Sparkle key ($KEYCHAIN_KEY) doesn't match .env.local ($PUBLIC_KEY): installed apps would reject the update."
"$GH" repo view "$RELEASES_REPO" >/dev/null 2>&1 || fail "Can't reach $RELEASES_URL, where the update feed is published."

# MARK: The version

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    [ -t 0 ] || fail "Give the version: bash scripts/publish-release.sh <version> (now ${CURRENT})"
    read -r -p "Version to publish (now ${CURRENT}): " VERSION
fi
VERSION="${VERSION#v}"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "“${VERSION}” isn't a version like 1.2.3"
TAG="v${VERSION}"

# MARK: Checks

[ "$(git branch --show-current)" = "main" ] || fail "Switch to main first (git checkout main)."
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "Commit or stash your changes first."
git fetch -q origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main isn't in step with GitHub: pull (or push) first."
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || "$GH" release view "${TAG}" >/dev/null 2>&1 || "$GH" release view "${TAG}" -R "$RELEASES_REPO" >/dev/null 2>&1; then
    fail "${TAG} is already published. Pick a new version."
fi
grep -qE "^## \[${VERSION}\]" "$CHANGELOG" || fail "CHANGELOG.md has no “## [${VERSION}]” section: add what's new first."

# MARK: Version and date in the repo

TODAY="$(date +%Y-%m-%d)"
if [ "${VERSION}" != "${CURRENT}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
fi
# "## [1.0.0]" (or "## [1.0.0] - Unreleased") becomes "## [1.0.0] - 2026-10-26".
sed -i '' -E "s/^## \[${VERSION//./\\.}\]( - Unreleased)?$/## [${VERSION}] - $TODAY/" "$CHANGELOG"
grep -qE "^## \[${VERSION//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$CHANGELOG" || fail "CHANGELOG.md's “## [${VERSION}]” heading should be “## [${VERSION}]” or “## [${VERSION}] - <date>”."
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git commit -q -am "LF Studios ${VERSION}"
    git push -q origin main
    echo "▶ Committed and pushed “LF Studios ${VERSION}”"
fi

# MARK: Build and zip

echo "▶ Building the universal app (Apple Silicon + Intel)…"
LFSTUDIOS_REQUIRE_SPARKLE_KEY=true bash "$ROOT/build-app.sh" --universal --no-install
ARCHS="$(lipo -archs "$APP/Contents/MacOS/LFStudios")"
[[ "${ARCHS}" == *arm64* && "${ARCHS}" == *x86_64* ]] || fail "The app isn't universal (${ARCHS})."
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "${BUILT}" = "${VERSION}" ] || fail "The app says version ${BUILT}, not ${VERSION}."
codesign --verify --deep --strict "$APP" || fail "The app's signature doesn't verify."
BUILT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
[ "${BUILT_KEY}" = "${PUBLIC_KEY}" ] || fail "The app's update key is “${BUILT_KEY}”, not the one in .env.local."

rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$DIST/LF-Studios.zip"
echo "▶ Zipped: $DIST/LF-Studios.zip ($(du -h "$DIST/LF-Studios.zip" | cut -f1))"

# MARK: Update feed

bash "$ROOT/generate-appcast.sh" "${VERSION}" "$DIST/LF-Studios.zip"
SIGNATURE="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' "$DIST/appcast.xml" | head -1)"
"$SPARKLE_BIN/sign_update" --verify "$DIST/LF-Studios.zip" "$SIGNATURE" || fail "The zip's update signature doesn't verify."

# MARK: Update rehearsal

# The version users have now must really update to this one through Check
# for Updates (not just see it in the feed): nothing is published otherwise.
bash "$ROOT/scripts/rehearse-update.sh" "$DIST" "${VERSION}" || fail "The update rehearsal failed: nothing was published. Fix it and run this again."

# MARK: Release notes

NOTES="$DIST/notes.md"
{
    cat <<'EOF'
## Install

Already have LF Studios 1.4.1 or later? It updates itself: LF Studios → **Check for Updates…**. Otherwise, install it by hand once:

1. Download **LF-Studios.zip** below and unzip it.
2. Drag **LF Studios** into your **Applications** folder.
3. Open **Terminal** and run this once (LF Studios isn't notarized by Apple yet, so macOS blocks it until you do):
   ```
   xattr -dr com.apple.quarantine "/Applications/LF Studios.app"
   ```
4. Open LF Studios.
5. When macOS asks, allow **Screen Recording** (System Settings → Privacy & Security → Screen Recording), and **Accessibility** if it asks for that too.
6. Quit LF Studios and open it again once, so the permissions take effect.

Works on Apple Silicon and Intel Macs with macOS 13 or later.

EOF
    echo "## What's new in ${VERSION}"
    echo ""
    # The version's CHANGELOG section, without its heading.
    awk -v v="${VERSION}" '
        $0 ~ "^## \\[" v "\\]" { on = 1; next }
        on && /^## \[/ { exit }
        on { print }
    ' "$CHANGELOG" | sed -E "s#\]\((docs/[^)]*)\)#](${REPO_URL}/blob/main/\1)#g"
} > "$NOTES"

# MARK: Publish

echo "▶ Publishing ${TAG}…"
# The public release first: its appcast.xml is what installed apps see once
# it's the latest release there.
"$GH" release create "${TAG}" "$DIST/LF-Studios.zip" "$DIST/appcast.xml" \
    -R "$RELEASES_REPO" \
    --target main \
    --latest \
    --title "LF Studios ${VERSION}" \
    --notes-file "$NOTES"
"$GH" release create "${TAG}" "$DIST/LF-Studios.zip" \
    --target "$(git rev-parse HEAD)" \
    --title "LF Studios ${VERSION}" \
    --notes-file "$NOTES"

# What installed apps will read, without a GitHub login.
FEED="$(curl -fsL "${RELEASES_URL}/releases/latest/download/appcast.xml" || true)"
[[ "${FEED}" == *"<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>"* ]] || fail "The public update feed doesn't offer ${VERSION} yet: check ${RELEASES_URL}/releases"
echo ""
echo "✓ Published: ${RELEASES_URL}/releases/tag/${TAG}"
echo "  (and $REPO_URL/releases/tag/${TAG})"
