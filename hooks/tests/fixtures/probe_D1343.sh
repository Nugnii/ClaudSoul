#!/usr/bin/env bash
# СУДИТ: hooks/secret-guard.sh
# probe_D1343.sh — страж записи читает текст правки и тогда, когда поля входа Edit зовутся `old_str`/`new_str`.
#
# Повод (19 ноября 2026, скептик D1329): у 79 настоящих правок соседнего проекта вход Edit несёт `old_str`/`new_str`,
# а стражи записи читают только `new_string` — текст такой правки для них пуст. Представитель — страж секретов.
# Проверка результата: bash hooks/tests/fixtures/probe_D1343.sh → 0 — секрет в `new_str` получает отказ; 1 — проходит;
#   2 — не измерено (нет стража или jq, либо положительный контроль не сработал: тот же секрет в `new_string` обязан
#   получить отказ — иначе рамка не умеет отвечать «да»).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/secret-guard.sh"
[ -f "$HOOK" ] || { echo "нет стража — не измерено"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "нет jq — не измерено"; exit 2; }
T=$(mktemp -d) || exit 2
KEY="AKIA""3KJH2LK4J5HG6PQR"   # образец из test_secret_guard.sh, склеен, чтобы файл пробы сам не был находкой
verdict() {   # <имя поля> → deny | ask | -
    jq -n --arg s "AWS = \"$KEY\"" --arg k "$1" '{tool_name:"Edit", tool_input:({file_path:"/tmp/a.py"} + {($k):$s})}' \
        | HOME="$T" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "-"' 2>/dev/null | head -1
}
ctl=$(verdict new_string)
[ "$ctl" = deny ] || { echo "контроль: секрет в new_string отказа не получил (${ctl:-пусто}) — не измерено"; exit 2; }
got=$(verdict new_str)
[ "$got" = deny ] || { echo "секрет в new_str проходит (${got:-пусто})"; exit 1; }
echo "секрет в new_str получает отказ"
exit 0
