#!/usr/bin/env bash
# test_harvest_failures.sh — жнец провалов кладёт pending-кандидата и уважает окно и дедуп.
# en: failure harvester writes pending candidates and honours window, dedup and sources.
#
# Проверяется: инжект + серия провалов в окне → кандидат class=failure_after_injection;
# провал ВНЕ окна — нет; повторный прогон — без дублей; внешнее событие (ci-red) — тоже
# источник; ранги 4-6 (injected=false) кандидатов не порождают.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/disagreement-lib.sh"
# shellcheck source=/dev/null
source "$LIB"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PEND="$TMP/disagreement-pending-s1.jsonl"

cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-01T10:00:00Z","file":"pattern-a.md","confidence":4,"injected":true,"session_id":"s1","rank":1}
{"date":"2026-09-01T10:00:00Z","file":"pattern-ctl.md","confidence":4,"injected":false,"session_id":"s1","rank":5}
{"date":"2026-09-01T08:00:00Z","file":"pattern-old.md","confidence":4,"injected":true,"session_id":"s1","rank":2}
EOF
cat > "$TMP/error-streak-log-s1.jsonl" << 'EOF'
{"ts":"2026-09-01T10:10:00Z","attempts":2}
EOF

# --- T1: инжект за 10 минут до провала → один кандидат нужного класса ---
MADE=$(dis_harvest_failures "s1" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-a"' "$PEND" 2>/dev/null \
   && grep -q '"class":"failure_after_injection"' "$PEND"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: made=$MADE $(cat "$PEND" 2>/dev/null)"; fi

# --- T2: pattern-old (2 часа до провала) вне окна 30 мин — кандидата нет ---
grep -q '"key":"pattern-old"' "$PEND" 2>/dev/null \
    && { FAIL=$((FAIL+1)); echo "FAIL [T2]: вне окна попал"; } || PASS=$((PASS+1))

# --- T3: контрольный ранг (injected=false) кандидата не порождает ---
grep -q '"key":"pattern-ctl"' "$PEND" 2>/dev/null \
    && { FAIL=$((FAIL+1)); echo "FAIL [T3]: контроль попал"; } || PASS=$((PASS+1))

# --- T4: повторный прогон — дедуп, счёт 0 ---
MADE=$(dis_harvest_failures "s1" "$TMP" 30 3)
[ "$MADE" = "0" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4]: дубль made=$MADE"; }

# --- T5: внешнее событие (ci-red) — второй источник времени провала ---
cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-02T12:00:00Z","file":"pattern-b.md","confidence":3,"injected":true,"session_id":"s2","rank":1}
EOF
printf '{"ts":"2026-09-02T12:05:00Z","kind":"ci-red","detail":"прогон 1 для x: failure","status":"open"}\n' > "$TMP/pending-events.jsonl"
MADE=$(dis_harvest_failures "s2" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-b"' "$TMP/disagreement-pending-s2.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: made=$MADE"; fi

# --- T6: без источников провала — ноль, не падение ---
MADE=$(dis_harvest_failures "s3" "$TMP" 30 3)
[ "$MADE" = "0" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6]: made=$MADE"; }

# --- T7: hotfix-repeat и resurrected — тоже негативные события мира ---
# Диагностика 2026-08-31: в живом pending-events.jsonl 26 строк, из них 21 hotfix-repeat
# и 1 resurrected — селектор жнеца знал только revert|ci-red и был слеп к 22 из 26.
# Самый частый вид негативного события не жнётся вовсе.
cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-03T09:00:00Z","file":"pattern-hf.md","confidence":3,"injected":true,"session_id":"s4","rank":1}
{"date":"2026-09-03T09:00:00Z","file":"pattern-rz.md","confidence":3,"injected":true,"session_id":"s5","rank":1}
EOF
cat > "$TMP/pending-events.jsonl" << 'EOF'
{"ts":"2026-09-03T09:07:00Z","kind":"hotfix-repeat","detail":"второй fix того же файла","status":"open"}
{"ts":"2026-09-03T09:08:00Z","kind":"resurrected","detail":"закрытый пункт ожил","status":"open"}
EOF
MADE=$(dis_harvest_failures "s4" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-hf"' "$TMP/disagreement-pending-s4.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7a]: hotfix-repeat не пожат, made=$MADE"; fi
MADE=$(dis_harvest_failures "s5" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-rz"' "$TMP/disagreement-pending-s5.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7b]: resurrected не пожат, made=$MADE"; fi

echo "harvest-failures: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
