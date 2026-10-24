#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ShotStyle"
# Assembled inside .build, in a .noindex folder: Spotlight skips it, so
# only the copy in /Applications shows up as an app.
APP_BUNDLE="$SCRIPT_DIR/.build/app.noindex/$APP_NAME.app"
ENTITLEMENTS="$SCRIPT_DIR/ShotStyle.entitlements"

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
if [ -n "${SHOTSTYLE_CODESIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$SHOTSTYLE_CODESIGN_IDENTITY"
elif security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
else
    SIGN_IDENTITY="-"
fi

ADHOC_WARNING='⚠ No "ShotStyle Local Signing" certificate: signing ad-hoc.
  macOS will forget the Screen Recording and Accessibility permissions on
  every rebuild (ShotStyle asks again and recording stays blocked).
  Fix it once on this Mac: bash scripts/setup-signing.sh'
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "$ADHOC_WARNING"
    echo ""
fi
TIMESTAMP_MODE="${SHOTSTYLE_CODESIGN_TIMESTAMP:-auto}"
SPARKLE_PUBLIC_ED_KEY="${SHOTSTYLE_SPARKLE_PUBLIC_ED_KEY:-}"
REQUIRE_SPARKLE_KEY="${SHOTSTYLE_REQUIRE_SPARKLE_KEY:-false}"

echo "▶ Building $APP_NAME (release)…"
cd "$SCRIPT_DIR"
swift build -c release 2>&1
BUILD_DIR="$(swift build -c release --show-bin-path)"

BINARY="$BUILD_DIR/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "✗ Build failed — binary not found at $BINARY"
    exit 1
fi

echo "▶ Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY"              "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist"
elif [[ "$REQUIRE_SPARKLE_KEY" =~ ^(1|true|yes|on)$ ]]; then
    echo "✗ SHOTSTYLE_SPARKLE_PUBLIC_ED_KEY is required when SHOTSTYLE_REQUIRE_SPARKLE_KEY=true."
    echo "  Generate it with Sparkle's generate_keys tool and keep the private key out of git."
    exit 1
else
    echo "⚠ Sparkle public key not set; update checks will be disabled in this build."
fi

# Build the icon from Branding/ShotStyle_Icon.png (1024×1024), then copy it into the bundle
ICON_PNG="$SCRIPT_DIR/Branding/ShotStyle_Icon.png"
if [ -f "$ICON_PNG" ]; then
    ICONSET="$(mktemp -d)/ShotStyle.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$SCRIPT_DIR/Branding/ShotStyle.icns"
    rm -rf "$(dirname "$ICONSET")"
fi
if [ -f "$SCRIPT_DIR/Branding/ShotStyle.icns" ]; then
    cp "$SCRIPT_DIR/Branding/ShotStyle.icns" "$APP_BUNDLE/Contents/Resources/ShotStyle.icns"
fi

if [ -f "$SCRIPT_DIR/PrivacyInfo.xcprivacy" ]; then
    cp "$SCRIPT_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
fi

if [ -f "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" ]; then
    cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"
fi

# The app's own languages (translated permission prompts). These .lproj folders
# are also how macOS knows ShotStyle is localized: it then lists ShotStyle under
# per-app languages and shows system panels in the same language. The app's
# strings live in the ShotStyleCore resource bundle (scripts/localize.py).
for lproj in "$SCRIPT_DIR"/Localization/Main/*.lproj; do
    [ -d "$lproj" ] && ditto "$lproj" "$APP_BUNDLE/Contents/Resources/$(basename "$lproj")"
done
# The app's strings, also in the main bundle: SwiftUI looks up plain
# Text("…") literals there. L("…") reads the same files from the ShotStyleCore
# resource bundle, which is also what tests see.
for lproj in "$SCRIPT_DIR"/Sources/ShotStyleCore/Resources/*.lproj; do
    [ -d "$lproj" ] && ditto "$lproj" "$APP_BUNDLE/Contents/Resources/$(basename "$lproj")"
done

# Copy SPM-generated resource bundles (capture sound, KeyboardShortcuts localizations, etc.)
while IFS= read -r bundle; do
    bundle_name="$(basename "$bundle")"
    if [ "$bundle_name" = "${APP_NAME}_${APP_NAME}.bundle" ]; then
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
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

if ! otool -L "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "@rpath/Sparkle.framework"; then
    echo "✗ Built binary is not linked against Sparkle.framework"
    exit 1
fi

if ! otool -l "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
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
        echo "✗ Invalid SHOTSTYLE_CODESIGN_TIMESTAMP: $TIMESTAMP_MODE"
        echo "  Use auto, true, or false."
        exit 1
        ;;
esac

codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"

echo "▶ Copying to /Applications…"
APPS_DEST="/Applications/$APP_NAME.app"
rm -rf "$APPS_DEST"
cp -R "$APP_BUNDLE" "$APPS_DEST"

echo ""
echo "✓ Done!  ShotStyle.app deployed to /Applications."
echo "  Launch it from /Applications."
echo ""
echo "  First launch: grant Screen Recording permission when prompted"
echo "  (System Settings → Privacy & Security → Screen Recording)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo ""
    echo "$ADHOC_WARNING"
fi
