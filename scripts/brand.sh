#!/bin/zsh
# Renders the site's icons and share image from brand/*.html with headless Chrome.
set -euo pipefail
ROOT="${0:A:h:h}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
shot() { "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size="$2" --virtual-time-budget=3000 --screenshot="$ROOT/site/$3" "file://$ROOT/brand/$1" >/dev/null 2>&1; echo "site/$3"; }
shot og.html 1200,630 og.png
shot icon.html 512,512 icon-512.png
# Chrome cannot open a window as small as 180 px, so the touch icon is scaled down from the 512 one.
sips -z 180 180 "$ROOT/site/icon-512.png" --out "$ROOT/site/apple-touch-icon.png" >/dev/null; echo "site/apple-touch-icon.png"
