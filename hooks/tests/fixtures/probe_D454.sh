#!/usr/bin/env bash
# probe_D454.sh — проба пункта D454: `hooks/error-tracker.sh` считал полосу провалов по
#                 `.transcript_path`, а харнесс кладёт туда путь РОДИТЕЛЯ всегда. Пока
#                 субагент работал, файл родителя не рос: своя полоса субагента не
#                 считалась вовсе, а «стой» адресовался тому, кто провалов не делал.
# Результат: полоса считается по расшифровке АКТОРА; субагент со своими двумя провалами
#            получает «стой», родитель чужих провалов не получает, состояние полосы
#            принадлежит актору.
# Проверка результата: bash hooks/tests/fixtures/probe_D454.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/error-tracker.sh"
[ -f "$HOOK" ] || { echo "probe_D454: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D454: нет jq" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D454: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
S="$T/state"; mkdir -p "$S"

mk_fails() {  # mk_fails <файл> <сколько провалов>
    : > "$1"
    local i=0
    while [ "$i" -lt "${2:-0}" ]; do
        jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",is_error:true,content:[{type:"text",text:"error: сборка упала"}]}]}}' >> "$1"
        i=$((i+1))
    done
}
call() {  # call <sid> <расшифровка родителя> [agent_id]
    jq -cn --arg s "$1" --arg p "$2" --arg a "${3:-}" \
        '{session_id:$s, tool_name:"Bash", transcript_path:$p, tool_input:{command:"bash t.sh"}}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' \
      | env STATE_DIR="$S" bash "$HOOK" 2>/dev/null
}
said() { grep -qE '2\+ провала|провал|СТОП|стой' <<< "${1:-}"; }

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: родитель со своими провалами обязан получить «стой». Без него
# «субагенту тихо» неотличимо от «хук онемел», и проба зеленела бы на выпотрошенном коде.
PAR_BAD="$T/parent-bad.jsonl"; mk_fails "$PAR_BAD" 3
OUT=$(call ctl "$PAR_BAD")
said "$OUT" || {
    echo "probe_D454: контроль — родитель не получил «стой», судить нечем: ${OUT:0:200}" >&2
    exit 2
}

# Суд 1: провалы у РОДИТЕЛЯ, вызов принадлежит субагенту с ЧИСТОЙ собственной расшифровкой.
# Чужая полоса ему не адресуется.
SID=s1
mkdir -p "$T/$SID/subagents"
mk_fails "$T/$SID/subagents/agent-sub1.jsonl" 0
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"работаю"}]}}\n' \
    >> "$T/$SID/subagents/agent-sub1.jsonl"
OUT=$(call "$SID" "$PAR_BAD" sub1)
if said "$OUT"; then
    echo "probe_D454: дефект — субагенту адресована полоса провалов РОДИТЕЛЯ: ${OUT:0:200}" >&2
    exit 1
fi

# Суд 2: своя полоса субагента считается — иначе «тихо всегда» выдаётся за различение.
SID=s2
mkdir -p "$T/$SID/subagents"
mk_fails "$T/$SID/subagents/agent-sub2.jsonl" 3
PAR_OK="$T/parent-ok.jsonl"; mk_fails "$PAR_OK" 0
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"ровно"}]}}\n' >> "$PAR_OK"
OUT=$(call "$SID" "$PAR_OK" sub2)
said "$OUT" || {
    echo "probe_D454: дефект — своя полоса субагента не считается, он невидим себе" >&2
    exit 1
}

# Суд 3: состояние полосы принадлежит актору — у родителя имя прежнее, у субагента своё.
[ -f "$S/error_streak_fired_s2.agent-sub2" ] || {
    echo "probe_D454: дефект — полоса субагента не записана под его именем" >&2
    exit 1
}
[ -f "$S/error_streak_fired_ctl" ] || {
    echo "probe_D454: контроль — полоса родителя не записана прежним именем" >&2
    exit 2
}

# Суд 4: ОТСУТСТВИЕ ЧУЖОГО. Проверка «мой файл есть» проходится дублирующей записью:
# починка, пишущая полосу и под именем актора, и в общий сессионный файл, проходила суды
# выше (воспроизведено адверсариальной проверкой 18 сентября 2026). Общее имя читает гейт
# разбора (`five-whys-gate.sh`, STREAK) как повод РОДИТЕЛЯ — то есть дубль возвращает ровно
# чинимый дефект. Сессия берётся ЧИСТАЯ, чтобы родитель в ней не работал вовсе.
SID=s3
mkdir -p "$T/$SID/subagents"
mk_fails "$T/$SID/subagents/agent-sub3.jsonl" 3
PAR3="$T/parent3.jsonl"; mk_fails "$PAR3" 0
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"ровно"}]}}\n' >> "$PAR3"
call "$SID" "$PAR3" sub3 >/dev/null
[ -f "$S/error_streak_fired_${SID}.agent-sub3" ] || {
    echo "probe_D454: контроль — полоса субагента не записана, судить нечем" >&2
    exit 2
}
if [ -f "$S/error_streak_fired_${SID}" ]; then
    echo "probe_D454: дефект — полоса субагента записана и под ОБЩИМ именем: его читает гейт разбора как повод родителя" >&2
    exit 1
fi
if [ -f "$S/had_struggle_${SID}.agent-sub3" ]; then
    echo "probe_D454: дефект — сессионный признак буксования получил суффикс актора: свод его не увидит" >&2
    exit 1
fi
exit 0
