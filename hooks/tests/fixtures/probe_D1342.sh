#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# probe_D1342.sh — коммит с обходом ловушки в ДРУГОЙ каталог (временный репозиторий) не получает отказа «коммит в main».
#
# Повод (18 ноября 2026, скептик D1326 и живой отказ в той же сессии). Команда, где коммит идёт после `cd` во временный
# репозиторий и несёт слово обхода ловушки (`GIT_CONFIG_*`), получает «коммит в main (<каталог сессии>) обходит ловушку
# git» — хотя главную ветку каталога сессии она не трогает.
# Проверка результата: bash hooks/tests/fixtures/probe_D1342.sh → 0 — такой коммит отказа не получает; 1 — получает;
#   2 — не измерено (нет jq/python3/git, либо положительный контроль не сработал: тот же обход в самом каталоге сессии
#   на main обязан получить отказ — иначе рамка не умеет отвечать «да»).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/merge-root-gate.sh"
[ -f "$HOOK" ] || { echo "нет стража — не измерено"; exit 2; }
for c in jq python3 git; do command -v "$c" >/dev/null 2>&1 || { echo "нет $c — не измерено"; exit 2; }; done
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/h" "$T/s" "$T/main"
# Каталог сессии — проект под договором долга: страж судит только такие (карта корней и бэклог в корне).
( cd "$T/main" && git init -q -b main . && printf '# ROOTS\n' > ROOTS.md && printf '# BACKLOG\n' > BACKLOG.md \
    && git add . && git -c user.email=t@t -c user.name=t commit -q -m init ) \
    || { echo "каталог сессии не собран — не измерено"; exit 2; }
verdict() {   # <команда> → deny | pass
    python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"p1342","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$T/main" \
        | ( cd "$T/main" && HOME="$T/h" STATE_DIR="$T/s" CLAUDSOUL_REPO="$REPO" CLAUDSOUL_ROOT="$REPO" bash "$HOOK" 2>/dev/null ) \
        | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null | head -1
}
ctl=$(verdict 'GIT_CONFIG_COUNT=0 git commit -qm x --allow-empty')
[ "$ctl" = deny ] || { echo "контроль: обход в каталоге сессии на main отказа не получил (${ctl:-пусто}) — не измерено"; exit 2; }
a=$(verdict 'R=$(mktemp -d); cd "$R" && git init -q . && GIT_CONFIG_COUNT=0 git commit -qm init --allow-empty')
b=$(verdict "bash -c 'R=\$(mktemp -d); cd \"\$R\" && git init -q . && GIT_CONFIG_COUNT=0 git commit -qm init --allow-empty'")
if [ "$a" = deny ] || [ "$b" = deny ]; then
    echo "коммит во временный репозиторий получил отказ «коммит в main»: после cd — ${a:-pass}, в bash -c — ${b:-pass}"
    exit 1
fi
echo "коммит во временный репозиторий отказа не получает"
exit 0
