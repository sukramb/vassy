#!/bin/zsh
# Builds a signed, notarized Vassy.app for distribution and zips it into dist/.
#
# One-time setup on the release Mac:
#   1. A "Developer ID Application" certificate in the keychain
#      (Xcode › Settings › Accounts › Manage Certificates › +).
#   2. Notarization credentials stored under the profile name "vassy":
#      xcrun notarytool store-credentials vassy
#
#   scripts/release.sh            sign with the only Developer ID identity found
#   VASSY_SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh
set -euo pipefail
ROOT="${0:A:h:h}"
DIST="$ROOT/dist"
APP="$DIST/Vassy.app"
ZIP="$DIST/Vassy.zip"
PROFILE="${VASSY_NOTARY_PROFILE:-vassy}"

IDENTITY="${VASSY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate found in the keychain." >&2; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"
VASSY_APP="$APP" VASSY_ARCHS="arm64 x86_64" VASSY_SIGN_IDENTITY="$IDENTITY" "$ROOT/build.sh"
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"   # zip again so the download carries the stapled ticket
spctl --assess --type execute --verbose=2 "$APP"
echo "Release ready: $ZIP"
