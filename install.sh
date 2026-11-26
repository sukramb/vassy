#!/bin/zsh
# Baut die App, installiert den Hook und trägt ihn in ~/.claude/settings.json ein.
# Rückgängig: ./install.sh --uninstall
set -euo pipefail
HERE="${0:A:h}"
QUEUE="$HOME/.claude/claude-queue"
SETTINGS="$HOME/.claude/settings.json"
NODE="$(command -v node || echo /opt/homebrew/bin/node)"
HOOK_CMD="\"$NODE\" \"$QUEUE/hook.js\""

mkdir -p "$HOME/.claude/backups"
cp "$SETTINGS" "$HOME/.claude/backups/settings.json.$(date +%Y%m%d-%H%M%S)"

MODE="${1:-install}"
python3 - "$SETTINGS" "$HOOK_CMD" "$MODE" <<'PY'
import json, sys
path, cmd, mode = sys.argv[1], sys.argv[2], sys.argv[3]
s = json.load(open(path))
hooks = s.setdefault("hooks", {})
for ev in ["Stop", "Notification", "UserPromptSubmit", "SessionEnd"]:
    groups = [g for g in hooks.get(ev, []) if not any("claude-queue/hook.js" in h.get("command", "") for h in g.get("hooks", []))]
    if mode != "--uninstall":
        groups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 3}]})
    if groups: hooks[ev] = groups
    else: hooks.pop(ev, None)
json.dump(s, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
print("Hooks entfernt" if mode == "--uninstall" else "Hooks eingetragen")
PY

if [[ "$MODE" == "--uninstall" ]]; then
  pkill -x Vassy 2>/dev/null || true
  rm -rf "$HOME/Applications/Vassy.app"
  echo "Deinstalliert. Daten bleiben in $QUEUE"
  exit 0
fi

mkdir -p "$QUEUE/events"
cp "$HERE/hook/hook.js" "$QUEUE/hook.js"
"$HERE/build.sh"
open "$HOME/Applications/Vassy.app"
