#!/usr/bin/env bash
# test_dead_sensor_check.sh — молчащий признак виден, сработавший — нет.
#
# Результат: признак, объявленный в знаниях и ни разу не сработавший за окно, попадает в
#            список; сработавший не попадает; пустое состояние не выдаётся за находку
# Проверка результата: bash hooks/tests/test_dead_sensor_check.sh даёт 0
#
# Повод (D204): `fix-level-check` за 33 дня не создал ни одного файла состояния, и это
# обнаружил человек, а не механизм. Молчание сенсора читается как «нарушений нет».
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · сработавший признак молчащим не считается;
#   · журналов нет вовсе → скрипт молчит с кодом 0, а не объявляет все признаки мёртвыми
#     (это ровно та ошибка, ради которой заведён отрицательный контроль в реплеях);
#   · знаний нет → скрипт не утверждает ничего.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/dead-sensor-check.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; LESSONS="$TMP/lessons"; mkdir -p "$STATE" "$LESSONS"

cat > "$LESSONS/pattern-x.md" <<'MD'
detection_signals: |
  [
    {"name": "signal_alive", "enforcement": "deny"},
    {"name": "signal_silent", "enforcement": "deny"}
  ]
MD
printf '{"date":"2026-08-29T10:00:00Z","signal":"signal_alive"}\n' > "$STATE/blocker-fired-00000000-0000-4000-8000-000000000001.jsonl"

run() { STATE_DIR="$STATE" LESSONS_DIR="$LESSONS" bash "$SCRIPT" 2>&1; }

# --- T1: молчащий признак назван ---
OUT=$(run); RC=$?
if grep -q 'signal_silent' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: молчащий признак не назван: '$OUT'"; fi
if [ "$RC" -eq 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: находка не сообщена кодом возврата: rc=$RC"; fi

# --- T6: КОНТРПРИМЕР — пример признака в META.md сенсором не считается ---
printf 'detection_signals: |\n  [{"name": "signal_from_schema_example"}]\n' > "$LESSONS/META.md"
OUT6=$(run)
if ! grep -q 'signal_from_schema_example' <<< "$OUT6"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: пример из схемы META.md объявлен молчащим сенсором"; fi
rm -f "$LESSONS/META.md"

# --- T2: КОНТРПРИМЕР — сработавший признак молчащим не считается ---
if ! grep -q '· signal_alive' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: сработавший признак объявлен молчащим"; fi

# --- T3: КОНТРПРИМЕР — журналов нет → код 0, ничего не утверждается ---
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
OUT3=$(STATE_DIR="$EMPTY" LESSONS_DIR="$LESSONS" bash "$SCRIPT" 2>&1); RC3=$?
if [ "$RC3" -eq 0 ] && grep -q 'сравнивать не с чем' <<< "$OUT3"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: пустое состояние: rc=$RC3 '$OUT3'"; fi

# --- T4: КОНТРПРИМЕР — знаний нет → скрипт не утверждает ничего ---
NOLES="$TMP/noles"; mkdir -p "$NOLES"
OUT4=$(STATE_DIR="$STATE" LESSONS_DIR="$NOLES" bash "$SCRIPT" 2>&1); RC4=$?
if [ "$RC4" -eq 0 ] && grep -q 'не найдено' <<< "$OUT4"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: без знаний: rc=$RC4 '$OUT4'"; fi

# --- T5: все признаки сработали → находки нет ---
printf '{"date":"2026-08-29T11:00:00Z","signal":"signal_silent"}\n' >> "$STATE/blocker-fired-00000000-0000-4000-8000-000000000001.jsonl"
OUT5=$(run); RC5=$?
if [ "$RC5" -eq 0 ] && grep -q 'молчащих нет' <<< "$OUT5"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: все сработали, а находка есть: rc=$RC5 '$OUT5'"; fi

# --- T7 (D1006, 19 октября 2026): окно — 40 СЕССИЙ, а не 40 файлов ---
# У каждой из 40 сессий по три журнала (родитель и два субагента); `signal_silent` сработал только в
# 20-й сессии от свежей. По файлам окно взяло бы около 13 сессий, и признак ложно числился бы молчащим.
ST7="$TMP/state7"; mkdir -p "$ST7"
for i in $(seq 1 40); do
    sid=$(printf '00000000-0000-4000-8000-%012d' "$i"); t="20260101$(printf '%02d%02d' $((i / 60)) $((i % 60)))"
    for a in "" ".agent-a1" ".agent-a2"; do
        f="$ST7/blocker-fired-$sid$a.jsonl"
        printf '{"date":"2026-08-29T10:00:00Z","signal":"signal_alive"}\n' > "$f"; touch -t "$t" "$f"
    done
done
f="$ST7/blocker-fired-$(printf '00000000-0000-4000-8000-%012d' 21).jsonl"
printf '{"date":"2026-08-29T10:00:00Z","signal":"signal_silent"}\n' >> "$f"; touch -t 202601010021 "$f"
OUT7=$(STATE_DIR="$ST7" LESSONS_DIR="$LESSONS" bash "$SCRIPT" 2>&1)
if ! grep -q 'signal_silent' <<< "$OUT7" && grep -q 'окно 40 сессий' <<< "$OUT7"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7]: окно не в сессиях: '$OUT7'"; fi

# --- T8: журнал реплея сессией не считается — его срабатывание признак не «оживляет» ---
ST8="$TMP/state8"; mkdir -p "$ST8"
printf '{"date":"2026-08-29T10:00:00Z","signal":"signal_alive"}\n' > "$ST8/blocker-fired-00000000-0000-4000-8000-000000000002.jsonl"
printf '{"date":"2026-08-29T10:00:00Z","signal":"signal_silent"}\n' > "$ST8/blocker-fired-replay-1-2.jsonl"
OUT8=$(STATE_DIR="$ST8" LESSONS_DIR="$LESSONS" bash "$SCRIPT" 2>&1)
if grep -q 'signal_silent' <<< "$OUT8"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8]: срабатывание из журнала реплея засчитано: '$OUT8'"; fi

# --- T9 (финальный скептик D1006): граница окна. Сессия A: родитель старше всех (`signal_silent`) и
# субагент новее всех; между ними — журнал сессии B. Окно в одну сессию — A с обоими журналами, и
# `signal_silent` сработал; прежний отбор ронял родителя A, едва встречал B, и признак ложно молчал.
ST9="$TMP/state9"; mkdir -p "$ST9"
A9=00000000-0000-4000-8000-0000000000a9; B9=00000000-0000-4000-8000-0000000000b9
printf '{"signal":"signal_silent"}\n' > "$ST9/blocker-fired-$A9.jsonl"; touch -t 202601010001 "$ST9/blocker-fired-$A9.jsonl"
printf '{"signal":"signal_alive"}\n' > "$ST9/blocker-fired-$B9.jsonl"; touch -t 202601010002 "$ST9/blocker-fired-$B9.jsonl"
printf '{"signal":"signal_alive"}\n' > "$ST9/blocker-fired-$A9.agent-x1.jsonl"; touch -t 202601010003 "$ST9/blocker-fired-$A9.agent-x1.jsonl"
OUT9=$(STATE_DIR="$ST9" LESSONS_DIR="$LESSONS" DEAD_SENSOR_SESSIONS=1 bash "$SCRIPT" 2>&1)
if ! grep -q 'signal_silent' <<< "$OUT9" && grep -q 'окно 1 сессий, журналов 2' <<< "$OUT9"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9]: сессия окна потеряла журнал на границе: '$OUT9'"; fi

# --- T10: битая строка в журнале окна не делает молчащими все признаки разом ---
printf 'not json\n' >> "$ST9/blocker-fired-$A9.agent-x1.jsonl"
OUT10=$(STATE_DIR="$ST9" LESSONS_DIR="$LESSONS" DEAD_SENSOR_SESSIONS=1 bash "$SCRIPT" 2>&1)
if ! grep -q 'signal_alive' <<< "$OUT10"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10]: одна битая строка обнулила сработавшие: '$OUT10'"; fi

# --- T11 (второй круг финального скептика D1006): строка-значение в журнале окна не делает молчащими все
# признаки. `fromjson?` разбирал `"s"`, `-r` печатал его без кавычек, и второй проход `jq -s` падал разбором.
printf '"s"\n[1, 2]\n' >> "$ST9/blocker-fired-$A9.agent-x1.jsonl"
OUT11=$(STATE_DIR="$ST9" LESSONS_DIR="$LESSONS" DEAD_SENSOR_SESSIONS=1 bash "$SCRIPT" 2>&1)
if ! grep -q 'signal_alive' <<< "$OUT11" && ! grep -q 'signal_silent' <<< "$OUT11"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T11]: строка-значение обнулила сработавшие: '$OUT11'"; fi

echo "dead sensor check: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
