#!/usr/bin/env bash
# test_pre_compact_finalizer.sh — характеризующий тест PreCompact-финализатора.
# Обёртка над intrusiveness-state-lib (покрыта). Финализирует метрики до компакта;
# вывода не даёт. Тест (F8): без state выходит тихо, без SID тихо, не падает.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/pre-compact-finalizer.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_silent() { if [ -z "$1" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: получено: $1"; fi; }
assert_rc0() { if [ "$1" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

run() { printf '{"session_id":"%s"}' "$1" | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }

# нет состояния сессии → ранний выход, тишина
out=$(run "sid-without-state"); rc=$?
assert_silent "$out" "T1 no state → silent"
assert_rc0 "$rc" "T1 rc=0"

# без session_id → тишина
out=$(run ""); rc=$?
assert_silent "$out" "T2 no session_id → silent"
assert_rc0 "$rc" "T2 rc=0"

echo ""
echo "pre-compact-finalizer tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
