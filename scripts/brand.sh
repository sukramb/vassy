#!/bin/zsh
# Renders the site's icons, the share image and the macOS app icon from brand/*.html with headless Chrome.
set -euo pipefail
ROOT="${0:A:h:h}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
shot() { "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size="$2" --virtual-time-budget=3000 --screenshot="$ROOT/site/$3" "file://$ROOT/brand/$1" >/dev/null 2>&1; echo "site/$3"; }
shot og.html 1200,630 og.png
shot icon.html 512,512 icon-512.png
# Buy Me a Coffee cover: 1600x400 rendered at 2x. Not part of the site, kept in brand/export.
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1600,400 --virtual-time-budget=3000 --screenshot="$ROOT/brand/export/bmc-cover.png" "file://$ROOT/brand/bmc-cover.html" >/dev/null 2>&1; echo "brand/export/bmc-cover.png"
# Chrome cannot open a window as small as 180 px, so the touch icon is scaled down from the 512 one.
sips -z 180 180 "$ROOT/site/icon-512.png" --out "$ROOT/site/apple-touch-icon.png" >/dev/null; echo "site/apple-touch-icon.png"

# macOS app icon: a transparent 1024 px render, scaled into an .icns that build.sh puts in the bundle.
TMP="$(mktemp -d)"; SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --default-background-color=00000000 --window-size=1024,1024 --virtual-time-budget=3000 --screenshot="$TMP/1024.png" "file://$ROOT/brand/appicon.html" >/dev/null 2>&1
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"; rm -rf "$TMP"; echo "Resources/AppIcon.icns"
