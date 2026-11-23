#!/usr/bin/env bash
# СУДИТ: hooks/publish-guard.sh
# probe_D455.sh — проба пункта D455: `hooks/publish-guard.sh` искал свидетельство сухого
#                 прогона в расшифровке РОДИТЕЛЯ, а текст субагента туда не попадает вовсе —
#                 субагент, честно сделавший сухой прогон, получал ОТКАЗ уровня 4.
# Результат: сухой прогон в расшифровке АКТОРА снимает отказ; без него отказ остаётся;
#            сухой прогон родителя субагенту не засчитывается.
# Проверка результата: bash hooks/tests/fixtures/probe_D455.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/publish-guard.sh"
[ -f "$HOOK" ] || { echo "probe_D455: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D455: нет jq" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D455: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

PUSH='bash scripts/publish-public.sh --push'
DRY='bash scripts/publish-public.sh'

mk_tr() {  # mk_tr <имя> <команды...>
    local f="$T/$1.jsonl"; shift
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"публикуй"}]}}\n' > "$f"
    local c
    for c in "$@"; do
        printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' \
            "$(jq -Rn --arg c "$c" '$c')" >> "$f"
    done
    printf '%s' "$f"
}
run_sub() {  # run_sub <расшифровка агента> <расшифровка родителя>
    local sid="s$RANDOM"; local proj="$T/proj-$sid"
    mkdir -p "$proj/$sid/subagents"
    cp "$2" "$proj/$sid.jsonl"
    local ag="$proj/$sid/subagents/agent-$sid.jsonl"; cp "$1" "$ag"
    jq -cn --arg c "$PUSH" --arg p "$proj/$sid.jsonl" --arg a "$ag" --arg s "$sid" \
        '{tool_name:"Bash", tool_input:{command:$c}, transcript_path:$p, session_id:$s, agent_id:$s, agent_transcript_path:$a}' \
      | bash "$HOOK" 2>&1
}
denied() { printf '%s' "${1:-}" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

PAR_PLAIN=$(mk_tr par_plain "echo не про публикацию")

# Положительный контроль: без сухого прогона нигде отказ ОБЯЗАН быть. Иначе «отказа нет»
# неотличимо от «страж выпотрошен», и проба зеленела бы на пустом файле.
AG_NODRY=$(mk_tr ag_nodry "$PUSH")
denied "$(run_sub "$AG_NODRY" "$PAR_PLAIN")" \
    || { echo "probe_D455: контроль — субагент без сухого прогона отказа не получил, судить нечем" >&2; exit 2; }

# Суд 1: сухой прогон лежит в расшифровке САМОГО субагента — отказа быть не должно.
AG_DRY=$(mk_tr ag_dry "$DRY" "$PUSH")
if denied "$(run_sub "$AG_DRY" "$PAR_PLAIN")"; then
    echo "probe_D455: дефект — сухой прогон субагента в его расшифровке не зачтён (ложный отказ уровня 4)" >&2
    exit 1
fi

# Суд 2: сухой прогон РОДИТЕЛЯ субагенту не засчитывается — это чужое предъявление.
PAR_DRY=$(mk_tr par_dry "$DRY")
AG_NODRY2=$(mk_tr ag_nodry2 "$PUSH")
if ! denied "$(run_sub "$AG_NODRY2" "$PAR_DRY")"; then
    echo "probe_D455: дефект — субагенту зачтён сухой прогон РОДИТЕЛЯ" >&2
    exit 1
fi
exit 0
