#!/bin/zsh
# Builds the menu bar app into ~/Applications/Vassy.app (ad-hoc signed, for this Mac).
# scripts/release.sh reuses it with VASSY_APP, VASSY_ARCHS and VASSY_SIGN_IDENTITY set.
set -euo pipefail
HERE="${0:A:h}"
cd "$HERE"
ARCHS=(${=VASSY_ARCHS:-})
FLAGS=(-c release ${ARCHS:+${ARCHS/#/--arch=}})
swift build $FLAGS 2>&1 | grep -vE "^\[|Compiling|Building" || true
(( ${pipestatus[1]} == 0 )) || { echo "Build failed." >&2; exit 1; }
PRODUCTS="$(swift build $FLAGS --show-bin-path)"
BIN="$PRODUCTS/Vassy"
# Where the app looks for updates. Only a local test build overrides this.
FEED="${VASSY_FEED_URL:-https://www.vassy.app/appcast.xml}"
LOCAL_FEED=""
[[ "$FEED" == http://127.0.0.1:* ]] && LOCAL_FEED="  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>"
APP="${VASSY_APP:-$HOME/Applications/Vassy.app}"
IDENTITY="${VASSY_SIGN_IDENTITY:--}"
VERSION="$(<"$HERE/VERSION")"
[[ "$APP" == */Vassy.app ]] || { echo "Refusing to build into $APP: the path must end in /Vassy.app" >&2; exit 1; }
[[ -n "${VASSY_APP:-}" ]] || pkill -x Vassy 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Vassy"
mkdir -p "$APP/Contents/Resources" && cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Sparkle installs the updates. The binary finds it through an rpath into Frameworks.
mkdir -p "$APP/Contents/Frameworks" && ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Vassy" 2>/dev/null
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Vassy</string>
  <key>CFBundleDisplayName</key><string>Vassy</string>
  <key>CFBundleIdentifier</key><string>local.vassy.menubar</string>
  <key>CFBundleExecutable</key><string>Vassy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>SUFeedURL</key><string>$FEED</string>
  <key>SUPublicEDKey</key><string>Okyb5LbmjeFWWiumZTb36/9xUhAgkUqVOInByOhUjVY=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUScheduledCheckInterval</key><integer>21600</integer>
$LOCAL_FEED
  <key>NSAppleEventsUsageDescription</key><string>Vassy types your answers into the right Terminal tab and brings it to the front.</string>
</dict></plist>
PLIST
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$SPARKLE" >/dev/null 2>&1
  codesign --force --sign - "$APP" >/dev/null
else
  # Developer ID: hardened runtime and a secure timestamp are required for notarization.
  # Sparkle's helpers are signed from the inside out, then the framework, then the app.
  SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
  $SIGN "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  $SIGN --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  $SIGN "$SPARKLE/Versions/B/Autoupdate"
  $SIGN "$SPARKLE/Versions/B/Updater.app"
  $SIGN "$SPARKLE"
  $SIGN --entitlements "$HERE/Vassy.entitlements" "$APP"
fi
echo "Done: $APP"
