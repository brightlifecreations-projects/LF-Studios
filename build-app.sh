#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Options: --universal builds one app for Apple Silicon and Intel Macs (the
# same as LFSTUDIOS_UNIVERSAL=true); --no-install leaves it in
# .build/app.noindex (LFSTUDIOS_INSTALL=false).
for arg in "$@"; do
    case "$arg" in
        --universal) LFSTUDIOS_UNIVERSAL=true ;;
        --no-install) LFSTUDIOS_INSTALL=false ;;
        -h|--help)
            echo "Usage: bash build-app.sh [--universal] [--no-install]"
            echo "  --universal   one app for Apple Silicon and Intel Macs"
            echo "  --no-install  leave the app in .build/app.noindex"
            exit 0 ;;
        *) echo "✗ Unknown option: $arg (see --help)"; exit 2 ;;
    esac
done
# The app as people see it ("LF Studios.app") and the Swift product and
# executable inside it (no space).
APP_NAME="LF Studios"
PRODUCT="LFStudios"
# Assembled inside .build, in a .noindex folder: Spotlight skips it, so
# only the copy in /Applications shows up as an app.
APP_BUNDLE="$SCRIPT_DIR/.build/app.noindex/$APP_NAME.app"
ENTITLEMENTS="$SCRIPT_DIR/LFStudios.entitlements"

if [ -f "$SCRIPT_DIR/.env.local" ]; then
    set -a
    source "$SCRIPT_DIR/.env.local"
    set +a
fi

# Default: the "ShotStyle Local Signing" certificate when the keychain has
# one, else "-" (ad-hoc, no certificate needed). Ad-hoc builds get a new
# identity on every build, so macOS forgets the Screen Recording and
# Accessibility permissions each time; a fixed local certificate keeps them.
LOCAL_IDENTITY="ShotStyle Local Signing"
if [ -n "${LFSTUDIOS_CODESIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$LFSTUDIOS_CODESIGN_IDENTITY"
elif security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
else
    SIGN_IDENTITY="-"
fi

ADHOC_WARNING='⚠ No "ShotStyle Local Signing" certificate: signing ad-hoc.
  macOS will forget the Screen Recording and Accessibility permissions on
  every rebuild (LF Studios asks again and recording stays blocked).
  Fix it once on this Mac: bash scripts/setup-signing.sh'
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "$ADHOC_WARNING"
    echo ""
fi
TIMESTAMP_MODE="${LFSTUDIOS_CODESIGN_TIMESTAMP:-auto}"
SPARKLE_PUBLIC_ED_KEY="${LFSTUDIOS_SPARKLE_PUBLIC_ED_KEY:-}"
REQUIRE_SPARKLE_KEY="${LFSTUDIOS_REQUIRE_SPARKLE_KEY:-false}"
# LFSTUDIOS_UNIVERSAL=true builds for Apple Silicon and Intel (the release
# workflow does this); the default builds for this Mac only.
UNIVERSAL="${LFSTUDIOS_UNIVERSAL:-false}"
# LFSTUDIOS_INSTALL=false leaves the app in .build/app.noindex instead of
# copying it to /Applications.
INSTALL="${LFSTUDIOS_INSTALL:-true}"

cd "$SCRIPT_DIR"

# With only the Command Line Tools, the newest SDK can need macro plugins
# (SwiftUIMacros) that only full Xcode ships. Then the build is retried with
# an installed macOS 26 SDK; if none works, it says to install Xcode.
BUILD_LOG="$SCRIPT_DIR/.build/build-app.log"
mkdir -p "$SCRIPT_DIR/.build"

macro_failure() {
    grep -qE "SwiftUIMacros|PreviewsMacros|external macro implementation|plugin for module '.*Macros'" "$BUILD_LOG"
}

# Other macOS 26 SDKs installed with the Command Line Tools, newest first,
# skipping the one that just failed.
fallback_sdks() {
    local current
    current="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    for dir in "$(xcode-select -p 2>/dev/null)/SDKs" /Library/Developer/CommandLineTools/SDKs; do
        [ -d "$dir" ] || continue
        ls -d "$dir"/MacOSX26*.sdk 2>/dev/null | sort -rV
    done | while read -r sdk; do
        [ "$(cd "$sdk" && pwd -P)" = "$(cd "$current" 2>/dev/null && pwd -P)" ] || echo "$sdk"
    done | awk '!seen[$0]++'
}

no_sdk_works() {
    echo ""
    echo "✗ LF Studios can't be built with the tools on this Mac."
    echo "  The macOS SDK needs the macro plugins that come with full Xcode."
    echo "  Install Xcode from the App Store, open it once, then run:"
    echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  and build again with: bash build-app.sh"
    exit 1
}

# swift build "$@", retried with another macOS 26 SDK after a macro failure.
release_build() {
    if swift build -c release "$@" 2>&1 | tee "$BUILD_LOG"; [ "${PIPESTATUS[0]}" -eq 0 ]; then
        return 0
    fi
    macro_failure || exit 1
    if [ -n "${SDKROOT:-}" ]; then no_sdk_works; fi
    while read -r sdk; do
        [ -n "$sdk" ] || continue
        echo ""
        echo "▶ The newest SDK needs Xcode's macro plugins — trying $(basename "$sdk")…"
        if SDKROOT="$sdk" swift build -c release "$@" 2>&1 | tee "$BUILD_LOG"; [ "${PIPESTATUS[0]}" -eq 0 ]; then
            # Every later build (the other architecture, --show-bin-path)
            # uses the same SDK.
            export SDKROOT="$sdk"
            return 0
        fi
        macro_failure || exit 1
    done < <(fallback_sdks)
    no_sdk_works
}

if [[ "$UNIVERSAL" =~ ^(1|true|yes|on)$ ]]; then
    # One build per architecture, then lipo: a single --arch keeps SwiftPM's
    # usual build layout, so resource bundles and Sparkle are the same as in
    # a normal build (two --arch flags at once switch to a different builder).
    ARCH_BINARIES=()
    BUILD_DIR=""
    for arch in arm64 x86_64; do
        echo "▶ Building $APP_NAME (release, $arch)…"
        release_build --arch "$arch"
        ARCH_DIR="$(swift build -c release --arch "$arch" --show-bin-path)"
        if [ ! -f "$ARCH_DIR/$PRODUCT" ]; then
            echo "✗ Build failed — binary not found at $ARCH_DIR/$PRODUCT"
            exit 1
        fi
        # Copied aside right away: newer SwiftPM builds every architecture
        # into the same Products folder, so the next build overwrites it.
        mkdir -p "$SCRIPT_DIR/.build/universal"
        cp "$ARCH_DIR/$PRODUCT" "$SCRIPT_DIR/.build/universal/$PRODUCT-$arch"
        ARCH_BINARIES+=("$SCRIPT_DIR/.build/universal/$PRODUCT-$arch")
        # Resource bundles and Sparkle.framework come from the first build.
        [ -n "$BUILD_DIR" ] || BUILD_DIR="$ARCH_DIR"
    done
    BINARY="$SCRIPT_DIR/.build/universal/$PRODUCT"
    lipo -create "${ARCH_BINARIES[@]}" -output "$BINARY"
    ARCHS="$(lipo -archs "$BINARY")"
    echo "  Architectures: $ARCHS"
    if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
        echo "✗ The universal binary is missing an architecture ($ARCHS)"
        exit 1
    fi
else
    echo "▶ Building $APP_NAME (release)…"
    release_build
    BUILD_DIR="$(swift build -c release --show-bin-path)"
    BINARY="$BUILD_DIR/$PRODUCT"
fi

if [ ! -f "$BINARY" ]; then
    echo "✗ Build failed — binary not found at $BINARY"
    exit 1
fi

echo "▶ Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY"              "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist"
elif [[ "$REQUIRE_SPARKLE_KEY" =~ ^(1|true|yes|on)$ ]]; then
    echo "✗ LFSTUDIOS_SPARKLE_PUBLIC_ED_KEY is required when LFSTUDIOS_REQUIRE_SPARKLE_KEY=true."
    echo "  Generate it with Sparkle's generate_keys tool and keep the private key out of git."
    exit 1
else
    echo "⚠ Sparkle public key not set; update checks will be disabled in this build."
fi

# Build the icon from Branding/LFStudios_Icon.png (1024×1024), then copy it into the bundle
ICON_PNG="$SCRIPT_DIR/Branding/LFStudios_Icon.png"
if [ -f "$ICON_PNG" ]; then
    ICONSET="$(mktemp -d)/$PRODUCT.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$SCRIPT_DIR/Branding/$PRODUCT.icns"
    rm -rf "$(dirname "$ICONSET")"
fi
if [ -f "$SCRIPT_DIR/Branding/$PRODUCT.icns" ]; then
    cp "$SCRIPT_DIR/Branding/$PRODUCT.icns" "$APP_BUNDLE/Contents/Resources/$PRODUCT.icns"
fi

if [ -f "$SCRIPT_DIR/PrivacyInfo.xcprivacy" ]; then
    cp "$SCRIPT_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
fi

if [ -f "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" ]; then
    cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"
fi

# The app's own languages (translated permission prompts). These .lproj folders
# are also how macOS knows LF Studios is localized: it then lists LF Studios under
# per-app languages and shows system panels in the same language. The app's
# strings live in the LFStudiosCore resource bundle (scripts/localize.py).
for lproj in "$SCRIPT_DIR"/Localization/Main/*.lproj; do
    [ -d "$lproj" ] && ditto "$lproj" "$APP_BUNDLE/Contents/Resources/$(basename "$lproj")"
done
# The app's strings, also in the main bundle: SwiftUI looks up plain
# Text("…") literals there. L("…") reads the same files from the LFStudiosCore
# resource bundle, which is also what tests see.
for lproj in "$SCRIPT_DIR"/Sources/LFStudiosCore/Resources/*.lproj; do
    [ -d "$lproj" ] && ditto "$lproj" "$APP_BUNDLE/Contents/Resources/$(basename "$lproj")"
done

# Copy SPM-generated resource bundles (capture sound, KeyboardShortcuts localizations, etc.)
while IFS= read -r bundle; do
    bundle_name="$(basename "$bundle")"
    if [ "$bundle_name" = "${PRODUCT}_${PRODUCT}.bundle" ]; then
        continue
    fi
    ditto "$bundle" "$APP_BUNDLE/Contents/Resources/$bundle_name"
done < <(find "$BUILD_DIR" -maxdepth 1 -type d -name "*.bundle" -print)

SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "✗ Sparkle.framework not found at $SPARKLE_FRAMEWORK"
    exit 1
fi

echo "▶ Embedding Sparkle.framework…"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$PRODUCT" 2>/dev/null || true

if ! otool -L "$APP_BUNDLE/Contents/MacOS/$PRODUCT" | grep -q "@rpath/Sparkle.framework"; then
    echo "✗ Built binary is not linked against Sparkle.framework"
    exit 1
fi

if ! otool -l "$APP_BUNDLE/Contents/MacOS/$PRODUCT" | grep -q "@executable_path/../Frameworks"; then
    echo "✗ Built binary is missing @executable_path/../Frameworks rpath"
    exit 1
fi

echo "Signing with $SIGN_IDENTITY..."
if [ "$SIGN_IDENTITY" = "-" ] || [ "$SIGN_IDENTITY" = "$LOCAL_IDENTITY" ]; then
    # Local build (ad-hoc or the local certificate, neither has a Team ID):
    # re-sign Sparkle with the same signature and skip the hardened runtime,
    # whose library validation rejects mixed signatures (the app would crash
    # at launch with "different Team IDs").
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
else
    SIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS")
fi

case "$TIMESTAMP_MODE" in
    1|true|yes|on)
        SIGN_ARGS+=(--timestamp)
        ;;
    0|false|no|off|none)
        ;;
    auto)
        if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
            SIGN_ARGS+=(--timestamp)
        fi
        ;;
    *)
        echo "✗ Invalid LFSTUDIOS_CODESIGN_TIMESTAMP: $TIMESTAMP_MODE"
        echo "  Use auto, true, or false."
        exit 1
        ;;
esac

codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"

if [[ ! "$INSTALL" =~ ^(1|true|yes|on)$ ]]; then
    echo ""
    echo "✓ Done!  LF Studios.app is at $APP_BUNDLE"
    exit 0
fi

APPS_DEST="/Applications/$APP_NAME.app"
# Replacing a running app's files breaks it until it's quit: its next
# Check for Updates says "An error occurred while launching the installer".
# Quit it the normal way first (it saves, and says if it's busy), and open
# the new one after.
REOPEN=false
if pgrep -f "$APPS_DEST/Contents/MacOS/" >/dev/null; then
    echo "▶ Quitting LF Studios to replace it…"
    osascript -e 'tell application id "com.lfstudios.app" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do pgrep -f "$APPS_DEST/Contents/MacOS/" >/dev/null || break; sleep 1; done
    if pgrep -f "$APPS_DEST/Contents/MacOS/" >/dev/null; then
        echo "✗ LF Studios is still open (a recording or export running?). Quit it, then run this again."
        echo "  The new build is at $APP_BUNDLE"
        exit 1
    fi
    REOPEN=true
fi

echo "▶ Copying to /Applications…"
rm -rf "$APPS_DEST"
cp -R "$APP_BUNDLE" "$APPS_DEST"
if $REOPEN; then open "$APPS_DEST"; fi

echo ""
echo "✓ Done!  LF Studios.app deployed to /Applications."
echo "  Launch it from /Applications."
echo ""
echo "  First launch: grant Screen Recording permission when prompted"
echo "  (System Settings → Privacy & Security → Screen Recording)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo ""
    echo "$ADHOC_WARNING"
fi
