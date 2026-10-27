#!/bin/bash
# Publishes an LF Studios release from this Mac (no GitHub Actions minutes):
# sets the version, builds one app for Apple Silicon and Intel, zips it, and
# creates a GitHub Release with LF-Studios.zip and install steps.
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
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || "$GH" release view "${TAG}" >/dev/null 2>&1; then
    fail "${TAG} is already published. Pick a new version."
fi
grep -qE "^## \[${VERSION}\]" "$CHANGELOG" || fail "CHANGELOG.md has no “## [${VERSION}]” section: add what's new first."

# MARK: Version and date in the repo

TODAY="$(date +%Y-%m-%d)"
if [ "${VERSION}" != "${CURRENT}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
fi
# "## [1.0.0] - Unreleased" becomes "## [1.0.0] - 2026-10-26".
sed -i '' -E "s/^## \[${VERSION}\] - Unreleased$/## [${VERSION}] - $TODAY/" "$CHANGELOG"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git commit -q -am "LF Studios ${VERSION}"
    git push -q origin main
    echo "▶ Committed and pushed “LF Studios ${VERSION}”"
fi

# MARK: Build and zip

echo "▶ Building the universal app (Apple Silicon + Intel)…"
bash "$ROOT/build-app.sh" --universal --no-install
ARCHS="$(lipo -archs "$APP/Contents/MacOS/LFStudios")"
[[ "${ARCHS}" == *arm64* && "${ARCHS}" == *x86_64* ]] || fail "The app isn't universal (${ARCHS})."
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "${BUILT}" = "${VERSION}" ] || fail "The app says version ${BUILT}, not ${VERSION}."
codesign --verify --deep --strict "$APP" || fail "The app's signature doesn't verify."

rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$DIST/LF-Studios.zip"
echo "▶ Zipped: $DIST/LF-Studios.zip ($(du -h "$DIST/LF-Studios.zip" | cut -f1))"

# MARK: Release notes

NOTES="$DIST/notes.md"
{
    cat <<'EOF'
## Install

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
"$GH" release create "${TAG}" "$DIST/LF-Studios.zip" \
    --target "$(git rev-parse HEAD)" \
    --title "LF Studios ${VERSION}" \
    --notes-file "$NOTES"
echo ""
echo "✓ Published: $REPO_URL/releases/tag/${TAG}"
