#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/user-correction-guard.sh
# test_adv_twin_agent_text_2mb.sh — противник окна хода (D498): `transcript_agent_text_before_reply`
# берёт окно с фиксированным захватом 2 МБ до реплики (`--before 2097152`), а не с последнего
# текста агента (`--from-agent` в помощнике есть, но не подключён). Текст агента, отстоящий от
# реплики больше чем на 2 МБ (между ними — крупный вывод инструмента), в окно не попадает:
# функция отдаёт пусто, а на всём файле — этот текст. Предметный признак стража поправок
# (пересечение реплики с объявленным агентом) на окне молчит, на всём файле срабатывает.
# Мир: наибольшее расстояние «начало последнего текста агента → реплика» по 2095 репликам —
# 1,83 МБ (e33272a5), строки до 11,5 МБ в расшифровках есть.
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
python3 - "$F" <<'PY'
import json, sys
def j(o): return json.dumps(o, ensure_ascii=False)
big = "строка лога выгрузки отчёта 0123456789 " * 70000   # ≈ 2,5 МБ в одной записи результата
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for o in [
        {"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": "собери отчёт по выплатам"}]}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Готово: отчёт по выплатам собран, таблица подчинённых заполнена"}]}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "cat export.log"}}]}},
        {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": big}]}},
        {"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": "отчёт по выплатам собран неверно, таблица подчинённых пустая"}]}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "ls"}}]}},
    ]:
        f.write(j(o) + "\n")
PY

WIN=$(bash -c '. "$1/hook-input-lib.sh"; transcript_agent_text_before_reply "$2"' _ "$HOOKS" "$F")
WHOLE=$(bash -c '. "$1/hook-input-lib.sh"; transcript_turn_window() { cat "$1"; }; transcript_agent_text_before_reply "$2"' _ "$HOOKS" "$F")
[ -n "$WHOLE" ] && ok || bad T0 "контроль: на всём файле текст агента до реплики обязан найтись"
[ "$WIN" = "$WHOLE" ] && ok || bad T1 "текст агента до реплики: окно «${WIN:0:60}» ≠ весь файл «${WHOLE:0:60}»"

cp "$HOOKS/hook-input-lib.sh" "$T/whole-lib.sh"
printf '%s\n' 'transcript_turn_window() { cat "$1"; }' >> "$T/whole-lib.sh"
run_ucg() {
    printf '{"session_id":"s-2mb","transcript_path":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$F" \
        | env ${1:+INPUT_LIB="$1"} STATE_DIR="$STATE_DIR" bash "$HOOKS/user-correction-guard.sh" 2>/dev/null
}
O_WIN=$(run_ucg "")
rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
O_WHOLE=$(run_ucg "$T/whole-lib.sh")
[ "$O_WIN" = "$O_WHOLE" ] && ok || bad T2 "страж поправок: окно «${O_WIN:0:80}» ≠ весь файл «${O_WHOLE:0:80}»"

echo "test_adv_twin_agent_text_2mb: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
