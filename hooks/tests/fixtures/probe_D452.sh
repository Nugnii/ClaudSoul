#!/usr/bin/env bash
# probe_D452.sh — проба пункта D452: `hooks/five-whys-gate.sh` перечислял субагенту поводы
#                 РОДИТЕЛЯ, потому что все четыре файла поводов ключевались общим
#                 `session_id` (`rework-fired`, `error_streak_fired`, `correction-fired`,
#                 `question-open`). Наблюдено дословно: субагенту инжектнут «Второй заход»
#                 на файл, которого он не касался.
# Результат: напоминание перечисляет только поводы АКТОРА вызова; повод родителя субагенту
#            не инжектится, свой повод субагента инжектится, поведение родителя не меняется.
# Проверка результата: bash hooks/tests/fixtures/probe_D452.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/five-whys-gate.sh"
[ -f "$HOOK" ] || { echo "probe_D452: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D452: нет jq" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D452: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
S="$T/state"; mkdir -p "$S"

mk_plain() {  # расшифровка без цепочки причин
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Правлю строку."}]}}' >> "$1"
}
call() {  # call <sid> <расшифровка> [agent_id]
    jq -cn --arg s "$1" --arg p "$2" --arg a "${3:-}" \
        '{session_id:$s, tool_name:"Write", transcript_path:$p, tool_input:{file_path:"/repo/x.sh"}}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' \
      | STATE_DIR="$S" bash "$HOOK" 2>/dev/null
}
# Суд — по журналу стража, а не по выводу (D1151, 31 октября 2026): запись без права на отказ молчит, а строку
# `turn:…|actor:<суффикс>|<виды>` страж пишет на каждый вызов с живыми поводами актора, до выбора вывода. Виды
# несут отпечаток (`rework:<путь>:<ступень>`), поэтому и «чужое не подмешано» читается из той же строки.
seen_of() { grep '^turn:' "$S/five-whys-$1.seen" 2>/dev/null | grep -F "|actor:$2|"; }   # seen_of <sid> <суффикс>
noticed() { grep -qF -- "${3:-|}" <<< "$(seen_of "$1" "$2")"; }   # noticed <sid> <суффикс ('' у родителя)> [вид]

# КАЖДЫЙ СУД В СВОЕЙ СЕССИИ. Дедуп напоминания (`five-whys-<SID>.seen`) до 18 сентября
# 2026 тоже был общим на акторов, поэтому в одной сессии первый вызов ГАСИЛ второй: первая
# редакция этой пробы вела контроль родителя перед судом субагента — и дефект не
# воспроизводился вовсе, субагент молчал по дедупу, а не по различению владельца.
# Разные сессии убирают это взаимное влияние из рамки суда.
mk_case() {  # mk_case <sid> → расшифровки родителя и субагента
    mkdir -p "$T/$1/subagents"
    mk_plain "$T/$1.parent.jsonl"
    mk_plain "$T/$1/subagents/agent-sub1.jsonl"
}
callp() { call "$1" "$T/$1.parent.jsonl" "${2:-}"; }

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (своя сессия): родитель со своим поводом обязан получить
# напоминание. Без него «субагенту тихо» неотличимо от «гейт онемел», и проба зеленела бы
# на выпотрошенном хуке.
mk_case ctl
printf '{"path":"/repo/test_gate_deny_per_kind.sh","cycles":3}\n' > "$S/rework-fired-ctl.jsonl"
callp ctl >/dev/null
noticed ctl "" "rework:" || {
    echo "probe_D452: контроль — родитель не получил напоминания, судить нечем" >&2
    exit 2
}

# Суд 1 (своя сессия, субагент ходит ПЕРВЫМ): повод лежит у родителя, вызов — субагента.
# Перечислять ему нечего.
mk_case s1
printf '{"path":"/repo/test_gate_deny_per_kind.sh","cycles":3}\n' > "$S/rework-fired-s1.jsonl"
callp s1 sub1 >/dev/null
if noticed s1 .agent-sub1; then
    echo "probe_D452: дефект — субагенту инжектнут повод РОДИТЕЛЯ" >&2
    exit 1
fi

# Суд 2: у субагента появился СВОЙ повод — напоминание обязано вернуться. Без этого суда
# проба зеленела бы и на гейте, который субагенту молчит ВСЕГДА, то есть не различает
# владельца, а просто ослеп.
mk_case s2
printf '{"path":"/repo/own.sh","cycles":3}\n' > "$S/rework-fired-s2.agent-sub1.jsonl"
callp s2 sub1 >/dev/null
noticed s2 .agent-sub1 "rework:" || {
    echo "probe_D452: дефект — свой повод субагента не инжектится, гейт для него нем" >&2
    exit 1
}

# Суд 3: своё названо своим именем, чужое не подмешано. Строка `turn:` здесь не годится: отпечаток `rework` в ней несёт
# только ПОСЛЕДНИЙ путь (`_rw_name … | tail -1` в гейте), и файл родителя, подмешанный первым, она не видит (скептик opus,
# D1151 M2). Весь перечень приписанных файлов (`_rw_files`) страж пишет в журнал исходов полем `ref`, когда цепочка в ходе
# актора произнесена, — поэтому субагент здесь произносит цепочку про СВОЙ файл, и `ref` обязан назвать его, не назвав чужого.
# Своих файлов два, и контроль требует оба: суд держится на том, что `ref` — весь перечень, а не последний путь (иначе
# «последний путь» вместе с «файл родителя первым» проходили пробу, D1151 круг 3, L1). Суд дефекта — раньше контроля:
# чужой файл в `ref` — дефект при любом составе своих.
mk_case s3
printf '{"path":"/repo/CHUZHOY.sh","cycles":3}\n' > "$S/rework-fired-s3.jsonl"
printf '{"path":"/repo/own.sh","cycles":3}\n{"path":"/repo/own2.sh","cycles":3}\n' > "$S/rework-fired-s3.agent-sub1.jsonl"
: > "$T/s3/subagents/agent-sub1.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$T/s3/subagents/agent-sub1.jsonl"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Почему упало? → own.sh:12 и own2.sh:3 читают пустой файл. Почему файл пуст? → писатель молчит при отказе. Почему молчит? → код возврата глотается. Корень назван."}]}}' \
    >> "$T/s3/subagents/agent-sub1.jsonl"
callp s3 sub1 >/dev/null
REF3=$(jq -r 'select(.signal == "rework") | .ref // empty' "$S/outcome-s3.jsonl" 2>/dev/null)
if grep -q 'CHUZHOY' <<< "$REF3"; then
    echo "probe_D452: дефект — субагенту приписан файл РОДИТЕЛЯ: $REF3" >&2
    exit 1
fi
grep -q 'own\.sh' <<< "$REF3" && grep -q 'own2\.sh' <<< "$REF3" \
    || { echo "probe_D452: контроль — свои файлы субагента в журнал исходов легли не оба: $REF3" >&2; exit 2; }

# Суд 4: ВСЕ пять файлов поводов, а не только `rework`. Первая редакция починки перевела
# четыре и пропустила пятый (`breakage-fired`, объявленный ниже по файлу), а проба судила
# только `rework` и промолчала — субагенту инжектировалась жалоба собеседника на поломку,
# адресованная родителю (находка адверсариальной проверки 18 сентября 2026). Срод `breakage`
# СТОЯЧИЙ: отказа он не даёт (с D1151 и напоминания), и именно на таком сроде дедуп гасил чужого.
mk_case s5
printf '{"date":"2026-09-18T00:00:00Z","snippet":"всё сломалось","hash":"777"}\n' > "$S/breakage-fired-s5.jsonl"
callp s5 sub1 >/dev/null
if noticed s5 .agent-sub1 "breakage:"; then
    echo "probe_D452: дефект — субагенту инжектнута жалоба РОДИТЕЛЯ на поломку" >&2
    exit 1
fi
# Контроль к нему: своя жалоба субагенту обязана дойти, иначе гейт для него просто нем.
printf '{"date":"2026-09-18T00:00:00Z","snippet":"всё сломалось","hash":"777"}\n' > "$S/breakage-fired-s5.agent-sub1.jsonl"
callp s5 sub1 >/dev/null
noticed s5 .agent-sub1 "breakage:" || {
    echo "probe_D452: контроль — своя жалоба субагенту не дошла, судить нечем" >&2
    exit 2
}

# Суд 5: ДЕДУП не гасит другого актора. Стоячий срод пишет строку в общий журнал хода, и до
# 18 сентября 2026 первый дошедший актор снимал напоминание у всех остальных в сессии.
mk_case s6
printf '{"date":"2026-09-18T00:00:00Z","snippet":"всё сломалось","hash":"777"}\n' > "$S/breakage-fired-s6.jsonl"
cp "$S/breakage-fired-s6.jsonl" "$S/breakage-fired-s6.agent-sub1.jsonl"
callp s6 sub1 >/dev/null          # субагент говорит первым и пишет ключ хода
callp s6 >/dev/null                # родитель со СВОИМ поводом обязан всё равно получить своё
noticed s6 "" "breakage:" || {
    echo "probe_D452: дефект — напоминание родителя погашено дедупом СУБАГЕНТА" >&2
    exit 1
}

# Суд 6: ВСЕ ПЯТЬ семей поводов, а не те две, на которых наблюдался дефект. Объявленный
# результат D452 говорит «только поводы АКТОРА», то есть утверждение о ВСЁМ перечне; суды
# же писались по одной находке каждый (rework — из пункта, breakage — от скептика), и
# мутант «суффикс применён к rework и breakage, а STREAK, CORRECTION и QUESTION оставлены
# на общем ключе» проходил все четыре пробы (воспроизведено 18 сентября 2026). Здесь
# перечень берётся из КОНТРАКТА, а не из памяти о дефекте.
mk_case s7
printf '{"date":"2026-09-18T00:00:00Z","snippet":"поправка","hash":"111"}\n' > "$S/correction-fired-s7.jsonl"
printf '{"date":"2026-09-18T00:00:00Z","q":"а почему так?"}\n' > "$S/question-open-s7.jsonl"
printf '2' > "$S/error_streak_fired_s7"
callp s7 sub1 >/dev/null
if noticed s7 .agent-sub1; then
    echo "probe_D452: дефект — субагенту инжектнуты поводы РОДИТЕЛЯ (поправка/вопрос/полоса)" >&2
    exit 1
fi
# Контроль: те же три семьи, положенные СУБАГЕНТУ, обязаны дойти — иначе гейт просто нем
# к ним, и суд выше проходил бы на онемевшем механизме.
mk_case s8
printf '2' > "$S/error_streak_fired_s8.agent-sub1"
callp s8 sub1 >/dev/null
noticed s8 .agent-sub1 "streak:" || {
    echo "probe_D452: контроль — своя полоса субагенту не дошла, судить нечем" >&2
    exit 2
}

# Суд 7: поведение РОДИТЕЛЯ не изменилось — своё видит, чужого не видит.
mk_case s4
printf '{"path":"/repo/own.sh","cycles":3}\n' > "$S/rework-fired-s4.agent-sub1.jsonl"
printf '{"path":"/repo/parent.sh","cycles":3}\n' > "$S/rework-fired-s4.jsonl"
OUT=$(callp s4)
noticed s4 "" "rework:" || {
    echo "probe_D452: дефект — родитель перестал видеть собственный повод" >&2
    exit 1
}
if grep -q '/repo/own.sh' <<< "$OUT$(seen_of s4 "")"; then
    echo "probe_D452: дефект — родителю назван повод СУБАГЕНТА" >&2
    exit 1
fi
exit 0
