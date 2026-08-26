#!/usr/bin/env bash
# Unit tests for detection-signals-lib.sh
# Run: bash hooks/tests/test_detection_signals.sh

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/detection-signals-lib.sh"
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: expected='$expected' actual='$actual'")
    fi
}

# Helper: runs a function and converts exit code 0/1 to "match"/"nomatch"
run_node() {
    if ds_evaluate_node "$1" "$2" "$3" "$4"; then
        echo match
    else
        echo nomatch
    fi
}

run_signal() {
    if ds_evaluate_signal "$1" "$2" "$3" "$4"; then
        echo match
    else
        echo nomatch
    fi
}

# --- Fixtures ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Long file (350 lines)
LONG_FILE="$TMPDIR/PLAN.md"
seq 1 350 > "$LONG_FILE"

# Short file (50 lines)
SHORT_FILE="$TMPDIR/notes.md"
seq 1 50 > "$SHORT_FILE"

# Pattern file with blocker + detection_signals
BLOCKER_PATTERN="$TMPDIR/pattern-test-blocker.md"
cat > "$BLOCKER_PATTERN" <<'EOF'
---
name: test blocker pattern
confidence: 5
confirmed_count: 9
blocker: true
blocker_reminder: "test reminder text"
detection_signals: |
  [
    {
      "name": "long_doc_edit",
      "all_of": [
        {"tool_matches": ["Edit", "Write"]},
        {"file_path_regex": "(^|/)PLAN\\.md$"},
        {"file_size_min_lines": 300}
      ]
    },
    {
      "name": "destructive_bash",
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"any_of": [
          {"tool_input_contains": "rm -rf"},
          {"tool_input_contains": "git push --force"}
        ]}
      ]
    }
  ]
---
Body text here.
EOF

# Pattern without blocker flag
PLAIN_PATTERN="$TMPDIR/pattern-plain.md"
cat > "$PLAIN_PATTERN" <<'EOF'
---
name: plain pattern
confidence: 3
---
Body.
EOF

# Pattern with blocker:true but empty detection_signals
EMPTY_SIGNALS_PATTERN="$TMPDIR/pattern-empty-signals.md"
cat > "$EMPTY_SIGNALS_PATTERN" <<'EOF'
---
name: empty signals
blocker: true
---
Body.
EOF

# --- ds_has_blocker_flag ---
ds_has_blocker_flag "$BLOCKER_PATTERN"; assert_eq "blocker flag true" 0 $?
ds_has_blocker_flag "$PLAIN_PATTERN"; assert_eq "blocker flag absent" 1 $?
ds_has_blocker_flag "/nonexistent"; assert_eq "blocker flag no file" 1 $?

# --- ds_extract_signals ---
SIG=$(ds_extract_signals "$BLOCKER_PATTERN")
COUNT=$(printf '%s' "$SIG" | jq -r '. | length')
assert_eq "extract count=2" 2 "$COUNT"
FIRST_NAME=$(printf '%s' "$SIG" | jq -r '.[0].name')
assert_eq "extract first name" "long_doc_edit" "$FIRST_NAME"

EMPTY_SIG=$(ds_extract_signals "$EMPTY_SIGNALS_PATTERN")
assert_eq "extract empty returns []" "[]" "$EMPTY_SIG"

PLAIN_SIG=$(ds_extract_signals "$PLAIN_PATTERN")
assert_eq "extract plain returns []" "[]" "$PLAIN_SIG"

# --- ds_evaluate_node: tool_matches ---
assert_eq "tool_matches Edit in [Edit,Write]" match \
    "$(run_node '{"tool_matches":["Edit","Write"]}' "Edit" '{}' '')"
assert_eq "tool_matches Write in [Edit,Write]" match \
    "$(run_node '{"tool_matches":["Edit","Write"]}' "Write" '{}' '')"
assert_eq "tool_matches Bash not in [Edit,Write]" nomatch \
    "$(run_node '{"tool_matches":["Edit","Write"]}' "Bash" '{}' '')"
assert_eq "tool_matches empty array" nomatch \
    "$(run_node '{"tool_matches":[]}' "Edit" '{}' '')"

# --- ds_evaluate_node: file_path_regex ---
assert_eq "regex PLAN.md matches" match \
    "$(run_node '{"file_path_regex":"(^|/)PLAN\\.md$"}' "Edit" '{"file_path":"/foo/PLAN.md"}' '')"
assert_eq "regex PLAN.md no match on .py" nomatch \
    "$(run_node '{"file_path_regex":"(^|/)PLAN\\.md$"}' "Edit" '{"file_path":"/foo/bar.py"}' '')"
assert_eq "regex no file_path" nomatch \
    "$(run_node '{"file_path_regex":".*"}' "Edit" '{}' '')"

# --- ds_evaluate_node: file_size_min_lines ---
assert_eq "size min 300 on 350-line file" match \
    "$(run_node '{"file_size_min_lines":300}' "Edit" "{\"file_path\":\"$LONG_FILE\"}" '')"
assert_eq "size min 300 on 50-line file" nomatch \
    "$(run_node '{"file_size_min_lines":300}' "Edit" "{\"file_path\":\"$SHORT_FILE\"}" '')"
assert_eq "size min on nonexistent file = 0 lines" nomatch \
    "$(run_node '{"file_size_min_lines":300}' "Edit" '{"file_path":"/nonexistent/foo.md"}' '')"
assert_eq "size min 0 on nonexistent" match \
    "$(run_node '{"file_size_min_lines":0}' "Edit" '{"file_path":"/nonexistent/foo.md"}' '')"

# --- ds_evaluate_node: prompt_contains ---
assert_eq "prompt_contains substring" match \
    "$(run_node '{"prompt_contains":"plan"}' "Edit" '{}' 'edit the plan now')"
assert_eq "prompt_contains no match" nomatch \
    "$(run_node '{"prompt_contains":"xyz"}' "Edit" '{}' 'edit the plan now')"
assert_eq "prompt_contains empty prompt" nomatch \
    "$(run_node '{"prompt_contains":"plan"}' "Edit" '{}' '')"

# --- ds_evaluate_node: tool_input_contains ---
assert_eq "tool_input_contains rm -rf" match \
    "$(run_node '{"tool_input_contains":"rm -rf"}' "Bash" '{"command":"rm -rf /tmp/foo"}' '')"
assert_eq "tool_input_contains no match" nomatch \
    "$(run_node '{"tool_input_contains":"rm -rf"}' "Bash" '{"command":"ls -la"}' '')"

# --- Compositions: all_of ---
assert_eq "all_of all pass" match "$(run_node \
    '{"all_of":[{"tool_matches":["Edit"]},{"file_path_regex":".*\\.md$"}]}' \
    "Edit" '{"file_path":"/a.md"}' '')"
assert_eq "all_of one fails → nomatch" nomatch "$(run_node \
    '{"all_of":[{"tool_matches":["Edit"]},{"file_path_regex":".*\\.py$"}]}' \
    "Edit" '{"file_path":"/a.md"}' '')"
assert_eq "all_of empty → nomatch" nomatch "$(run_node '{"all_of":[]}' "Edit" '{}' '')"

# --- Compositions: any_of ---
assert_eq "any_of one passes" match "$(run_node \
    '{"any_of":[{"tool_matches":["Write"]},{"tool_matches":["Edit"]}]}' \
    "Edit" '{}' '')"
assert_eq "any_of none passes" nomatch "$(run_node \
    '{"any_of":[{"tool_matches":["Write"]},{"tool_matches":["Bash"]}]}' \
    "Edit" '{}' '')"
assert_eq "any_of empty → nomatch" nomatch "$(run_node '{"any_of":[]}' "Edit" '{}' '')"

# --- Nested composition ---
assert_eq "all_of > any_of → match" match "$(run_node \
    '{"all_of":[{"tool_matches":["Bash"]},{"any_of":[{"tool_input_contains":"rm"},{"tool_input_contains":"force"}]}]}' \
    "Bash" '{"command":"rm foo"}' '')"
assert_eq "all_of > any_of tool fails" nomatch "$(run_node \
    '{"all_of":[{"tool_matches":["Bash"]},{"any_of":[{"tool_input_contains":"rm"}]}]}' \
    "Edit" '{"command":"rm foo"}' '')"

# --- ds_evaluate_signal ---
SIGNAL='{"name":"x","all_of":[{"tool_matches":["Edit"]}]}'
assert_eq "signal all_of match" match "$(run_signal "$SIGNAL" "Edit" '{}' '')"
assert_eq "signal all_of nomatch" nomatch "$(run_signal "$SIGNAL" "Bash" '{}' '')"

ANY_SIGNAL='{"name":"y","any_of":[{"tool_matches":["Edit"]},{"tool_matches":["Write"]}]}'
assert_eq "signal any_of match" match "$(run_signal "$ANY_SIGNAL" "Write" '{}' '')"

NO_OP_SIGNAL='{"name":"z"}'
assert_eq "signal no op field → nomatch" nomatch "$(run_signal "$NO_OP_SIGNAL" "Edit" '{}' '')"

# --- ds_evaluate (end-to-end) ---
# Positive: Edit PLAN.md with 350 lines
NAME=$(ds_evaluate "$BLOCKER_PATTERN" "Edit" "{\"file_path\":\"$LONG_FILE\"}" '')
assert_eq "e2e Edit long PLAN.md → long_doc_edit" "long_doc_edit" "$NAME"

# Negative: Edit short file
NAME=$(ds_evaluate "$BLOCKER_PATTERN" "Edit" "{\"file_path\":\"$SHORT_FILE\"}" '' || true)
assert_eq "e2e Edit short file → empty" "" "$NAME"

# Positive: Bash rm -rf
NAME=$(ds_evaluate "$BLOCKER_PATTERN" "Bash" '{"command":"rm -rf /tmp/foo"}' '')
assert_eq "e2e Bash rm -rf → destructive_bash" "destructive_bash" "$NAME"

# Negative: Bash ls
NAME=$(ds_evaluate "$BLOCKER_PATTERN" "Bash" '{"command":"ls"}' '' || true)
assert_eq "e2e Bash ls → empty" "" "$NAME"

# Empty signals → no match
NAME=$(ds_evaluate "$EMPTY_SIGNALS_PATTERN" "Edit" "{\"file_path\":\"$LONG_FILE\"}" '' || true)
assert_eq "e2e empty signals → empty" "" "$NAME"

# --- Report ---
TOTAL=$((PASS + FAIL))
echo
echo "─── Detection signals tests ───"
echo "Passed: $PASS/$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  ✗ $t"
    done
    exit 1
fi
exit 0
