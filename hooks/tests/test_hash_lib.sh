#!/usr/bin/env bash
# test_hash_lib.sh — характеризующий тест для общего hash-lib.sh.
# Фиксирует детерминизм hash_value (тот же вход → тот же хеш, разный → разный),
# чтобы дедупликация копий из 5 хуков + TURN_KEY не изменила дедуп-поведение.
# Изоляция: lib через HASH_LIB env (по умолчанию — исходник проекта).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HASH_LIB="${HASH_LIB:-$HOOKS_DIR/hash-lib.sh}"

[ -f "$HASH_LIB" ] || { echo "FAIL: $HASH_LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$HASH_LIB"

PASS=0
FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}
assert_ne() {
    local a="$1" b="$2" label="$3"
    if [ "$a" != "$b" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$a' unexpectedly equals '$b'"; fi
}
assert_nonempty() {
    local v="$1" label="$2"
    if [ -n "$v" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: empty"; fi
}

# --- determinism: same input → same hash ---
h1=$(hash_value "alpha beta")
h2=$(hash_value "alpha beta")
assert_eq "$h1" "$h2" "T1: deterministic on identical input"

# --- sensitivity: different input → different hash ---
assert_ne "$(hash_value "abc")" "$(hash_value "abd")" "T2: differs on different input"

# --- empty string → deterministic non-empty hash ---
e1=$(hash_value "")
assert_nonempty "$e1" "T3a: empty input yields non-empty hash"
assert_eq "$e1" "$(hash_value "")" "T3b: empty input deterministic"

# --- special chars (spaces, quotes, slashes, unicode, colons) ---
s="a b\"c'd/e:ф:::g"
assert_eq "$(hash_value "$s")" "$(hash_value "$s")" "T4: special chars deterministic"
assert_ne "$(hash_value "$s")" "$(hash_value "${s}x")" "T5: near-miss differs"

# --- long input (TURN_KEY style: assistant + prompt prefix) ---
long=$(printf 'event:::%s:::%s' "$(head -c 500 /dev/zero | tr '\0' 'A')" "prompt-prefix")
assert_nonempty "$(hash_value "$long")" "T6: long input works"

# --- hash is a single token (no spaces) — needed since callers compare raw ---
out=$(hash_value "token check")
words=$(printf '%s' "$out" | wc -w | tr -d ' ')
assert_eq "$words" "1" "T7: hash is a single token"

echo ""
echo "hash-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
