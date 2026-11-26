#!/bin/zsh
# Builds the menu bar app into ~/Applications/Vassy.app
set -euo pipefail
HERE="${0:A:h}"
cd "$HERE"
swift build -c release 2>&1 | grep -vE "^\[|Compiling|Building" || true
BIN="$(swift build -c release --show-bin-path)/Vassy"
APP="$HOME/Applications/Vassy.app"
pkill -x Vassy 2>/dev/null || true
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
  <key>NSAppleEventsUsageDescription</key><string>Vassy schickt deine Antworten in den richtigen Terminal-Tab und holt ihn nach vorne.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Done: $APP"
