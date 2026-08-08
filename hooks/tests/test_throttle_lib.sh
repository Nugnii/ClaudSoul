#!/usr/bin/env bash
# test_throttle_lib.sh — характеризующий тест для общего throttle-lib.sh.
# Фиксирует семантику per-session подавления повторов (throttle_file / throttle_seen
# / throttle_mark), чтобы дедупликация из 6 хуков не изменила поведение «маркер не
# появляется дважды в сессии». Изоляция: tmp-файлы, lib через THROTTLE_LIB env.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
THROTTLE_LIB="${THROTTLE_LIB:-$HOOKS_DIR/throttle-lib.sh}"

[ -f "$THROTTLE_LIB" ] || { echo "FAIL: $THROTTLE_LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$THROTTLE_LIB"

PASS=0
FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}
# seen → exit 0; not-seen → exit 1. Helpers translate to a stable string.
seen_str() { if throttle_seen "$1" "$2"; then echo seen; else echo unseen; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- throttle_file: single naming scheme ---
F=$(throttle_file "$TMP" docs-family SID123)
assert_eq "$F" "$TMP/docs-family-fired-SID123.jsonl" "T1: file naming scheme"

# --- not seen before any mark (file absent) ---
assert_eq "$(seen_str "$F" "alpha")" "unseen" "T2: unseen on absent file, no crash"

# --- mark then seen ---
throttle_mark "$F" "alpha"
assert_eq "$(seen_str "$F" "alpha")" "seen" "T3: seen after mark"

# --- different key still unseen (per-key dedup) ---
assert_eq "$(seen_str "$F" "beta")" "unseen" "T4: other key unseen"

# --- mark with extra diagnostic fields, still valid JSON, still seen ---
throttle_mark "$F" "beta" '"pattern":"p1","signal":"s1"'
assert_eq "$(seen_str "$F" "beta")" "seen" "T5a: seen after mark-with-extra"
if command -v jq >/dev/null 2>&1; then
    last=$(tail -1 "$F")
    parsed=$(echo "$last" | jq -r '.key + "|" + .pattern + "|" + .signal' 2>/dev/null)
    assert_eq "$parsed" "beta|p1|s1" "T5b: extra fields are valid JSON"
else
    PASS=$((PASS + 1))  # jq absent: skip JSON parse, count as pass
fi

# --- idempotent read: marking same key twice still reads as seen ---
throttle_mark "$F" "alpha"
assert_eq "$(seen_str "$F" "alpha")" "seen" "T6: re-mark keeps seen"

# --- keys with special chars (real blocker keys: pattern@/abs/path, pattern:signal) ---
K1="pattern-inside-out@/tmp/My Project/file.sh"
K2="pattern-x:cross_hook_recall_gate@correction-fired"
throttle_mark "$F" "$K1"
throttle_mark "$F" "$K2"
assert_eq "$(seen_str "$F" "$K1")" "seen" "T7: path-style key with spaces/slashes"
assert_eq "$(seen_str "$F" "$K2")" "seen" "T8: colon/at-style key"
assert_eq "$(seen_str "$F" "pattern-inside-out@/tmp/other.sh")" "unseen" "T9: near-miss key unseen"

# --- isolation by session: different sid → different file → key invisible ---
F2=$(throttle_file "$TMP" docs-family OTHER_SID)
assert_eq "$(seen_str "$F2" "alpha")" "unseen" "T10: other session does not see key"

# --- field is canonically "key" (single name across all hooks) ---
if command -v jq >/dev/null 2>&1; then
    keyval=$(grep -F '"key":"alpha"' "$F" | head -1 | jq -r '.key' 2>/dev/null)
    assert_eq "$keyval" "alpha" "T11: canonical field name is key"
else
    PASS=$((PASS + 1))
fi

echo ""
echo "throttle-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
