#!/usr/bin/env bash
# СУДИТ: hooks/lib/transcript_window.py hooks/hook-input-lib.sh hooks/user-correction-guard.sh hooks/root-cause-lib.sh hooks/activity-flush-lib.sh hooks/shared-language-lib.sh hooks/output-language-check.sh hooks/timestamp-canary-check.sh hooks/fix-level-check.sh hooks/accepted-alternative-gap.sh hooks/declared-problem-recorded.sh
# test_queued_reply_readers.sh — D1142 (корень R3): реплика владельца, набранная посреди хода, лежит вложением
# `queued_command` (`commandMode: prompt`, автор — `attachment.origin.kind`), и каждый читатель реплики видит её
# репликой: граница хода, текст реплики, текст агента до неё, образец «правка, затем реплика» на обоих путях стража,
# ключ хода разбора причин, журнал активности, речь для общего словаря. Контроль — отчёт субагента той же формы
# (`origin.kind: peer`) и уведомление задачи (`commandMode: task-notification`, без автора) репликой не становятся.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "ожидалось «$3», получено «$2»"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

PAGE="$T/page.html"
REPLY='верни прежний цвет и шрифт сделай крупнее'
queued() {  # queued <origin.kind или пусто> <commandMode> <текст> <uuid>
    jq -nc --arg k "$1" --arg m "$2" --arg t "$3" --arg u "$4" \
        '{type:"attachment", uuid:$u, isSidechain:false,
          attachment:({type:"queued_command", commandMode:$m, prompt:[{type:"text", text:$t}]}
                      + (if $k == "" then {} else {origin:{kind:$k}} end))}'
}
head_lines() {
    jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"сделай заголовок страницы синим"}]}}'
    jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Посчитал: 13 процентов."}]}}'
    jq -nc --arg f "$PAGE" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e1",name:"Edit",input:{file_path:$f,old_string:"a",new_string:"b"}}]}}'
    jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"e1",content:"ok"}]}}'
}
F="$T/queued.jsonl"     # реплика владельца посреди хода, за ней — отчёт субагента и уведомление задачи
{ head_lines; queued human prompt "$REPLY" q1; queued peer prompt "отчёт субагента: всё готово" q2
  queued "" task-notification "<task-notification>задача кончилась</task-notification>" q3
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:"ls"}}]}}'; } > "$F"
C="$T/control.jsonl"    # те же вложения без реплики владельца
{ head_lines; queued peer prompt "отчёт субагента: всё готово" q2
  queued "" task-notification "<task-notification>задача кончилась</task-notification>" q3; } > "$C"
Q_OFF=$(python3 -c 'import sys
o=0
for l in open(sys.argv[1],"rb"):
    if b"\"q1\"" in l: print(o); break
    o+=len(l)' "$F")

lib() { bash -c '. "$1/hook-input-lib.sh"; shift; '"$1" _ "$HOOKS" "${@:2}"; }
# L1 — граница хода (до Stop) реплика посреди хода НЕ двигает: Stop между ними не случается, ход продолжается.
# L1s — режим `reply` отдаёт последнюю РЕЧЬ владельца: реплику посреди хода; без неё — реплику хода.
eq L1 "$(python3 "$HOOKS/lib/transcript_window.py" "$F")" 0
eq L1s "$(python3 "$HOOKS/lib/transcript_window.py" "$F" --reply --range | cut -d' ' -f1)" "$Q_OFF"
eq L1c "$(python3 "$HOOKS/lib/transcript_window.py" "$C" --reply --range | cut -d' ' -f1)" 0
# L2 — текст реплики: путь с окном и путь по всему файлу дают нынешнюю реплику; контроль — прежнюю.
eq L2 "$(lib 'transcript_user_texts "$1" 1' "$F" 2>/dev/null)" "$REPLY"
eq L2w "$(lib 'transcript_turn_window() { cat "$1"; }; transcript_user_texts "$1" 1' "$F" 2>/dev/null)" "$REPLY"
eq L2c "$(lib 'transcript_user_texts "$1" 1' "$C" 2>/dev/null)" "сделай заголовок страницы синим"
# L3 — текст агента ДО реплики: до реплики посреди хода агент говорил, до первой реплики — нет.
eq L3 "$(lib 'transcript_agent_text_before_reply "$1"' "$F" 2>/dev/null)" "Посчитал: 13 процентов."
eq L3w "$(lib 'transcript_turn_window() { cat "$1"; }; transcript_agent_text_before_reply "$1"' "$F" 2>/dev/null)" "Посчитал: 13 процентов."
eq L3c "$(lib 'transcript_agent_text_before_reply "$1"' "$C" 2>/dev/null)" ""
# L4 — образец «правка, затем реплика» быстрого пути.
eq L4 "$(python3 "$HOOKS/lib/transcript_window.py" "$F" --context-hit "$PAGE")" 1
eq L4c "$(python3 "$HOOKS/lib/transcript_window.py" "$C" --context-hit "$PAGE")" 0
# L5 — страж поправок, повторная правка того же файла: быстрый путь и запасной (помощник не ответил) говорят одно.
ucg() {  # ucg <расшифровка> <библиотека ввода или пусто>
    rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
    jq -nc --arg p "$1" --arg f "$PAGE" '{session_id:"s-q",transcript_path:$p,tool_name:"Edit",
        tool_input:{file_path:$f,old_string:"b",new_string:"c"},hook_event_name:"PreToolUse"}' \
        | env ${2:+INPUT_LIB="$2"} bash "$HOOKS/user-correction-guard.sh" 2>/dev/null \
        | grep -c 'Ты правишь файл, который уже правил'
}
cp "$HOOKS/hook-input-lib.sh" "$T/no-helper-lib.sh"
printf '%s\n' 'transcript_edit_then_reply() { :; }' 'transcript_turn_window() { cat "$1"; }' >> "$T/no-helper-lib.sh"
eq L5 "$(ucg "$F" "")" 1
eq L5w "$(ucg "$F" "$T/no-helper-lib.sh")" 1
eq L5c "$(ucg "$C" "$T/no-helper-lib.sh")" 0
# L6 — ключ хода разбора причин реплика посреди хода НЕ меняет (скептик D1142, M1): со сбросом на вложении находка,
# объявленная до него, оставалась без суда на Stop — журнал держит ключ прежнего хода.
rc() { mkdir -p "$STATE_DIR"; bash -c '. "$1/root-cause-lib.sh"; rc_turn_digest "$2"' _ "$HOOKS" "$1" 2>/dev/null; }
eq L6 "$(rc "$F" | jq -r '.k')" "сделай заголовок страницы синим"
eq L6c "$(rc "$C" | jq -r '.k')" "сделай заголовок страницы синим"
# L7 — журнал активности: реплика посреди хода записана, отчёт субагента — нет.
mkdir -p "$T/cwd"
bash -c '. "$1/activity-flush-lib.sh"; activity_flush s-q-abcdefgh "$2" "$3"' _ "$HOOKS" "$F" "$T/cwd" >/dev/null 2>&1 || true  # предмет проверки: его итог читает grep ниже (D1219)
ACT=$(cat "$T/cwd/.claude-docs/session-activity.md" 2>/dev/null)
grep -Fq "$REPLY" <<< "$ACT" && ok || bad L7 "реплики посреди хода нет в журнале активности"
grep -Fq "отчёт субагента" <<< "$ACT" && bad L7c "отчёт субагента записан как реплика" || ok
# L8 — речь для общего словаря.
SPEECH=$(bash -c '. "$1/shared-language-lib.sh"; shlang_user_text "$2"' _ "$HOOKS" "$F" 2>/dev/null)
grep -Fxq "$REPLY" <<< "$SPEECH" && ok || bad L8 "реплики посреди хода нет в речи собеседника"
grep -Fq "отчёт субагента" <<< "$SPEECH" && bad L8c "отчёт субагента взят речью" || ok
grep -Fq "задача кончилась" <<< "$SPEECH" && bad L8t "уведомление задачи взято речью" || ok

# L9 — сканер речи на Stop (`relative-date-check`): «вчера» без даты сказано ДО реплики посреди хода, после неё — чисто.
# Stop между ними не случается, и этот текст судит только Stop, закрывающий ход: находка обязана быть на обоих путях
# (с помощником и без). Первая редакция D1142 (fddd73fc) начинала окно с вложения, и текст до него не судил никто.
# Контроль — та же речь ПОСЛЕ реплики находится на обоих путях.
D="$T/dated.jsonl"; DC="$T/dated-after.jsonl"
SAID='Вчера мы починили счётчики.'
{ head_lines; jq -nc --arg t "$SAID" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
  queued human prompt "$REPLY" q4
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Цвет вернул."}]}}'; } > "$D"
{ head_lines; queued human prompt "$REPLY" q5
  jq -nc --arg t "$SAID" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; } > "$DC"
rdc() {  # rdc <расшифровка> <библиотека ввода или пусто> → число находок
    rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
    jq -nc --arg p "$1" '{hook_event_name:"Stop",session_id:"s-d",transcript_path:$p}' \
        | env ${2:+INPUT_LIB="$2"} bash "$HOOKS/relative-date-check.sh" >/dev/null 2>&1
    local _k; _k=$(grep -c '' "$STATE_DIR/relative-date-findings-s-d.jsonl" 2>/dev/null); echo "${_k:-0}"
}
eq L9 "$(rdc "$D" "")" 1
eq L9w "$(rdc "$D" "$T/no-helper-lib.sh")" 1
eq L9c "$(rdc "$DC" "")|$(rdc "$DC" "$T/no-helper-lib.sh")" "1|1"

# L10 — краевые формы автора судятся одинаково на двух путях (скептик D1142, L3): `origin.kind: ""` — не человек
# (jq подставляет «human» только на отсутствие поля), вложение с автором не объектом не роняет выборку окна.
E="$T/edge.jsonl"
{ head_lines; queued "" prompt "реплика без автора" q6
  jq -nc '{type:"attachment",uuid:"q7",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:""},prompt:"пустой автор"}}'
  jq -nc '{type:"attachment",uuid:"q8",attachment:{type:"queued_command",commandMode:"prompt",origin:"human",prompt:"автор строкой"}}'; } > "$E"
eq L10 "$(lib 'transcript_user_texts "$1" 1' "$E" 2>/dev/null)|$(lib 'transcript_turn_window() { cat "$1"; }; transcript_user_texts "$1" 1' "$E" 2>/dev/null)" "реплика без автора|реплика без автора"

# L11–L15 — остальные сканеры речи на Stop судят текст агента ДО реплики посреди хода так же, как после неё (граница
# хода — запись `user`, вложение её не двигает; редакция fddd73fc сдвигала окно на вложение, и сказанное до него не судил
# никто). Фикстура: реплика → текст агента с находкой → вложение человека → текст без находки → Stop.
# mid <файл> <текст до> <текст после> [строка перед текстом до — для канарейки]
mid() {
    { jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"сделай шрифт крупнее"}]}}'
      [ -n "${4:-}" ] && printf '%s\n' "$4"
      jq -nc --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
      queued human prompt "$REPLY" q9
      jq -nc --arg t "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; } > "$1"
}
stop() {  # stop <хук> <sid> <расшифровка> [ENV=…] → stdout хука
    local h="$1" s="$2" t="$3"; shift 3
    rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
    jq -nc --arg s "$s" --arg p "$t" '{hook_event_name:"Stop",session_id:$s,transcript_path:$p}' \
        | env "$@" bash "$HOOKS/$h" 2>/dev/null
}
lines() { local _k; _k=$(grep -c '' "$1" 2>/dev/null); echo "${_k:-0}"; }
# L11 — смешение алфавитов (`output-language-check`): токен в состоянии нарушений.
mid "$T/ol.jsonl" "Сделал trёх правок." "Шрифт увеличил."
stop output-language-check.sh s-ol "$T/ol.jsonl" >/dev/null
eq L11 "$(lines "$STATE_DIR/output-violations-s-ol.jsonl")" 1
# L12 — таймштамп-канарейка: шапка с эхом инжекта сказана до вложения, после него шапки нет — алерта быть не должно.
# Контроль: шапки нет нигде — алерт на месте (хук не молчит по другой причине).
INJ='{"type":"attachment","attachment":{"type":"hook_additional_context","content":["🕐 2026-10-27 12:00 CEST"]}}'
mkdir -p "$T/noabl"
mid "$T/tc.jsonl" "🕐 2026-10-27 12:00 Сделал." "Дальше." "$INJ"
mid "$T/tcc.jsonl" "Сделал." "Дальше." "$INJ"
canary() { stop timestamp-canary-check.sh s-tc "$1" CANARY_STATE_DIR="$STATE_DIR" ABLATION_DIR="$T/noabl" | grep -c Канарейка; }
eq L12 "$(canary "$T/tc.jsonl")" 0
eq L12c "$(canary "$T/tcc.jsonl")" 1
# L13 — текстовый фикс после инцидента (`fix-level-check`): фраза в состоянии.
mkdir -p "$T/nolessons"
mid "$T/fl.jsonl" "Ошибся, буду внимательнее." "Шрифт увеличил."
stop fix-level-check.sh s-fl "$T/fl.jsonl" LESSONS_DIR="$T/nolessons" >/dev/null
eq L13 "$(lines "$STATE_DIR/fix-level-s-fl.jsonl")" 1
# L14 — принятый вариант собеседника (`accepted-alternative-gap`): напоминание на stdout.
mid "$T/aa.jsonl" "Отличная идея, беру твой вариант." "Шрифт увеличил."
eq L14 "$(stop accepted-alternative-gap.sh s-aa "$T/aa.jsonl" | grep -c additionalContext)" 1
# L15 — заявленная проблема (`declared-problem-recorded`): начало хода — отметка реплики `user`, а не вложения. Бэклог
# тронут между ними — исход засчитан, напоминания нет. Контроль: бэклог тронут до реплики — напоминание есть.
now=$(date -u +%s)
iso() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
touch_at() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }
{ jq -nc --arg ts "$(iso $((now - 3600)))" '{type:"user",timestamp:$ts,message:{role:"user",content:"разбери это"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Нашёл проблему."}]}}'
  queued human prompt "$REPLY" q10 | jq -c --arg ts "$(iso $((now - 30)))" '. + {timestamp:$ts}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Дальше."}]}}'; } > "$T/dp.jsonl"
DPK=$(bash -c '. "$1/root-cause-lib.sh"; rc_turn_key "$2"' _ "$HOOKS" "$T/dp.jsonl" 2>/dev/null)
dpr() {  # dpr <эпоха правки бэклога> → число строк напоминания
    printf '# долг\n' > "$T/BACKLOG.md"; touch_at "$T/BACKLOG.md" "$1"
    rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
    printf 'turn:%s|discovery:123|\n' "$DPK" > "$STATE_DIR/five-whys-s-dp.seen"
    jq -nc --arg p "$T/dp.jsonl" '{hook_event_name:"Stop",session_id:"s-dp",transcript_path:$p}' \
        | DPR_LOCAL_BACKLOG="$T/BACKLOG.md" bash "$HOOKS/declared-problem-recorded.sh" >/dev/null 2>&1
    local _k; _k=$(grep -c 'закрытого списка' "$STATE_DIR/stop-signals-s-dp.txt" 2>/dev/null); echo "${_k:-0}"
}
eq L15 "$(dpr $((now - 1800)))" 0
eq L15c "$(dpr $((now - 7200)))" 1

# L16 — автор вложения строкой не роняет читателей с `jq -s` (скептик D1142, L3): приводилка проверяет, что `origin` — объект
# (в jq 1.7 `.attachment.origin.kind` на строке — ошибка, и `jq -s` теряет весь вывод). Враждебная запись стоит НЕ последней,
# за ней — настоящая реплика человека: потоковый `jq -r` после ошибки идёт дальше, `jq -s` — нет (нога L10 этого не различает).
H="$T/hostile-mid.jsonl"
{ jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"сделай заголовок страницы синим"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Посчитал: 13 процентов."}]}}'
  jq -nc '{type:"attachment",uuid:"q11",attachment:{type:"queued_command",commandMode:"prompt",origin:"human",prompt:"автор строкой"}}'
  queued human prompt "$REPLY" q12; } > "$H"
eq L16 "$(lib 'transcript_agent_text_before_reply "$1"' "$H" 2>/dev/null)" "Посчитал: 13 процентов."
eq L16w "$(lib 'transcript_turn_window() { cat "$1"; }; transcript_agent_text_before_reply "$1"' "$H" 2>/dev/null)" "Посчитал: 13 процентов."

echo "test_queued_reply_readers: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
