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
printf '{"date":"2026-08-29T10:00:00Z","signal":"signal_alive"}\n' > "$STATE/blocker-fired-s1.jsonl"

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
printf '{"date":"2026-08-29T11:00:00Z","signal":"signal_silent"}\n' >> "$STATE/blocker-fired-s1.jsonl"
OUT5=$(run); RC5=$?
if [ "$RC5" -eq 0 ] && grep -q 'молчащих нет' <<< "$OUT5"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: все сработали, а находка есть: rc=$RC5 '$OUT5'"; fi

echo "dead sensor check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
