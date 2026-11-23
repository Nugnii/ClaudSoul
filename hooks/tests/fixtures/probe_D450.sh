#!/usr/bin/env bash
# probe_D450.sh — проба пункта D450: `hooks/subagent-outcome.sh` судил исход СУБАГЕНТА по
#                 расшифровке РОДИТЕЛЯ: читал `transcript_path`, тогда как харнесс кладёт
#                 собственную расшифровку агента в `agent_transcript_path`.
# Результат: успешный субагент при родителе, стоящем на `tool_use` вызова Task, не
#            объявляется оборвавшимся; настоящий обрыв агента виден; отсутствие поля даёт
#            «расшифровка недоступна», а не суд над расшифровкой родителя.
# Проверка результата: bash hooks/tests/fixtures/probe_D450.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
#
# Цена дефекта измерена: на момент `SubagentStop` последний блок ассистента у родителя —
# `tool_use` самого вызова Task, то есть тревога поднималась на КАЖДОМ успешном агенте, а
# постоянный ключ дедупа (`cksum` пути родителя) гасил все следующие — во всех 16 файлах
# `subagent-cut-*.seen` по всем проектам ровно по одной строке.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/subagent-outcome.sh"
[ -f "$HOOK" ] || { echo "probe_D450: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D450: нет jq" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D450: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

mk() {  # mk <файл> text|tool_use|structured
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"задача"}]}}\n' >> "$1"
    case "$2" in
        text)     printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"сделано"}]}}\n' >> "$1" ;;
        tool_use) printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n' >> "$1" ;;
        # Форма агента ВОЛНЫ: результат сдан вызовом `StructuredOutput` (312 из 322 живых
        # расшифровок, кончающихся вызовом инструмента, — замер 18 сентября 2026).
        structured) printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"StructuredOutput","input":{}}]}}\n' >> "$1"
                    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Structured output provided successfully"}]}}\n' >> "$1" ;;
    esac
}
run() {  # run <расшифровка агента|пусто> <расшифровка родителя>
    # Раскладка путей взята из мира: `<проект>/<session_id>/subagents/agent-<id>.jsonl`.
    local st="$T/state.$RANDOM"; mkdir -p "$st"
    local n="p$RANDOM"; local proj="$T/proj-$n"
    mkdir -p "$proj/$n/subagents"
    cp "$2" "$proj/$n.jsonl" 2>/dev/null || :
    if [ -n "$1" ]; then
        local ag="$proj/$n/subagents/agent-$n.jsonl"
        cp "$1" "$ag" 2>/dev/null || :
        jq -cn --arg a "$ag" --arg p "$proj/$n.jsonl" --arg s "$n" --arg i "$n" \
            '{session_id:$s, transcript_path:$p, agent_id:$i, agent_transcript_path:$a}'
    else
        jq -cn --arg p "$proj/$n.jsonl" --arg s "$n" '{session_id:$s, transcript_path:$p}'
    fi | STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
    cat "$st/pending-alerts.txt" 2>/dev/null || true
}

# Родитель в момент SubagentStop: стоит на вызове Task, то есть на `tool_use`.
mk "$T/parent.jsonl" tool_use

# Положительный контроль: настоящий обрыв агента страж обязан назвать. Без этого «тишина»
# неотличима от «страж выпотрошен» — проба зеленела бы на пустом файле.
mk "$T/cut.jsonl" tool_use
grep -q 'ОБОРВАЛСЯ' <<< "$(run "$T/cut.jsonl" "$T/parent.jsonl")" \
    || { echo "probe_D450: контроль — настоящий обрыв не назван, судить нечем" >&2; exit 2; }

# Суд 1: агент ДОГОВОРИЛ, родитель стоит на tool_use — тишина обязательна.
mk "$T/done.jsonl" text
OUT=$(run "$T/done.jsonl" "$T/parent.jsonl")
if grep -q 'ОБОРВАЛСЯ' <<< "$OUT"; then
    echo "probe_D450: дефект — успешный субагент объявлен оборвавшимся по состоянию родителя" >&2
    exit 1
fi

# Суд 1б: агент ВОЛНЫ сдал результат вызовом инструмента — тоже тишина. Первая редакция
# починки D450 объявляла такие обрывом: признак «договорил = текст последним» взят по форме
# агента инструмента Task, а агент волны текстом не кончает никогда.
mk "$T/wave.jsonl" structured
OUT=$(run "$T/wave.jsonl" "$T/parent.jsonl")
if grep -q 'ОБОРВАЛСЯ' <<< "$OUT"; then
    echo "probe_D450: дефект — сданный структурированный ответ объявлен обрывом" >&2
    exit 1
fi

# Суд 1в: расшифровка ОТСТАЁТ от ответа (живая гонка 18 сентября 2026) — судит поле харнесса.
mk "$T/lag.jsonl" tool_use
st_lag="$T/state.lag"; mkdir -p "$st_lag"
n=lag; proj="$T/proj-$n"; mkdir -p "$proj/$n/subagents"
cp "$T/parent.jsonl" "$proj/$n.jsonl"; cp "$T/lag.jsonl" "$proj/$n/subagents/agent-$n.jsonl"
jq -cn --arg a "$proj/$n/subagents/agent-$n.jsonl" --arg p "$proj/$n.jsonl" --arg s "$n" \
    '{session_id:$s, transcript_path:$p, agent_id:"lag", agent_transcript_path:$a, last_assistant_message:"сделано"}' \
  | STATE_DIR="$st_lag" bash "$HOOK" >/dev/null 2>&1
if grep -q 'ОБОРВАЛСЯ' "$st_lag/pending-alerts.txt" 2>/dev/null; then
    echo "probe_D450: дефект — ответ агента взят у отставшей расшифровки, а не у харнесса" >&2
    exit 1
fi

# Суд 2: поля нет вовсе — «недоступна», а не суд над родителем.
OUT=$(run "" "$T/parent.jsonl")
if grep -q 'ОБОРВАЛСЯ' <<< "$OUT"; then
    echo "probe_D450: дефект — без поля страж осудил расшифровку родителя" >&2
    exit 1
fi
grep -q 'недоступна' <<< "$OUT" || { echo "probe_D450: без поля ожидалось «недоступна», получено: [${OUT:0:80}]" >&2; exit 2; }
exit 0
