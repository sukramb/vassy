#!/bin/zsh
# Builds Vassy, installs its hook and registers it with the coding agents you use.
#
#   ./install.sh                        ask which agents to watch (detected ones preselected)
#   ./install.sh --agents claude,codex  no questions
#   ./install.sh --uninstall            remove the app and every hook entry; data stays in ~/.vassy
#
# Every config file is backed up to ~/.vassy/backups before it is changed.
set -euo pipefail
HERE="${0:A:h}"
BASE="$HOME/.vassy"
NODE="$(command -v node || echo /opt/homebrew/bin/node)"
KNOWN=(claude codex)
typeset -A LABEL=(claude "Claude Code" codex "Codex")

MODE=install
PICKED=""
while (( $# )); do
  case "$1" in
    --uninstall) MODE=uninstall ;;
    --agents) PICKED="${2:-}"; shift ;;
    --agents=*) PICKED="${1#--agents=}" ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

installed() { command -v "$1" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/$1" ]]; }

AGENTS=()
if [[ "$MODE" == install ]]; then
  if [[ -n "$PICKED" ]]; then
    for a in ${(s:,:)PICKED}; do
      (( ${KNOWN[(Ie)$a]} )) || { echo "Unknown agent: $a (known: ${KNOWN[*]})" >&2; exit 2; }
      AGENTS+=("$a")
    done
  else
    [[ -t 0 ]] && echo "Which coding agents should Vassy watch?"
    for a in $KNOWN; do
      if installed "$a"; then default=y; hint="found"; else default=n; hint="not found"; fi
      answer="$default"
      if [[ -t 0 ]]; then
        read "reply?  ${LABEL[$a]} (${hint}) [$([[ $default == y ]] && echo Y/n || echo y/N)] "
        answer="${reply:-$default}"
      fi
      [[ "${answer:l}" == y* ]] && AGENTS+=("$a")
    done
  fi
  (( ${#AGENTS} )) || { echo "No agent selected, nothing to do." >&2; exit 1; }
  command -v "$NODE" >/dev/null 2>&1 || { echo "Node.js is required for the hook but was not found." >&2; exit 1; }
fi

mkdir -p "$BASE/backups" "$BASE/events"

# Adds or removes Vassy's hook entries in each agent's config and writes ~/.vassy/config.json.
python3 - "$BASE" "$NODE" "${CODEX_HOME:-$HOME/.codex}" "${(j:,:)AGENTS}" <<'PY'
import json, os, shutil, sys, time
base, node, codex_home, picked = sys.argv[1], sys.argv[2], sys.argv[3], [a for a in sys.argv[4].split(",") if a]
home = os.path.expanduser("~")
targets = {
    "claude": (os.path.join(home, ".claude", "settings.json"),
               ["Stop", "Notification", "UserPromptSubmit", "SessionEnd"]),
    "codex": (os.path.join(codex_home, "hooks.json"),
              ["Stop", "PermissionRequest", "UserPromptSubmit", "PostToolUse", "SessionEnd"]),
}
marker = ".vassy/hook.js"
stamp = time.strftime("%Y%m%d-%H%M%S")

for agent, (path, events) in targets.items():
    wanted = agent in picked
    if not os.path.exists(path):
        if not wanted or not os.path.isdir(os.path.dirname(path)):
            if wanted: print(f"  {agent}: {os.path.dirname(path)} not found, skipped")
            continue
        config = {}
    else:
        with open(path) as f: config = json.load(f)
        shutil.copy2(path, os.path.join(base, "backups", f"{agent}-{os.path.basename(path)}.{stamp}"))
    hooks = config.setdefault("hooks", {})
    before = json.dumps(hooks, sort_keys=True)
    for event in list(hooks):
        kept = [g for g in hooks[event] if not any(marker in h.get("command", "") for h in g.get("hooks", []))]
        if kept: hooks[event] = kept
        else: del hooks[event]
    if wanted:
        command = f'"{node}" "{os.path.join(base, "hook.js")}" {agent}'
        for event in events:
            hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": command, "timeout": 3}]})
    if json.dumps(hooks, sort_keys=True) != before:
        with open(path, "w") as f:
            json.dump(config, f, indent=2, ensure_ascii=False); f.write("\n")
        print(f"  {agent}: hooks {'registered' if wanted else 'removed'} in {path}")

if picked:
    path = os.path.join(base, "config.json")
    try:
        with open(path) as f: config = json.load(f)
    except (OSError, ValueError): config = {}
    config["agents"] = picked
    with open(path, "w") as f:
        json.dump(config, f, indent=2); f.write("\n")
PY

if [[ "$MODE" == uninstall ]]; then
  pkill -x Vassy 2>/dev/null || true
  rm -rf "$HOME/Applications/Vassy.app"
  echo "Uninstalled. Your data is still in $BASE"
  exit 0
fi

cp "$HERE/hook/hook.js" "$BASE/hook.js"
"$HERE/build.sh"
open "$HOME/Applications/Vassy.app"

if (( ${AGENTS[(Ie)codex]} )); then
  echo
  echo "One more step for Codex: it only runs hooks you have approved."
  echo "Start codex, type /hooks and trust the Vassy entries."
fi
