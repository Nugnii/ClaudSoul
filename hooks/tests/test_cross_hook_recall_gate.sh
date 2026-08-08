#!/usr/bin/env bash
# test_cross_hook_recall_gate.sh — cross-hook recall gate в blocker-tier-check.sh.
# Escalation для pattern-inside-out-blindness: сработавший guard этой сессии +
# Write → инжект cross_hook_recall_reminder. Изоляция через BLOCKER_STATE_DIR +
# BLOCKER_KNOWLEDGE_DIR.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/blocker-tier-check.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

PASS=0
FAIL=0
FAILED_TESTS=()

SID="gate-test-session"

# Run hook with given tool_name + file_path; returns stdout.
run_hook() {
    local tool="$1" fpath="$2"
    local input
    input=$(jq -nc --arg s "$SID" --arg t "$tool" --arg f "$fpath" \
        '{session_id:$s, tool_name:$t, tool_input:{file_path:$f, content:"x"}, cwd:"/tmp"}')
    printf '%s' "$input" \
        | BLOCKER_STATE_DIR="$STATE_DIR" BLOCKER_KNOWLEDGE_DIR="$KNOW_DIR" bash "$SCRIPT" 2>/dev/null
}

assert_contains() {
    local label="$1" needle="$2" hay="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: expected to contain '$needle', got: '$hay'")
    fi
}

assert_silent() {
    local label="$1" hay="$2"
    if [ -z "$hay" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: expected silent, got: '$hay'")
    fi
}

# --- Fixtures ---
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"
KNOW_DIR="$TMP/knowledge"; mkdir -p "$KNOW_DIR"

# Pattern opting into the gate. No `blocker: true` / detection_signals → only the
# gate can fire, isolating it from the signal loop.
cat > "$KNOW_DIR/pattern-test-gate.md" <<'EOF'
---
name: test cross-hook gate pattern
confidence: 5
confirmed_count: 27
cross_hook_recall_gate: true
cross_hook_recall_reminder: "TEST-REMINDER grep существующего тулинга до создания"
---
body
EOF

mark_guard() {
    printf '{"date":"now","x":1}\n' > "$STATE_DIR/${1}-${SID}.jsonl"
}
clear_state() {
    rm -f "$STATE_DIR"/*.jsonl 2>/dev/null
}

# 1. Write + allowlisted guard fired → gate fires with the gate reminder.
clear_state
mark_guard "correction-fired"
out=$(run_hook "Write" "/tmp/x.config.js")
assert_contains "fires: signal name" "cross_hook_recall_gate" "$out"
assert_contains "fires: gate reminder" "TEST-REMINDER" "$out"
assert_contains "fires: names guard" "after correction-fired" "$out"

# 2. Write, no guard fired → silent.
clear_state
out=$(run_hook "Write" "/tmp/x.config.js")
assert_silent "no guard → silent" "$out"

# 3. Read (not a create) + guard fired → silent (gate is Write-only).
clear_state
mark_guard "correction-fired"
out=$(run_hook "Read" "/tmp/x.config.js")
assert_silent "Read → silent" "$out"

# 4. Throttle: second identical Write after fire → silent.
clear_state
mark_guard "bulk-copy-fired"
out=$(run_hook "Write" "/tmp/a.sh")        # records throttle
out2=$(run_hook "Write" "/tmp/b.sh")       # same (pattern,guard) → suppressed
assert_contains "throttle: first fires" "cross_hook_recall_gate" "$out"
assert_silent "throttle: second silent" "$out2"

# 5. Non-allowlisted guard only (trust-guard not in default allowlist) → silent.
clear_state
mark_guard "trust-guard-fired"
out=$(run_hook "Write" "/tmp/x.config.js")
assert_silent "non-allowlisted guard → silent" "$out"

# 6. Guard fired but no pattern opts in → silent.
clear_state
mark_guard "correction-fired"
rm -f "$KNOW_DIR/pattern-test-gate.md"
out=$(run_hook "Write" "/tmp/x.config.js")
assert_silent "no opt-in pattern → silent" "$out"

# --- Summary ---
echo "test_cross_hook_recall_gate.sh: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
    printf '  %s\n' "${FAILED_TESTS[@]}"
    exit 1
fi
exit 0
