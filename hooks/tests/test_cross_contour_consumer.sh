#!/usr/bin/env bash
# СУДИТ: hooks/lib/cross-contour-lib.sh
# test_cross_contour_consumer.sh — v1.3.9 consumer for cross-contour-discoveries.jsonl
# Tests the exact inline logic from knowledge-activator.sh that surfaces
# entity↔knowledge mentions when a knowledge file is already in injection set.

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

# ОТБОР БЕРЁТСЯ У ВЛАДЕЛЬЦА, А НЕ ПОВТОРЯЕТСЯ ЗДЕСЬ (23 сентября 2026, D474, род K).
# Прежде тут лежала КОПИЯ блока из `hooks/knowledge-activator.sh` («mirrors the block»), и
# свидетель судил её, а не боевой отбор: прогон 23 сентября дал живой 0 и выхолощенный 0 —
# поломка настоящего механизма прошла бы мимо. Теперь и хук, и этот свидетель зовут
# `cc_consume` из `hooks/lib/cross-contour-lib.sh`.
CC_LIB="$(cd "$(dirname "$0")/../.." && pwd)/hooks/lib/cross-contour-lib.sh"
[ -f "$CC_LIB" ] || { echo "FAIL: нет $CC_LIB — отбор кросс-контурных упоминаний без владельца"; exit 1; }
# shellcheck source=/dev/null
. "$CC_LIB"
# Пустой файл источается молча, и тест падал бы кодом 127 «cc_consume: command not found» —
# срыв, неотличимый от случайной поломки оболочки. Отказ называется словом.
command -v cc_consume >/dev/null 2>&1 || { echo "FAIL: $CC_LIB не даёт cc_consume — владелец отбора пуст"; exit 1; }
run_consumer() { cc_consume "$@"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: basic match — one knowledge file with two entity mentions ---
LOG="$TMP/t1.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:01:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-B.md","matched":"B"}
EOF
SORTED="12|pattern-X.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "2" "$(echo "$OUT" | grep -c '↔')" "T1: two mentions surfaced"
assert_eq "  - pattern-X ↔ entity-A (упомянуто: A)" "$(echo "$OUT" | head -1)" "T1: first line format"

# --- Test 2: dedup — duplicate (KF,EF) filtered ---
LOG="$TMP/t2.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:05:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:10:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
EOF
SORTED="12|pattern-X.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "1" "$(echo "$OUT" | grep -c '↔')" "T2: duplicates deduped"

# --- Test 3: filter — unrelated knowledge not in SORTED excluded ---
LOG="$TMP/t3.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:01:00+00:00","knowledge_file":"pattern-UNRELATED.md","entity_file":"entity-Z.md","matched":"Z"}
EOF
SORTED="12|pattern-X.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "1" "$(echo "$OUT" | grep -c '↔')" "T3: unrelated filtered out"
assert_eq "0" "$(echo "$OUT" | grep -c 'UNRELATED')" "T3: unrelated not in output"

# --- Test 4: empty SORTED → no output ---
LOG="$TMP/t4.jsonl"
echo '{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}' > "$LOG"
OUT=$(run_consumer "$LOG" "")
assert_eq "" "$OUT" "T4: empty SORTED → no output"

# --- Test 5: missing log file → no output, no error ---
OUT=$(run_consumer "$TMP/nonexistent.jsonl" "12|pattern-X.md|...")
assert_eq "" "$OUT" "T5: missing file handled gracefully"

# --- Test 6: head -3 limit (4 distinct pairs → 3 shown) ---
LOG="$TMP/t6.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:01:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-B.md","matched":"B"}
{"ts":"2026-04-22T10:02:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-C.md","matched":"C"}
{"ts":"2026-04-22T10:03:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-D.md","matched":"D"}
EOF
SORTED="12|pattern-X.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "3" "$(echo "$OUT" | grep -c '↔')" "T6: head -3 limit respected"

# --- Test 7: missing matched field → no «упомянуто» suffix ---
LOG="$TMP/t7.jsonl"
echo '{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md"}' > "$LOG"
SORTED="12|pattern-X.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "  - pattern-X ↔ entity-A" "$OUT" "T7: missing matched → no suffix"

# --- Test 8: malformed line skipped, valid lines processed ---
LOG="$TMP/t8.jsonl"
cat > "$LOG" <<'EOF'
not valid json
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{broken
EOF
SORTED="12|pattern-X.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "1" "$(echo "$OUT" | grep -c '↔')" "T8: malformed lines skipped"

# --- Test 9: multiple entries in SORTED — all are candidates ---
LOG="$TMP/t9.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:01:00+00:00","knowledge_file":"pattern-Y.md","entity_file":"entity-B.md","matched":"B"}
{"ts":"2026-04-22T10:02:00+00:00","knowledge_file":"pattern-Z.md","entity_file":"entity-C.md","matched":"C"}
EOF
SORTED=$(printf '%s\n' \
  "12|pattern-X.md|NameX|desc|5|4|false|0|universal|confirmed|fresh" \
  "8|pattern-Y.md|NameY|desc|3|2|false|0|universal|confirmed|fresh")
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "2" "$(echo "$OUT" | grep -c '↔')" "T9: multiple SORTED entries matched"
assert_eq "1" "$(echo "$OUT" | grep -c 'pattern-X')" "T9: pattern-X present"
assert_eq "1" "$(echo "$OUT" | grep -c 'pattern-Y')" "T9: pattern-Y present"
assert_eq "0" "$(echo "$OUT" | grep -c 'pattern-Z')" "T9: pattern-Z excluded"

# --- Test 10 (v1.6/5.2): ranked relaxation — pair surfaces via similarity even if KF not in SORTED ---
LOG="$TMP/t10.jsonl"
RANKED="$TMP/t10-ranked.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-ORPHAN.md","entity_file":"entity-RELATED.md","matched":"R"}
EOF
cat > "$RANKED" <<'EOF'
{"knowledge_file":"pattern-ORPHAN.md","entity_file":"entity-RELATED.md","matched":"R","similarity":0.75,"ranked_at":"2026-04-24T00:00:00+00:00"}
EOF
# SORTED empty so KF isn't in inject set; relaxation path should still surface it
OUT=$(run_consumer "$LOG" "" "$RANKED" "0.6")
assert_eq "1" "$(echo "$OUT" | grep -c '↔')" "T10: high-sim pair surfaces with empty SORTED"
assert_eq "1" "$(echo "$OUT" | grep -c 'pattern-ORPHAN')" "T10: orphan pattern included"

# --- Test 11 (v1.6/5.2): threshold — similarity below threshold excluded ---
LOG="$TMP/t11.jsonl"
RANKED="$TMP/t11-ranked.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-LOW.md","entity_file":"entity-FAR.md","matched":"F"}
EOF
cat > "$RANKED" <<'EOF'
{"knowledge_file":"pattern-LOW.md","entity_file":"entity-FAR.md","matched":"F","similarity":0.3,"ranked_at":"2026-04-24T00:00:00+00:00"}
EOF
OUT=$(run_consumer "$LOG" "" "$RANKED" "0.6")
assert_eq "" "$OUT" "T11: below-threshold similarity excluded"

# --- Test 12 (v1.6/5.2): union — inject set OR similarity ---
LOG="$TMP/t12.jsonl"
RANKED="$TMP/t12-ranked.jsonl"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-X.md","entity_file":"entity-A.md","matched":"A"}
{"ts":"2026-04-22T10:01:00+00:00","knowledge_file":"pattern-Y.md","entity_file":"entity-B.md","matched":"B"}
EOF
# Y not in SORTED, but ranked high; X is in SORTED, not ranked → both should surface
cat > "$RANKED" <<'EOF'
{"knowledge_file":"pattern-Y.md","entity_file":"entity-B.md","matched":"B","similarity":0.8,"ranked_at":"2026-04-24T00:00:00+00:00"}
EOF
SORTED="12|pattern-X.md|NameX|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED" "$RANKED" "0.6")
assert_eq "2" "$(echo "$OUT" | grep -c '↔')" "T12: union path — both KF types surface"

# --- Test 13 (v1.6/5.3): session dedup — surfaced pair excluded on next call ---
LOG="$TMP/t13.jsonl"
RANKED="$TMP/t13-ranked.jsonl"
SURFACED="$TMP/t13-surfaced.txt"
cat > "$LOG" <<'EOF'
{"ts":"2026-04-22T10:00:00+00:00","knowledge_file":"pattern-S.md","entity_file":"entity-D.md","matched":"D"}
EOF
cat > "$RANKED" <<'EOF'
{"knowledge_file":"pattern-S.md","entity_file":"entity-D.md","matched":"D","similarity":0.75,"ranked_at":"2026-04-24T00:00:00+00:00"}
EOF
# First call — surfaces and records to dedup file
OUT1=$(run_consumer "$LOG" "" "$RANKED" "0.6" "$SURFACED")
assert_eq "1" "$(echo "$OUT1" | grep -c '↔')" "T13a: first call surfaces pair"
if [ -f "$SURFACED" ] && grep -Fxq "pattern-S.md|entity-D.md" "$SURFACED"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T13b]: surfaced file not populated"
fi
# Second call — same pair should be deduplicated
OUT2=$(run_consumer "$LOG" "" "$RANKED" "0.6" "$SURFACED")
assert_eq "" "$OUT2" "T13c: second call dedups via session file"

# --- Test 14 (v1.6/5.2): empty SORTED + no ranked → no output (short-circuit) ---
LOG="$TMP/t14.jsonl"
echo '{"knowledge_file":"pattern-Z.md","entity_file":"entity-Q.md","matched":"Q"}' > "$LOG"
OUT=$(run_consumer "$LOG" "" "" "0.6")
assert_eq "" "$OUT" "T14: no inject set + no ranked → silent"

# --- Test 15 (D1006, 19 октября 2026): журнал читается целиком ---
# Писатель пишет пару один раз, поэтому давнее открытие лежит в НАЧАЛЕ журнала, а за ним — сотни
# других пар. Окно «последние 200 строк» его не видело бы.
LOG="$TMP/t15.jsonl"
echo '{"knowledge_file":"pattern-OLD.md","entity_file":"entity-F.md","matched":"F"}' > "$LOG"
for i in $(seq 1 250); do
    printf '{"knowledge_file":"pattern-N%s.md","entity_file":"entity-N%s.md","matched":"N%s"}\n' "$i" "$i" "$i" >> "$LOG"
done
SORTED="12|pattern-OLD.md|Name|desc|5|4|false|0|universal|confirmed|fresh"
OUT=$(run_consumer "$LOG" "$SORTED")
assert_eq "1" "$(echo "$OUT" | grep -c 'pattern-OLD ↔ entity-F')" "T15: давнее открытие в начале журнала найдено"

echo ""
echo "Cross-contour consumer tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
