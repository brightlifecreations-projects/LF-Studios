#!/bin/bash
# One-time setup on each Mac that builds ShotStyle.
#
#   bash scripts/setup-signing.sh
#
# Creates a self-signed code-signing certificate, "ShotStyle Local Signing",
# in your login keychain. build-app.sh signs with it automatically, so every
# build keeps the same identity and macOS remembers the Screen Recording and
# Accessibility permissions you grant. Without it, builds are signed ad-hoc:
# each one looks like a new app to macOS, which asks for the permissions
# again and blocks recording until you grant them to the new build.
#
# The certificate stays on this Mac: its private key is made here and
# imported straight into your keychain (nothing is written to the repo).
# It's only good for signing your own local builds, not for distributing the
# app. Remove it any time in Keychain Access.
#
# Optional: SHOTSTYLE_SIGNING_KEYCHAIN=/path/to.keychain-db puts it in
# another keychain instead (used to test this script).
set -euo pipefail

NAME="ShotStyle Local Signing"
KEYCHAIN="${SHOTSTYLE_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
# The system LibreSSL: a Homebrew OpenSSL 3 writes .p12 files that macOS's
# `security import` can't read without extra flags.
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ \"$NAME\" is already in your keychain. Nothing to do."
    echo "  Build with: bash build-app.sh"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Only protects the temporary .p12 between the two commands below.
PASSWORD="$("$OPENSSL" rand -hex 16)"

echo "▶ Creating the \"$NAME\" certificate…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
"$OPENSSL" pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

echo "▶ Adding it to $(basename "$KEYCHAIN")…"
# -T: codesign may use the key without asking for your password each build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

if ! security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✗ The certificate didn't show up in $KEYCHAIN."
    exit 1
fi

cat <<EOF
✓ Done. Keychain Access lists it as "not trusted": that's expected for a
  self-signed certificate and doesn't stop it from signing.

Next:
  1. bash build-app.sh        (now signs with "$NAME")
  2. Open ShotStyle and allow Screen Recording and Accessibility when asked,
     then quit and reopen it once. From now on, rebuilds keep them.

If ShotStyle keeps asking (permissions left over from earlier ad-hoc builds):
  tccutil reset ScreenCapture com.shotstyle.app
  tccutil reset Accessibility com.shotstyle.app
EOF
