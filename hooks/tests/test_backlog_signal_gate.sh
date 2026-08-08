#!/usr/bin/env bash
# test_backlog_signal_gate.sh — условие возврата сигналит только по открытому долгу.
#
# Повод (2026-08-07). Строки «📋 BACKLOG D16/D17 … можно калибровать» горели в каждой
# сессии ПОСЛЕ закрытия пунктов в v1.17.1 — сигнал проверял объём данных и не проверял
# состояние долга. На протухшем сигнале была построена рекомендация «калибруй», принятая
# собеседником; калибровка оказалась уже проведённой с вердиктом «менять нечего».
# Предмет замера не тот, о котором утверждение (pattern-subject-of-measurement-mismatch).
#
# Закрепляется:
#   T1/T2 — функционально в обе стороны: открытый пункт сигналит, закрытый молчит;
#   T3 — «в работе» (◐) считается открытым (v1.15.1: перевод в работу не гасит долг);
#   T4 — структурный инвариант: КАЖДАЯ эмиссия «📋 BACKLOG D» стоит под охраной
#        `_backlog_open` в своей if-строке. Новая эмиссия без охраны красит тест сама.
#        Это же — отрицательный контроль: на версии до правки T4 падает по построению.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COLLECTOR="$HOOKS_DIR/metrics-collector.sh"
[ -f "$COLLECTOR" ] || { echo "FAIL: $COLLECTOR not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Фикстуры окружения коллектора ------------------------------------------------
LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"
printf -- '---\nconfidence: 1\nimpact: 3\nconfirmed_count: 1\nstatus: active\n---\n' > "$LESSONS/case-x.md"
STATE="$TMP/state"; mkdir -p "$STATE"
# gentle-корпус ≥ 20 (условие D16/D17) и вмешательств ≥ 30 (условие D19)
printf '{"session_id":"s1","boundary":"stop","metrics":{"gentle_accepted":10,"gentle_ignored":15,"proactive_events":1,"override_events":40}}\n' \
    > "$STATE/intrusiveness-history.jsonl"
# срабатываний rework ≥ 30 (условие D18)
for i in $(seq 1 30); do echo '{"t":1}'; done > "$STATE/rework-fired-a.jsonl"

run_collector() { # $1 = BACKLOG fixture
    rm -f "$STATE/metrics.md"
    CLAUDSOUL_BACKLOG="$1" CLAUDSOUL_MEASURE_DUE="$TMP/no-such.sh" \
    LESSONS_DIR="$LESSONS" STATE_DIR="$STATE" PRED_SCAN_ROOTS="$TMP/noproj" \
        bash "$COLLECTOR" >/dev/null 2>&1 || true
    cat "$STATE/metrics.md" 2>/dev/null
}

# --- T1: D18 открыт (☐) → сигналит; D16/D17/D19 закрыты (отсутствуют) → молчат ----
B1="$TMP/backlog-open.md"
printf -- '- ☐ **D18** порог не калиброван\n' > "$B1"
OUT=$(run_collector "$B1")
echo "$OUT" | grep -Fq "📋 BACKLOG D18" && ok || bad "T1a" "открытый D18 не сигналит"
echo "$OUT" | grep -Fq "📋 BACKLOG D16/D17" && bad "T1b" "закрытый D16/D17 сигналит" || ok
echo "$OUT" | grep -Fq "📋 BACKLOG D19" && bad "T1c" "закрытый D19 сигналит" || ok

# --- T2: D18 закрыт (нет в файле) → молчит при выполненном условии ---------------
B2="$TMP/backlog-closed.md"
printf -- '- ☐ **D99** другой пункт\n' > "$B2"
OUT2=$(run_collector "$B2")
echo "$OUT2" | grep -Fq "📋 BACKLOG D18" && bad "T2" "закрытый D18 сигналит" || ok

# --- T3: «в работе» (◐) — открыт --------------------------------------------------
B3="$TMP/backlog-wip.md"
printf -- '- \xe2\x97\x90 **D18** взят в работу\n' > "$B3"
OUT3=$(run_collector "$B3")
echo "$OUT3" | grep -Fq "📋 BACKLOG D18" && ok || bad "T3" "◐ D18 (в работе) не считается открытым"

# --- T4: структурный инвариант — все эмиссии под охраной --------------------------
# Комментарии — не эмиссии (ds_code_only, v1.16.2): первая непробельная — «#».
UNGUARDED=$(awk '
    /^[[:space:]]*#/ { next }
    /if / { last_if = $0 }
    /📋 BACKLOG D/ {
        if (last_if !~ /_backlog_open/) { print NR": "$0; n++ }
    }
    END { exit (n > 0 ? 1 : 0) }
' "$COLLECTOR") && ok || bad "T4" "эмиссии без охраны _backlog_open:
$UNGUARDED"

echo ""
echo "test_backlog_signal_gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
