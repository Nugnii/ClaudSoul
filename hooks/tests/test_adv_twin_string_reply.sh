#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/user-correction-guard.sh
# test_adv_twin_string_reply.sh — противник окна хода (D498): реплика владельца со СТРОКОВЫМ
# content. Помощник окна считает её репликой (`_text` понимает строку) и начинает окно с неё, а
# `transcript_user_texts` строку не читает: `.message.content // [] | map(...)` на строке —
# ошибка jq, запись пропускается. На всём файле функция отдаёт текст ПРЕДЫДУЩЕЙ реплики со
# списочным content, на окне — пусто. Вердикты двух путей расходятся (помощник есть / помощника
# нет), и ни один не читает нынешнюю реплику.
# Форма из мира: 552 из 2406 реплик владельца в расшифровках несут строковый content, из них
# 415 — обычная речь, последняя 30 сентября 2026 (клиент 2.1.283).
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

F="$T/t.jsonl"
{
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"опять не так, переделай"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Переделал."}]}}'
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"отлично, спасибо, дальше"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:"ls"}}]}}'
} > "$F"

WIN=$(bash -c '. "$1/hook-input-lib.sh"; transcript_user_texts "$2" 1' _ "$HOOKS" "$F")
WHOLE=$(bash -c '. "$1/hook-input-lib.sh"; transcript_turn_window() { cat "$1"; }; transcript_user_texts "$2" 1' _ "$HOOKS" "$F")

# T1 — путь с помощником и путь без него обязаны дать одно (обещание окна).
[ "$WIN" = "$WHOLE" ] && ok || bad T1 "окно «${WIN}» ≠ весь файл «${WHOLE}»"
# T2 — последняя реплика владельца — нынешняя, строковая.
[ "$WIN" = "отлично, спасибо, дальше" ] && ok || bad T2 "окно отдало «${WIN}» вместо нынешней реплики"

# T3 — страж поправок на этом ходе: путь без помощника судит прошлую реплику («опять не так»),
# путь с помощником молчит. Вердикт стража зависит от того, нашёлся ли python3.
run_ucg() {  # run_ucg <библиотека ввода или пусто>
    printf '{"session_id":"s-str","transcript_path":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$F" \
        | env ${1:+INPUT_LIB="$1"} STATE_DIR="$STATE_DIR" bash "$HOOKS/user-correction-guard.sh" 2>/dev/null
}
cp "$HOOKS/hook-input-lib.sh" "$T/whole-lib.sh"
printf '%s\n' 'transcript_turn_window() { cat "$1"; }' >> "$T/whole-lib.sh"
OUT_WIN=$(run_ucg "")
rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
OUT_WHOLE=$(run_ucg "$T/whole-lib.sh")
[ "$OUT_WIN" = "$OUT_WHOLE" ] && ok || bad T3 "страж поправок: окно «${OUT_WIN:0:120}» ≠ весь файл «${OUT_WHOLE:0:120}»"

# T4 — контекстный сигнал (повторная правка файла после реплики) от текста реплики не зависит,
# а теряется вместе с ним: пустой LAST_USER_TEXT выводит стража раньше проверки CONTEXT_HIT.
# Прошлая реплика без слов поправки — словарь сработать не может; путь без помощника ловит
# повторную правку, путь с окном молчит.
G="$T/edit.jsonl"
{
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"сделай заголовок страницы синим"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e1",name:"Edit",input:{file_path:"/tmp/adv-twin-page.html",old_string:"a",new_string:"b"}}]}}'
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"e1",content:"ok"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Заголовок синий."}]}}'
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"верни прежний цвет и шрифт сделай крупнее"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e2",name:"Edit",input:{file_path:"/tmp/adv-twin-page.html",old_string:"b",new_string:"c"}}]}}'
} > "$G"
run_edit() {
    printf '{"session_id":"s-edit","transcript_path":"%s","tool_name":"Edit","tool_input":{"file_path":"/tmp/adv-twin-page.html","old_string":"b","new_string":"c"}}' "$G" \
        | env ${1:+INPUT_LIB="$1"} STATE_DIR="$STATE_DIR" bash "$HOOKS/user-correction-guard.sh" 2>/dev/null
}
rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
E_WIN=$(run_edit "")
rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
E_WHOLE=$(run_edit "$T/whole-lib.sh")
[ -n "$E_WHOLE" ] && ok || bad T4a "контроль: путь без помощника обязан поймать повторную правку после реплики"
[ "$E_WIN" = "$E_WHOLE" ] && ok || bad T4b "повторная правка после строковой реплики: окно «${E_WIN:0:80}» ≠ весь файл «${E_WHOLE:0:80}»"

echo "test_adv_twin_string_reply: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
