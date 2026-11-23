#!/usr/bin/env bash
# СУДИТ: hooks/timestamp-canary-check.sh
# probe_D1159 — канарейка на Stop судит итог хода, а не файл, который итог ещё не догнал. Ход в форме мира: реплика,
# инжект 🕐, промежуточный текст без шапки, вызов инструмента, его результат, размышление итога — строки текста итога в
# файле ещё нет (так лежал срез живой расшифровки 0083e0d5 на тревоге 27 октября 2026, 22:10).
#  · поле входа `last_assistant_message` со шапкой — тишина; без шапки — тревога «БЕЗ таймштампа»;
#  · поля нет, итога в файле нет — тишина (судить нечего);
#  · поля нет, итог в файле без шапки — тревога; со шапкой — тишина (прежний путь жив);
#  · путь с полем (в мире он единственный) судится всей логикой, а не одной шапкой: шапка в промежуточном блоке при
#    итоге без неё — тревога «промежуточном блоке», а не «БЕЗ таймштампа»; шапка итога 11:00 при инжекте 12:00 —
#    «не совпадает с инжектом»; продолжение после Stop без шапки — тишина (финальный скептик D1159, H1, M1, M2).
# Красная (1), пока хоть одна нога судит не так; 2 — рамка не собралась (нет канарейки, инжектора, jq).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
C="$R/hooks/timestamp-canary-check.sh"
[ -f "$C" ] && [ -f "$R/hooks/timestamp-inject.sh" ] && command -v jq >/dev/null 2>&1 || exit 2
unset CANARY_STATE_DIR TIMESTAMP_INJECT_PATH
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
rec() { jq -nc "$@"; }
{ rec '{type:"user",message:{role:"user",content:"почини"}}'
  rec '{type:"attachment",attachment:{type:"hook_additional_context",content:["🕐 2026-11-01 12:00 CET — этой шапкой начни ИТОГОВОЕ сообщение хода"]}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Смотрю файл."}]}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Read",input:{}}]}}'
  rec '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"ok"}]}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"thinking",thinking:"итог"}]}}'; } > "$T/race.jsonl" || exit 2
HDR='🕐 2026-11-01 12:00 CET

Готово.'
{ cat "$T/race.jsonl"; rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Готово."}]}}'; } > "$T/bare.jsonl"
{ cat "$T/race.jsonl"; rec --arg t "$HDR" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; } > "$T/head.jsonl"
out_of() {  # out_of <метка> <расшифровка> [текст поля] → текст тревоги (пусто — тишина)
    local inp
    inp=$(jq -nc --arg s "p1159$1" --arg p "$2" '{session_id:$s,transcript_path:$p,hook_event_name:"Stop",stop_hook_active:false}')
    [ $# -ge 3 ] && inp=$(printf '%s' "$inp" | jq -c --arg m "$3" '. + {last_assistant_message:$m}')
    mkdir -p "$T/st-$1"
    printf '%s' "$inp" | STATE_DIR="$T/st-$1" bash "$C" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}
canary() { out_of "$@" | grep -q 'БЕЗ таймштампа' && echo 1 || echo 0; }  # 1 — тревога «БЕЗ таймштампа»
[ "$(canary b "$T/bare.jsonl")" = 1 ] || { echo "рамка: итог без шапки в файле, без поля — канарейка не тревожит"; exit 2; }
[ "$(canary f1 "$T/race.jsonl" "$HDR")" = 0 ] || { echo "итог со шапкой в поле входа, файл итог не догнал — тревога"; exit 1; }
[ "$(canary f2 "$T/race.jsonl" "Готово.")" = 1 ] || { echo "итог без шапки в поле входа — тревоги нет"; exit 1; }
[ "$(canary n1 "$T/race.jsonl")" = 0 ] || { echo "поля нет, итога в файле нет — тревога о промежуточном блоке"; exit 1; }
[ "$(canary n2 "$T/head.jsonl")" = 0 ] || { echo "поля нет, итог со шапкой в файле — тревога"; exit 1; }
# Шапка в промежуточном блоке, итог (только в поле) без неё — тревога о промежуточном блоке.
{ head -n 2 "$T/race.jsonl"; rec --arg t "$HDR" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
  tail -n +4 "$T/race.jsonl"; } > "$T/interim.jsonl"
out_of i "$T/interim.jsonl" "Готово." | grep -q 'промежуточном блоке' || {
    echo "шапка в промежуточном блоке, итог в поле без неё — не тревога о промежуточном блоке"; exit 1; }
# Шапка итога в поле не совпадает с инжектом — тревога о несовпадении.
out_of s "$T/race.jsonl" "🕐 2026-11-01 11:00 CET" | grep -q 'не совпадает с инжектом' || {
    echo "шапка итога в поле (11:00) при инжекте 12:00 — несовпадения не названо"; exit 1; }
# Продолжение после Stop: итог со шапкой, сводка Stop, продолжение без шапки (в поле) — тишина.
{ head -n 2 "$T/race.jsonl"; rec --arg t "$HDR" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
  rec '{type:"system",subtype:"stop_hook_summary"}'; rec '{type:"assistant",message:{role:"assistant",content:[{type:"thinking",thinking:"дальше"}]}}'; } > "$T/cont.jsonl"
[ -z "$(out_of c "$T/cont.jsonl" "Дописал.")" ] || { echo "продолжение после Stop без шапки (в поле) — тревога"; exit 1; }
echo "канарейка судит итог хода по полю входа, а не по файлу, который его не догнал"
exit 0
