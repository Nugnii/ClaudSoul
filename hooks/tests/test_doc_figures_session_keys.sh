#!/usr/bin/env bash
# СУДИТ: scripts/doc-figures.sh
# test_doc_figures_session_keys.sh — числа README о пометках и срабатываниях считаются по журналам
# НАСТОЯЩИХ сессий, а «сессии» — сессиями, а не файлами (D1006, 19 октября 2026).
#
# Повод: ключ `blocker_sessions` считал ФАЙЛЫ `blocker-fired-*.jsonl` — вместе с журналами субагентов
# и фикстурами прогонов, — и README писал «в 1185 сессиях» при 209 настоящих.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/doc-figures.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ST="$TMP/state"; mkdir -p "$ST"
S1=00000000-0000-4000-8000-000000000001; S2=00000000-0000-4000-8000-000000000002
L='{"date":"2026-10-19T10:00:00Z","signal":"x"}'
# Сессия 1: родитель и два субагента по строке; сессия 2: родитель, две строки; плюс фикстура реплея.
printf '%s\n' "$L" > "$ST/blocker-fired-$S1.jsonl"
printf '%s\n' "$L" > "$ST/blocker-fired-$S1.agent-a1.jsonl"
printf '%s\n' "$L" > "$ST/blocker-fired-$S1.agent-a2.jsonl"
printf '%s\n%s\n' "$L" "$L" > "$ST/blocker-fired-$S2.jsonl"
printf '%s\n' "$L" > "$ST/blocker-fired-replay-1-2.jsonl"
# Стражу доверия: две целые записи и битая у настоящей сессии, одна у фикстуры.
printf '%s\n%s\nnot json\n' '{"key":"a"}' '{"key":"b"}' > "$ST/trust-guard-fired-$S1.jsonl"
printf '%s\n' '{"key":"c"}' > "$ST/trust-guard-fired-probe-x.jsonl"

fig() { STATE_DIR="$ST" bash "$SCRIPT" "$1" 2>/dev/null; }

[ "$(fig blocker_sessions)" = "2" ] && ok || bad T1 "сессий $(fig blocker_sessions), ждали 2 (журналы субагентов и фикстура сессиями не являются)"
[ "$(fig blocker_markers)" = "5" ] && ok || bad T2 "пометок $(fig blocker_markers), ждали 5 (без строки фикстуры)"
[ "$(fig trust_guard_firings)" = "2" ] && ok || bad T3 "срабатываний $(fig trust_guard_firings), ждали 2 (без битой строки и фикстуры)"
# Контрпример: журналов нет вовсе — n/a, а не ноль.
[ "$(STATE_DIR="$TMP/none" bash "$SCRIPT" blocker_sessions 2>/dev/null)" = "n/a" ] && ok || bad T4 "без журналов не n/a"

echo "doc figures session keys: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
