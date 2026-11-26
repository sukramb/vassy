#!/bin/zsh
# Builds Vassy from source and registers its hook with the coding agents you use.
#
#   ./install.sh                        ask which agents to watch (detected ones preselected)
#   ./install.sh --agents claude,codex  no questions
#   ./install.sh --uninstall            remove the app and every hook entry; data stays in ~/.vassy
#
# Every config file is backed up to ~/.vassy/backups before it is changed.
set -euo pipefail
HERE="${0:A:h}"
APP="$HOME/Applications/Vassy.app"
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

if [[ "$MODE" == uninstall ]]; then
  [[ -x "$APP/Contents/MacOS/Vassy" ]] || "$HERE/build.sh"
  "$APP/Contents/MacOS/Vassy" --uninstall
  pkill -x Vassy 2>/dev/null || true
  rm -rf "$APP" "$HOME/.vassy/hook"
  echo "Uninstalled. Your data is still in ~/.vassy"
  exit 0
fi

installed() { command -v "$1" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/$1" ]]; }

AGENTS=()
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

"$HERE/build.sh"
"$APP/Contents/MacOS/Vassy" --setup "${(j:,:)AGENTS}"
open "$APP"

if (( ${AGENTS[(Ie)codex]} )); then
  echo
  echo "One more step for Codex: it only runs hooks you have approved."
  echo "Start codex, type /hooks and trust the Vassy entries."
fi
