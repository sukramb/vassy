#!/bin/zsh
# Builds the menu bar app into ~/Applications/Vassy.app (ad-hoc signed, for this Mac).
# scripts/release.sh reuses it with VASSY_APP, VASSY_ARCHS and VASSY_SIGN_IDENTITY set.
set -euo pipefail
HERE="${0:A:h}"
cd "$HERE"
ARCHS=(${=VASSY_ARCHS:-})
FLAGS=(-c release ${ARCHS:+${ARCHS/#/--arch=}})
swift build $FLAGS 2>&1 | grep -vE "^\[|Compiling|Building" || true
BIN="$(swift build $FLAGS --show-bin-path)/Vassy"
APP="${VASSY_APP:-$HOME/Applications/Vassy.app}"
IDENTITY="${VASSY_SIGN_IDENTITY:--}"
[[ -n "${VASSY_APP:-}" ]] || pkill -x Vassy 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Vassy"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Vassy</string>
  <key>CFBundleDisplayName</key><string>Vassy</string>
  <key>CFBundleIdentifier</key><string>local.vassy.menubar</string>
  <key>CFBundleExecutable</key><string>Vassy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Vassy types your answers into the right Terminal tab and brings it to the front.</string>
</dict></plist>
PLIST
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP" >/dev/null
else
  # Developer ID: hardened runtime and a secure timestamp are required for notarization.
  codesign --force --options runtime --timestamp --entitlements "$HERE/Vassy.entitlements" --sign "$IDENTITY" "$APP"
fi
echo "Done: $APP"
