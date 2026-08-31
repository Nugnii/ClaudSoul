#!/usr/bin/env bash
# test_injection_outcome.sh — прибор «инжект → исход» джойнит журналы и находит шум якорей.
# en: injection-outcome instrument joins journals and flags anchor noise above threshold.
#
# Проверяется: джойн по (session, knowledge), исключение slot=research из основного среза,
# отдельный счёт сирот (вердикт без инжекта), MIN_N-гейт, код 1 на доле «не к месту» > 50%.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/injection-outcome.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

run() { STATE_DIR="$TMP" INJECTION_OUTCOME_SINCE="2026-01-01" INJECTION_OUTCOME_MIN_N="${2:-3}" bash "$SCRIPT" 2>&1; printf 'rc=%s' "$?"; }

# --- T1: журналов нет → код 0, не падение ---
OUT=$(run)
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1]: $OUT"; }

# --- фикстура: 3 инжекта в основном срезе (2 not_applicable, 1 confirmed) → 66% > 50 ---
cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-01T10:00:00Z","file":"pattern-a.md","injected":true,"session_id":"s1","rank":1}
{"date":"2026-09-01T10:00:00Z","file":"pattern-b.md","injected":true,"session_id":"s1","rank":2}
{"date":"2026-09-01T10:00:00Z","file":"pattern-c.md","injected":true,"session_id":"s2","rank":1}
{"date":"2026-09-01T10:00:00Z","file":"case-r.md","injected":true,"session_id":"s2","rank":9,"slot":"research"}
{"date":"2026-09-01T10:00:00Z","file":"pattern-x.md","injected":false,"session_id":"s1","rank":5}
EOF
cat > "$TMP/disagreement-outcomes.jsonl" << 'EOF'
{"date":"2026-09-01T11:00:00Z","session":"s1","knowledge":"pattern-a.md","outcome":"not_applicable","case":"x"}
{"date":"2026-09-01T11:00:00Z","session":"s1","knowledge":"pattern-b.md","outcome":"not_applicable","case":"x"}
{"date":"2026-09-01T11:00:00Z","session":"s2","knowledge":"pattern-c.md","outcome":"confirmed_knowledge","case":"x"}
{"date":"2026-09-01T11:00:00Z","session":"s2","knowledge":"case-r.md","outcome":"not_applicable","case":"research-шум не в счёт"}
{"date":"2026-09-01T11:00:00Z","session":"s9","knowledge":"pattern-z.md","outcome":"confirmed_knowledge","case":"сирота"}
EOF

OUT=$(run)
grep -q 'инжектированных с исходом.*: 3' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 основной срез без research]: $OUT"; }
grep -q 'slot=research.*: 1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T3 research отдельно]: $OUT"; }
grep -q 'без инжекта в окне.*: 1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 сирота]: $OUT"; }
grep -q 'находки, не сбой' <<< "$OUT" && grep -q 'rc=1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5 находка 66%>50]: $OUT"; }

# --- T6: MIN_N выше n → «мало данных», код 0 ---
OUT=$(run "" 10)
grep -q 'мало данных' <<< "$OUT" && grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6 MIN_N-гейт]: $OUT"; }

echo "injection-outcome: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
