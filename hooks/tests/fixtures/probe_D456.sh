#!/usr/bin/env bash
# СУДИТ: hooks/output-language-check.sh hooks/relative-date-check.sh
# probe_D456.sh — проба пункта D456: вызов СУБАГЕНТА гасил очередь находок РОДИТЕЛЯ.
#                 `surface_pending` не только показывает находку, но и переводит её из
#                 `pending` в `surfaced`; очередь ключуется `session_id`, общим у родителя и
#                 субагента, — значит находка о речи родителя показывалась субагенту (не тому
#                 адресату) и для родителя пропадала безвозвратно.
# Результат: вызов субагента чужую очередь не показывает и НЕ расходует; вызов родителя
#            показывает и гасит, как прежде. Три носителя: output-language-check,
#            relative-date-check, fix-level-check.
# Проверка результата: bash hooks/tests/fixtures/probe_D456.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
command -v jq >/dev/null 2>&1 || { echo "probe_D456: нет jq" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D456: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

# Носитель: имя хука, имя файла очереди, поле находки.
check_one() {  # check_one <хук> <файл-очереди> <поле>
    local hook="$MECH/hooks/$1.sh" name="$2" field="$3"
    [ -f "$hook" ] || { echo "probe_D456: нет $hook" >&2; return 2; }
    local st="$T/st-$1"; mkdir -p "$st"
    local sid="s1"; local f="$st/${name}-${sid}.jsonl"
    seed() { jq -cn --arg s "$sid" --arg v "смешанноеword" --arg fl "$field" \
        '{ts:"2026-09-18T00:00:00Z", sid:$s, event:"Stop", status:"pending"} + {($fl): $v}' > "$f"; }
    pending_count() { jq -r 'select(.status=="pending") | .status' "$f" 2>/dev/null | grep -c . || true; }

    # Положительный контроль: вызов РОДИТЕЛЯ находку показывает и гасит. Без него «субагент
    # ничего не сделал» неотличимо от «страж вообще не работает».
    seed
    local out
    out=$(jq -cn --arg s "$sid" '{hook_event_name:"PreToolUse", session_id:$s, tool_name:"Bash", tool_input:{command:"echo x"}}' \
        | STATE_DIR="$st" bash "$hook" 2>/dev/null)
    if [ "$(pending_count)" != "0" ]; then
        echo "probe_D456: контроль ($1) — вызов родителя находку не погасил, судить нечем" >&2; return 2
    fi

    # Суд: тот же вызов от СУБАГЕНТА. Очередь обязана остаться нетронутой.
    seed
    out=$(jq -cn --arg s "$sid" '{hook_event_name:"PreToolUse", session_id:$s, agent_id:"a1", agent_type:"general-purpose", tool_name:"Bash", tool_input:{command:"echo x"}}' \
        | STATE_DIR="$st" bash "$hook" 2>/dev/null)
    if [ "$(pending_count)" != "1" ]; then
        echo "probe_D456: дефект ($1) — вызов субагента израсходовал находку РОДИТЕЛЯ" >&2; return 1
    fi
    if [ -n "${out:-}" ]; then
        echo "probe_D456: дефект ($1) — находка о речи родителя показана субагенту" >&2; return 1
    fi
    return 0
}

rc=0
check_one output-language-check output-violations token || rc=$?
[ "$rc" = 0 ] || exit "$rc"
check_one relative-date-check relative-date-findings finding || rc=$?
[ "$rc" = 0 ] || exit "$rc"
exit 0
