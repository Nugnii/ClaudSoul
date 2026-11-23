#!/usr/bin/env bash
# СУДИТ: hooks/pending-alerts-surface.sh
# probe_D1344.sh — одна и та же строка о проекте, сказанная несколькими сессиями, показывается в сообщении один раз.
# Проверка результата: bash hooks/tests/fixtures/probe_D1344.sh → 0 — копия одна; 1 — копий больше одной;
#   2 — не измерено (нет jq, нет хука, раздел о проекте не напечатан).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$REPO/hooks/pending-alerts-surface.sh"
[ -f "$H" ] || { echo "нет хука показа — не измерено"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "нет jq — не измерено"; exit 2; }
W=$(mktemp -d) || { echo "нет временного каталога — не измерено"; exit 2; }
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home/.claude/hooks/state" "$W/proj"
P=$(cd "$W/proj" && pwd -P)
F="$W/home/.claude/hooks/state/project-signals-$(printf '%s' "$P" | cksum | awk '{print $1}').txt"
L='📋 Залежавшийся пункт ждёт очереди: BACKLOG.md:D9001 (проба D1344)'
printf '%s\n%s\n%s\n' "$L" "$L" '📋 Другая строка о проекте (проба D1344)' > "$F"
out=$(jq -cn --arg cwd "$P" '{cwd: $cwd, session_id: "probe-d1344", hook_event_name: "UserPromptSubmit", prompt: "x"}' \
      | HOME="$W/home" CLAUDSOUL_STATE_DIR="$W/home/.claude/hooks/state" bash "$H" 2>/dev/null \
      | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
# Положительный контроль: раздел о проекте напечатан, и вторая, непохожая строка в нём есть — иначе счёт копий
# первой ничего не значит (пустой вывод дал бы «0 копий»).
grep -q 'Другая строка о проекте' <<< "$out" || { echo "раздел о проекте не напечатан — не измерено"; exit 2; }
n=$(grep -c 'BACKLOG.md:D9001' <<< "$out")
[ "$n" -eq 1 ] && { echo "одинаковая строка показана один раз"; exit 0; }
echo "одинаковая строка показана $n раз(а)"
exit 1
