#!/usr/bin/env bash
# test_violation_class.sh — нарушение знания несёт адрес сигнала: три класса, не одно число.
#
# ПОВОД (диагностика 2026-08-31, D242). Запись applicable_not_followed не различала
# «сигнал не совпал / совпал и проигнорирован / заглушен троттлом» — а это три разных
# починки (пересмотр сигналов / лестница принуждения / ослабление троттла). Писатели
# обоих журналов существовали (rc_note_detection: act=said|muted с подписью;
# dis_close_outcome: исход с session+knowledge) — не было читателя-джойна.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/violation-class.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"

# said: страж сказал в сессии s1 про pattern-a — и знание всё равно не применено.
printf '{"ts":"2026-09-01T10:00:00Z","guard":"blocker-tier-check","act":"said","sig":"pattern-a:some_signal"}\n' \
    > "$STATE/detection-s1.jsonl"
# muted: страж заглушен троттлом в сессии s2 про pattern-b (подпись с путём через @).
printf '{"ts":"2026-09-01T11:00:00Z","guard":"blocker-tier-check","act":"muted","sig":"pattern-b@/some/path.md"}\n' \
    > "$STATE/detection-s2.jsonl"
# для s3 детект-строк нет вовсе → «сигнал не совпал».
cat > "$STATE/disagreement-outcomes.jsonl" << 'EOF'
{"date":"2026-09-01T12:00:00Z","session":"s1","knowledge":"pattern-a.md","outcome":"applicable_not_followed","case":"висело и не применил"}
{"date":"2026-09-01T12:01:00Z","session":"s2","knowledge":"pattern-b.md","outcome":"applicable_not_followed","case":"троттл съел"}
{"date":"2026-09-01T12:02:00Z","session":"s3","knowledge":"pattern-c.md","outcome":"applicable_not_followed","case":"сигнал мимо"}
{"date":"2026-09-01T12:03:00Z","session":"s1","knowledge":"pattern-x.md","outcome":"confirmed_knowledge","case":"не нарушение"}
EOF

OUT=$(STATE_DIR="$STATE" bash "$SCRIPT" 2>&1); RC=$?

ck() { if grep -qF -- "$1" <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [$2]: не найдено '$1'"; fi; }

# T1: три класса названы числом, каждый по одному
ck "said" "T1a: класс said"
ck "muted" "T1b: класс muted"
ck "не совпал" "T1c: класс не-совпал"
# T2: конкретные знания отнесены к своим классам
_l=$(grep "said" <<< "$OUT" || true)
if grep -q "pattern-a" <<< "$_l"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2a]: pattern-a не в said"; fi
_l=$(grep "muted" <<< "$OUT" || true)
if grep -q "pattern-b" <<< "$_l"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2b]: pattern-b не в muted"; fi
_l=$(grep "не совпал" <<< "$OUT" || true)
if grep -q "pattern-c" <<< "$_l"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2c]: pattern-c не в не-совпал"; fi
# T3: confirmed-исход в классификацию нарушений не попал
if grep -q "pattern-x" <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [T3]: confirmed-исход посчитан нарушением"
else PASS=$((PASS+1)); fi
# T4: артефакт написан
if [ -s "$STATE/violation-class-last.txt" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: артефакт не написан"; fi
# T5: rc 0/1
if [ "$RC" -le 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: rc=$RC"; fi

[ "$FAIL" -gt 0 ] && { echo "--- вывод ---"; printf '%s\n' "$OUT" | sed 's/^/  /'; }
echo "test_violation_class: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
