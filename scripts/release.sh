#!/bin/zsh
# Builds a signed, notarized Vassy.app for distribution and zips it into dist/.
#
# One-time setup on the release Mac:
#   1. A "Developer ID Application" certificate in the keychain
#      (Xcode › Settings › Accounts › Manage Certificates › +).
#   2. Notarization credentials stored under the profile name "vassy":
#      xcrun notarytool store-credentials vassy
#   3. The key that signs updates, in the login keychain under the account "vassy":
#      .build/artifacts/sparkle/Sparkle/bin/generate_keys --account vassy
#      Its public half is in build.sh (SUPublicEDKey). Keep a backup of the private key
#      (generate_keys --account vassy -x <file>): without it no installed app accepts an update.
#
#   scripts/release.sh            sign with the only Developer ID identity found
#   VASSY_SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh
set -euo pipefail
ROOT="${0:A:h:h}"
DIST="$ROOT/dist"
APP="$DIST/Vassy.app"
ZIP="$DIST/Vassy.zip"
PROFILE="${VASSY_NOTARY_PROFILE:-vassy}"

SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -z "${VASSY_FEED_URL:-}" ]] || { echo "VASSY_FEED_URL is for local test builds only; unset it for a release." >&2; exit 1; }

IDENTITY="${VASSY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate found in the keychain." >&2; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"
VASSY_APP="$APP" VASSY_ARCHS="arm64 x86_64" VASSY_SIGN_IDENTITY="$IDENTITY" "$ROOT/build.sh"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
# Zip again so the download carries the stapled ticket. Without extended attributes, so
# that plain `unzip` gives a valid app too.
rm "$ZIP"; ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"

VERSION="$(<"$ROOT/VERSION")"
# Installed apps read appcast.xml, download the zip and check this signature before installing.
[[ -x "$SIGN_UPDATE" ]] || swift package --package-path "$ROOT" resolve
SIGNATURE="$("$SIGN_UPDATE" --account vassy "$ZIP")"
[[ "$SIGNATURE" == sparkle:edSignature=* ]] || { echo "Could not sign the update: $SIGNATURE" >&2; exit 1; }
cat > "$ROOT/site/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Vassy</title>
    <link>https://vassy.app</link>
    <item>
      <title>Vassy $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="https://www.vassy.app/download/Vassy.zip" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
# Versions before 1.1 only read version.json and show a link to the download.
print -r -- "{\"version\": \"$VERSION\"}" > "$ROOT/site/version.json"
mkdir -p "$ROOT/site/download" && cp "$ZIP" "$ROOT/site/download/Vassy.zip"   # served at vassy.app/download/Vassy.zip
echo "Release ready: $ZIP (copied to site/download with appcast.xml; commit and push to publish)"
