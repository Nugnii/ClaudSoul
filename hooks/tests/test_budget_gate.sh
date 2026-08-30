#!/usr/bin/env bash
# test_budget_gate.sh — budget-gate.sh (ADR-010 Ф2): первый читатель itr_remaining_budget.
#
# Закрепляется:
#   - под действующей авторизацией гейт МОЛЧИТ при любом бюджете (поручение не лимитируется);
#   - без файла состояния авторизации — молчит (нет данных ≠ нарушение);
#   - unsolicited + бюджет исчерпан → инжект + событие budget_gate/surfaced;
#   - throttle: второй вызов в той же сессии молчит;
#   - бюджет не исчерпан → молчит;
#   - недеструктивный инструмент → молчит (оборона в глубину).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/budget-gate.sh"
STATE_LIB="$HOOK_DIR/intrusiveness-state-lib.sh"
AUTH_LIB="$HOOK_DIR/authorization-lib.sh"
for f in "$HOOK" "$STATE_LIB" "$AUTH_LIB"; do
    [ -f "$f" ] || { echo "FAIL: $f not found"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ITR_STATE_DIR="$TMP/state"
export STATE_DIR="$TMP/state"
export HOME="$TMP/home"
mkdir -p "$ITR_STATE_DIR" "$HOME/.claude/hooks/state"

# shellcheck source=/dev/null
source "$STATE_LIB"
# shellcheck source=/dev/null
source "$AUTH_LIB"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

assert_silent() { # $1 output, $2 label — тишина гейта
    [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: $1"
}
assert_contains() { # $1 haystack, $2 needle, $3 label — срабатывание
    if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: $1"; fi
}

run_gate() { # $1 sid, $2 tool → stdout
    jq -cn --arg sid "$1" --arg t "$2" '{session_id:$sid, tool_name:$t, hook_event_name:"PreToolUse"}' \
        | bash "$HOOK" 2>/dev/null
}

exhaust_budget() { # $1 sid — proactive_used до потолка
    itr_init_state "$1" >/dev/null 2>&1
    local path; path=$(_itr_state_path "$1")
    jq -c '.budget.proactive_used = .budget.proactive_max' "$path" > "$path.t" && mv "$path.t" "$path"
}

# --- T1: авторизация действует → молчит даже при пустом бюджете -------------------
auth_update g1 "делай"
exhaust_budget g1
OUT=$(run_gate g1 Edit)
assert_silent "$OUT" "T1 авторизация"

# --- T2: файла состояния нет → молчит ---------------------------------------------
exhaust_budget g2
OUT=$(run_gate g2 Edit)
assert_silent "$OUT" "T2 нет данных"

# --- T3: unsolicited + бюджет исчерпан → инжект + событие -------------------------
auth_update g3 "а зачем это всё?"
exhaust_budget g3
OUT=$(run_gate g3 Edit)
assert_contains "$OUT" "additionalContext" "T3a инжект"
assert_contains "$OUT" "Бюджет проактивных действий исчерпан" "T3b текст"
EV=$(jq -r '.events | last | "\(.type) \(.outcome)"' "$(_itr_state_path g3)")
[ "$EV" = "budget_gate surfaced" ] && ok || bad "T3c" "событие не записано: '$EV'"
PU=$(jq -r '.budget.proactive_used' "$(_itr_state_path g3)")
[ "$PU" = "3" ] && ok || bad "T3d" "budget_gate изменил бюджет: $PU"

# --- T4: throttle — второй вызов молчит -------------------------------------------
OUT=$(run_gate g3 Write)
assert_silent "$OUT" "T4 throttle"

# --- T5: бюджет не исчерпан → молчит ----------------------------------------------
auth_update g5 "почему так?"
itr_init_state g5 >/dev/null 2>&1
OUT=$(run_gate g5 Edit)
assert_silent "$OUT" "T5 бюджет не исчерпан"

# --- T6: недеструктивный инструмент → молчит --------------------------------------
auth_update g6 "почему так?"
exhaust_budget g6
OUT=$(run_gate g6 Read)
assert_silent "$OUT" "T6 Read"

echo ""
echo "test_budget_gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
