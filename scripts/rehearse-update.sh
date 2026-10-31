#!/bin/bash
# Rehearses the update users will get, before it's published: the version
# users have now (the latest release on LF-Studios-Releases) updates itself
# to the new build through LF Studios → Check for Updates… → Install Update,
# and must come back running the new version.
#
# It runs a copy of the old version from a temporary folder, pointed at a
# feed served from this Mac (the new appcast.xml and zip, so the signature
# Sparkle checks is the real one), and clicks the buttons the way a user
# would. publish-release.sh runs it before publishing; it also runs alone:
#
#   bash scripts/rehearse-update.sh .build/release-dist 1.16.0
#   bash scripts/rehearse-update.sh .build/release-dist 1.15.0 v1.14.0   # from an older release
#
# Needs: LF Studios not running (it's quit first, and opened again after),
# and Accessibility for the app running this script (Terminal, or the code
# editor), so it can click the menu and the update window.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:?Give the folder with LF-Studios.zip and appcast.xml}"
VERSION="${2:?Give the new version}"
OLD_TAG="${3:-}"   # the latest release when not given
DIST="$(cd "$DIST" && pwd)"
RELEASES_REPO="brightlifecreations-projects/LF-Studios-Releases"
GH="$(command -v gh || echo "$HOME/.local/bin/gh")"

fail() { echo "✗ Update rehearsal: $*" >&2; exit 1; }
[ -f "$DIST/LF-Studios.zip" ] && [ -f "$DIST/appcast.xml" ] || fail "no LF-Studios.zip and appcast.xml in $DIST"

# The real path (/private/var/…): the running app reports that one.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lfstudios-rehearsal.XXXXXX")" && pwd -P)"
OLD_APP="$WORK/old/LF Studios.app"
SERVER_PID=""
REOPEN=false
cleanup() {
    local status=$?
    pkill -f "$WORK/old/LF Studios.app/Contents/MacOS/" 2>/dev/null || true
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "$WORK"
    if $REOPEN; then open "/Applications/LF Studios.app" || true; fi
    exit "$status"
}
trap cleanup EXIT

# Two copies share one app ID (and Sparkle's installer with it): quit the
# one in use first, the normal way, so it saves and can say if it's busy.
if pgrep -x LFStudios >/dev/null; then
    echo "▶ Quitting LF Studios for the rehearsal (it opens again afterwards)…"
    osascript -e 'tell application id "com.lfstudios.app" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do pgrep -x LFStudios >/dev/null || break; sleep 1; done
    pgrep -x LFStudios >/dev/null && fail "LF Studios didn't quit (a recording or export running?). Quit it and run again."
    REOPEN=true
fi
[ "$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null)" = "true" ] \
    || fail "allow this app (Terminal, or your code editor) in System Settings → Privacy & Security → Accessibility, so it can click Check for Updates."

# The version users have now.
mkdir -p "$WORK/download" "$WORK/old" "$WORK/feed"
"$GH" release download ${OLD_TAG:+"$OLD_TAG"} -R "$RELEASES_REPO" -p LF-Studios.zip -D "$WORK/download" >/dev/null || fail "couldn't download the latest published release"
ditto -x -k "$WORK/download/LF-Studios.zip" "$WORK/old"
xattr -dr com.apple.quarantine "$OLD_APP" 2>/dev/null || true
OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD_APP/Contents/Info.plist")"
[ "$OLD_VERSION" != "$VERSION" ] || fail "the latest release is already $VERSION"
echo "▶ Rehearsing the update from $OLD_VERSION to ${VERSION}…"

# The new feed, served from this Mac.
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
cp "$DIST/LF-Studios.zip" "$WORK/feed/"
sed -E "s#url=\"[^\"]*LF-Studios\\.zip\"#url=\"http://127.0.0.1:${PORT}/LF-Studios.zip\"#" "$DIST/appcast.xml" > "$WORK/feed/appcast.xml"
(cd "$WORK/feed" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER_PID=$!
for _ in $(seq 1 20); do curl -fsI "http://127.0.0.1:${PORT}/appcast.xml" >/dev/null 2>&1 && break; sleep 0.5; done

running_pid() { pgrep -f "$WORK/old/LF Studios.app/Contents/MacOS/" | head -1 || true; }
window_text() {
    osascript -e "tell application \"System Events\" to get value of every static text of every window of (first process whose unix id is $1)" 2>/dev/null || true
}

# English, so the menu and Sparkle's buttons have known names.
open -n "$OLD_APP" --args -SUFeedURL "http://127.0.0.1:${PORT}/appcast.xml" -AppleLanguages '(en)'
PID=""
for _ in $(seq 1 30); do PID="$(running_pid)"; [ -n "$PID" ] && break; sleep 1; done
[ -n "$PID" ] || fail "LF Studios $OLD_VERSION didn't open"
sleep 4
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" \
          -e "delay 0.5" \
          -e "tell application \"System Events\" to click menu item \"Check for Updates…\" of menu 1 of menu bar item 2 of menu bar 1 of (first process whose unix id is $PID)" >/dev/null \
    || fail "couldn't click LF Studios → Check for Updates…"

FOUND=false
for _ in $(seq 1 30); do
    sleep 1
    TEXT="$(window_text "$PID")"
    if [[ "$TEXT" == *"is now available"* ]]; then FOUND=true; break; fi
    if [[ "$TEXT" == *"up to date!"* || "$TEXT" == *"Update Error!"* ]]; then fail "$OLD_VERSION says: $TEXT"; fi
done
$FOUND || fail "$OLD_VERSION didn't offer the update (it showed: ${TEXT:-nothing})"
[[ "$TEXT" == *"$VERSION"* ]] || fail "the update window offers something else: $TEXT"

osascript -e "tell application \"System Events\" to click button \"Install Update\" of window \"Software Update\" of (first process whose unix id is $PID)" >/dev/null \
    || fail "couldn't click Install Update"

# Sparkle downloads, checks the signature, installs, and opens the new one.
NEW_PID=""
for _ in $(seq 1 120); do
    sleep 1
    CURRENT="$(running_pid)"
    if [ -n "$CURRENT" ] && [ "$CURRENT" != "$PID" ]; then NEW_PID="$CURRENT"; break; fi
    if [ -n "$CURRENT" ]; then
        TEXT="$(window_text "$CURRENT")"
        [[ "$TEXT" == *"Update Error!"* ]] && fail "Install Update failed: $TEXT"
    fi
done
[ -n "$NEW_PID" ] || fail "LF Studios didn't come back after Install Update (2 minutes)"
ON_DISK="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD_APP/Contents/Info.plist")"
[ "$ON_DISK" = "$VERSION" ] || fail "after the update the app is $ON_DISK, not $VERSION"
RUNNING="$(lsappinfo info -only bundlepath -app "$NEW_PID" 2>/dev/null || true)"
[[ "$RUNNING" == *"$WORK/old/LF Studios.app"* ]] || fail "the app that came back isn't the updated copy ($RUNNING)"
echo "✓ $OLD_VERSION updated itself to $VERSION through Check for Updates and opened again"
