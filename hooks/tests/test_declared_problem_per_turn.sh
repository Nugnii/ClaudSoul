#!/usr/bin/env bash
# test_declared_problem_per_turn.sh — носитель проверяется ПОСЛЕ находки, а не за сессию.
#
# Результат: находка в ходе требует записи в носитель В ЭТОМ ЖЕ ходе
# Проверка результата: bash hooks/tests/test_declared_problem_per_turn.sh даёт 0
#
# Повод, измеренный 29 августа 2026. `declared-problem-recorded.sh` сверял время носителя
# (BACKLOG.md, база знаний) с НАЧАЛОМ СЕССИИ. В длинной сессии носитель меняется на первом
# часе — и дальше страж молчит до конца, сколько бы находок ни прозвучало. Живой случай
# того же дня: за сессию BACKLOG.md переписан на закрытии D105-D109, после чего десять
# срабатываний `discovery:` в журнале гейта не дали ни одного напоминания, и ход, где
# разбор дошёл до корня и не оставил исхода, прошёл молча.
#
# Предмет проверки был задан ГРАНИЦЕЙ СЕССИИ, а нужное состояние — «записано ПОСЛЕ
# находки». Это тот же род, что чинили в тот же день у гейта разбора: предмет берётся
# по тому, что удобно наблюдать, а не по тому, о чём утверждение.
#
# КОНТРПРИМЕР: ход, где находка прозвучала И носитель изменён после начала хода, молчания
# не нарушает — иначе страж станет фоном на здоровой работе.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/declared-problem-recorded.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SID="turn-test"
STATE="$TMP/state"; mkdir -p "$STATE"
BACKLOG="$TMP/BACKLOG.md"
LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"

USER_TEXT="разбери это"
TURN_KEY=$(printf '%s\n' "$USER_TEXT" | cksum | awk '{print $1}')

# Времена задаются ОДНОЙ шкалой. Первая версия этой фикстуры ставила время файла через
# `touch -t` (локальная зона), а метку хода — строкой «…Z» (UTC): на машине в CEST
# расхождение в два часа переворачивало вердикт, и падал тест, а не механизм. Двух шкал
# в одной сверке быть не должно — эпоха здесь единственная.
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
NOW=$(date -u +%s)
T_SESSION_START=$((NOW - 10800))   # начало сессии
T_BEFORE_TURN=$((NOW - 7200))      # носитель менялся ДО хода
T_TURN_START=$((NOW - 3600))       # начало хода
T_IN_TURN=$((NOW - 60))            # носитель менялся В ходе
TURN_START_ISO=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$T_TURN_START")
set_mtime() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }

TRANSCRIPT="$TMP/t.jsonl"
{
  printf '{"message":{"role":"user","content":"старое"},"timestamp":"2026-01-01T00:00:00Z"}\n'
  printf '{"message":{"role":"assistant","content":"ответ"},"timestamp":"2026-01-01T00:00:05Z"}\n'
  printf '{"message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$TURN_START_ISO"
} > "$TRANSCRIPT"

# Журнал гейта: находка прозвучала В ЭТОМ ходе.
printf 'turn:%s|discovery:123|\n' "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
printf '{}' > "$STATE/intrusiveness-${SID}.json"
set_mtime "$STATE/intrusiveness-${SID}.json" "$T_SESSION_START"

run_hook() {
    STATE_DIR="$STATE" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" \
    bash "$HOOK" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TRANSCRIPT"}
PAYLOAD
}

# --- T1: носитель менялся ПОСЛЕ начала сессии, но ДО хода → страж обязан говорить ---
printf '# долг\n' > "$BACKLOG"
set_mtime "$BACKLOG" "$T_BEFORE_TURN"
OUT=$(run_hook)
if grep -q 'закрытого списка' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: носитель не менялся в ходе, а исход не потребован: '$OUT'"; fi
if grep -q 'В ЭТОМ ходе' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: граница проверки не названа ходом"; fi

# --- T2: КОНТРПРИМЕР — носитель изменён В ХОДЕ → молчание ---
set_mtime "$BACKLOG" "$T_IN_TURN"
OUT2=$(run_hook)
if [ -z "$OUT2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: запись в ходе есть, а страж говорит: '$OUT2'"; fi

# --- T3: КОНТРПРИМЕР — находки в ЭТОМ ходе не было → молчание ---
printf 'turn:999999|discovery:123|\n' > "$STATE/five-whys-${SID}.seen"
set_mtime "$BACKLOG" "$T_BEFORE_TURN"
OUT3=$(run_hook)
if [ -z "$OUT3" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: находки в ходе нет, а страж говорит: '$OUT3'"; fi

echo "declared problem per turn: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
