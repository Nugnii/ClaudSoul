#!/usr/bin/env bash
# test_ablation_journal.sh — журнал задач ablation: append-only, гварды дисциплины.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/ablation/journal.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if echo "$1" | grep -Fq "$2"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"

# --- T1: register выдаёт неизменяемый task_id и пишет событие ---
ID=$(bash "$SCRIPT" register "починить парсер дат" "/tmp/proj")
assert_contains "$ID" "t-" "T1: task_id выдан"
assert_contains "$(cat "$ABLATION_DIR/journal.jsonl")" "\"e\":\"register\"" "T1b: событие записано"

# --- T2: classify eligible один раз — ок; второй раз — отказ ---
bash "$SCRIPT" classify "$ID" eligible "автономная, DoD есть" bugfix low && ok || bad "T2" "classify упал"
OUT=$(bash "$SCRIPT" classify "$ID" ineligible 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T2b" "повторная классификация прошла (rc=0)"
assert_contains "$OUT" "уже классифицирована" "T2c: причина отказа названа"

# --- T3: classify незарегистрированной — отказ ---
OUT=$(bash "$SCRIPT" classify "t-nope" eligible 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3" "классификация незарегистрированной прошла"

# --- T4: неизвестный класс — отказ ---
OUT=$(bash "$SCRIPT" classify "$ID" maybe 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4" "неизвестный класс принят"

# --- T5: funnel считает воронку ---
ID2=$(bash "$SCRIPT" register "вторая задача")
bash "$SCRIPT" classify "$ID2" nonsubstantive "болтовня" >/dev/null 2>&1
OUT=$(bash "$SCRIPT" funnel)
assert_contains "$OUT" "\"registered\": 2" "T5: registered=2"
assert_contains "$OUT" "\"eligible\": 1" "T5b: eligible=1"
assert_contains "$OUT" "\"substantive\": 1" "T5c: nonsubstantive не считается substantive"

# --- T6: show находит все события задачи ---
OUT=$(bash "$SCRIPT" show "$ID")
assert_contains "$OUT" "register" "T6: register в show"
assert_contains "$OUT" "classify" "T6b: classify в show"

echo "test_ablation_journal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
