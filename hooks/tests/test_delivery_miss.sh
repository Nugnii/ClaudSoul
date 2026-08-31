#!/usr/bin/env bash
# test_delivery_miss.sh — прибор пропусков доставки различает подано / совпало / не совпало.
# en: delivery-miss instrument splits repeats into delivered / matched-only / not-matched.
#
# Проверяется: извлечение пар (sid, знание) из подписей repeat:/daily: журнала .seen,
# три категории по журналу подач, находка при доле «не совпало» > 50%, MIN_N-гейт.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/delivery-miss.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

run() { STATE_DIR="$TMP" DELIVERY_MISS_MIN_N="${1:-3}" bash "$SCRIPT" 2>&1; printf 'rc=%s' "$?"; }

# --- T1: журналов нет → код 0 ---
OUT=$(run)
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1]: $OUT"; }

# --- фикстура: 4 пары — delivered(s1,a), matched(s1,b), not_matched(s2,c и s2,daily-d) ---
cat > "$TMP/five-whys-s1.seen" << 'EOF'
turn:111|repeat:pattern-a,pattern-b|
EOF
cat > "$TMP/five-whys-s2.seen" << 'EOF'
turn:222|repeat:pattern-c|daily:pattern-d|
EOF
cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-01T10:00:00Z","file":"pattern-a.md","injected":true,"session_id":"s1","rank":1}
{"date":"2026-09-01T10:00:00Z","file":"pattern-b.md","injected":false,"session_id":"s1","rank":5}
EOF

OUT=$(run)
grep -q 'проверяемой доставкой: 4' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 пары]: $OUT"; }
grep -q 'подано и всё равно повтор: 1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T3 delivered]: $OUT"; }
grep -q 'но не подано.*: 1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 matched]: $OUT"; }
grep -q 'не совпало вовсе.*: 2 (50%)' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5 not_matched 50%]: $OUT"; }
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6 50% не выше порога]: $OUT"; }

# --- T7: перекос в «не совпало» → находка, код 1 ---
cat > "$TMP/five-whys-s3.seen" << 'EOF'
turn:333|daily:pattern-e|
EOF
OUT=$(run)
grep -q 'отбор слеп' <<< "$OUT" && grep -q 'rc=1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 находка]: $OUT"; }

# --- T8: MIN_N-гейт ---
OUT=$(run 50)
grep -q 'мало данных' <<< "$OUT" && grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8]: $OUT"; }

echo "delivery-miss: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
