#!/usr/bin/env bash
# test_anchor_review_queue.sh — очередь пересмотра якорей растёт из not_applicable и молчит ниже порога.
# en: anchor review queue grows from not_applicable outcomes and stays silent below threshold.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/anchor-review-queue.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

run() { STATE_DIR="$TMP" ANCHOR_REVIEW_MIN_NA="${1:-3}" bash "$SCRIPT" 2>&1; printf 'rc=%s' "$?"; }

# --- T1: журнала нет → код 0 ---
OUT=$(run)
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1]: $OUT"; }

# --- фикстура: knowledge-a — 3 «не к месту» (в очередь), knowledge-b — 2 (нет), c — confirmed ---
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
for i in 1 2 3; do
    printf '{"date":"%s","session":"s%s","knowledge":"pattern-a.md","outcome":"not_applicable","case":"повод %s"}\n' "$NOW" "$i" "$i"
done > "$TMP/disagreement-outcomes.jsonl"
printf '{"date":"%s","session":"s1","knowledge":"pattern-b.md","outcome":"not_applicable","case":"x"}\n' "$NOW" >> "$TMP/disagreement-outcomes.jsonl"
printf '{"date":"%s","session":"s2","knowledge":"pattern-b.md","outcome":"not_applicable","case":"x"}\n' "$NOW" >> "$TMP/disagreement-outcomes.jsonl"
printf '{"date":"%s","session":"s1","knowledge":"pattern-c.md","outcome":"confirmed_knowledge","case":"x"}\n' "$NOW" >> "$TMP/disagreement-outcomes.jsonl"

OUT=$(run)
grep -q 'pattern-a.md.*3 раз' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 кандидат]: $OUT"; }
grep -q 'pattern-b' <<< "$OUT" && { FAIL=$((FAIL+1)); echo "FAIL [T3 ниже порога попал]: $OUT"; } || PASS=$((PASS+1))
grep -q 'находки, не сбой' <<< "$OUT" && grep -q 'rc=1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 код находки]: $OUT"; }

# --- T5: порог выше — очередь пуста, код 0 ---
OUT=$(run 5)
grep -q 'очередь пересмотра якорей пуста' <<< "$OUT" && grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5]: $OUT"; }

echo "anchor-review-queue: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
