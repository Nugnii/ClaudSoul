#!/usr/bin/env bash
# test_startup_signals.sh — v1.5.1-alpha: проверка startup signals (missing CLAUDE.md + global-lessons diff).
# Изоляция через HOME=$TMP — session-registry-lib и все хуки работают в sandbox.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not found"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly present"
    else PASS=$((PASS + 1)); fi
}

TMP=$(mktemp -d)
# Полная изоляция: sandbox HOME с копиями нужных хук-файлов
SANDBOX_HOME="$TMP/home"
mkdir -p "$SANDBOX_HOME/.claude/hooks" "$SANDBOX_HOME/.claude/hooks/state" "$SANDBOX_HOME/.claude/sessions" "$SANDBOX_HOME/.claude/global-lessons"
cp "$HOOKS_DIR/session-registry-lib.sh" "$SANDBOX_HOME/.claude/hooks/" 2>/dev/null || true
cp "$HOOKS_DIR/narrative-compose-lib.sh" "$SANDBOX_HOME/.claude/hooks/" 2>/dev/null || true

trap 'rm -rf "$TMP"' EXIT

run_session_start() {
    local sid="$1" cwd="$2" last_ended="$3"
    local last_session_file="$SANDBOX_HOME/.claude/sessions/last-session.json"
    if [ -n "$last_ended" ]; then
        printf '{"session_id":"%s","ended_at":"%s"}' "$sid" "$last_ended" > "$last_session_file"
    else
        rm -f "$last_session_file"
    fi
    echo "{\"session_id\":\"$sid\",\"source\":\"startup\",\"cwd\":\"$cwd\",\"hook_event_name\":\"SessionStart\"}" | \
        HOME="$SANDBOX_HOME" \
        NARRATIVE_GAP_HOURS=999999 \
        bash "$HOOK" >/dev/null 2>&1
    cat "$SANDBOX_HOME/.claude/hooks/state/startup-signals-${sid}.txt" 2>/dev/null || true
}

# --- Test 1: missing CLAUDE.md → init-project signal ---
mkdir -p "$TMP/proj-without"
OUT=$(run_session_start "test-sid-1" "$TMP/proj-without" "")
assert_contains "$OUT" "нет CLAUDE.md" "T1: missing CLAUDE.md detected"
assert_contains "$OUT" "/init-project" "T1: /init-project hint present"

# --- Test 2: CLAUDE.md present → no init-project signal ---
mkdir -p "$TMP/proj-with"
touch "$TMP/proj-with/CLAUDE.md"
OUT=$(run_session_start "test-sid-2" "$TMP/proj-with" "")
assert_not_contains "$OUT" "/init-project" "T2: no hint when CLAUDE.md exists"

# --- Test 3: knowledge delta → /reload hint ---
touch "$SANDBOX_HOME/.claude/global-lessons/case-v151-test-fixture.md"
LAST_ENDED=$(date -u -v-2d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "2 days ago" +"%Y-%m-%dT%H:%M:%SZ")
OUT=$(run_session_start "test-sid-3" "$TMP/proj-with" "$LAST_ENDED")
assert_contains "$OUT" "База знаний обновилась" "T3: knowledge delta detected"
assert_contains "$OUT" "/reload" "T3: /reload hint present"

# --- Test 4: no last session (bootstrap) → no reload hint ---
OUT=$(run_session_start "test-sid-4" "$TMP/proj-with" "")
assert_not_contains "$OUT" "/reload" "T4: no /reload hint when no last ended_at"

# --- Test 5: no new knowledge since last session → no /reload hint ---
# Age the fixture file back below the last_ended threshold
touch -t "202604200000" "$SANDBOX_HOME/.claude/global-lessons/case-v151-test-fixture.md" 2>/dev/null || true
LAST_ENDED_RECENT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OUT=$(run_session_start "test-sid-5" "$TMP/proj-with" "$LAST_ENDED_RECENT")
assert_not_contains "$OUT" "/reload" "T5: no /reload hint when knowledge older than last_ended"

# --- Test 6: ⚙️ AP3 silence debt carry-over from last history entry ---
HIST="$SANDBOX_HOME/.claude/hooks/state/intrusiveness-history.jsonl"
cat > "$HIST" <<'EOF'
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":2,"pending_topics":["topic-alpha","topic-beta"],"surfaced":0}}
EOF
OUT=$(run_session_start "test-sid-6" "$TMP/proj-with" "")
assert_contains "$OUT" "AP3 silence debt carry-over" "T6: AP3 carry-over hint present"
assert_contains "$OUT" "2 pending" "T6: pending count shown"
assert_contains "$OUT" "topic-alpha" "T6: topic list present"

# --- Test 7: AP3 skip when pending == 0 ---
cat > "$HIST" <<'EOF'
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":0,"pending_topics":[],"surfaced":3}}
EOF
OUT=$(run_session_start "test-sid-7" "$TMP/proj-with" "")
assert_not_contains "$OUT" "AP3 silence debt carry-over" "T7: AP3 hint absent when pending=0"

# --- Test 8: AP3 graceful when topics missing (legacy digest format) ---
cat > "$HIST" <<'EOF'
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":1,"surfaced":0}}
EOF
OUT=$(run_session_start "test-sid-8" "$TMP/proj-with" "")
assert_contains "$OUT" "AP3 silence debt carry-over" "T8: AP3 hint fires even without pending_topics"
assert_contains "$OUT" "1 pending" "T8: count shown without topics"

# --- Test 9: AP3 uses LAST history entry (multiple sessions) ---
cat > "$HIST" <<'EOF'
{"session_id":"old-sid","boundary":"stop","debt":{"pending":5,"pending_topics":["ancient"],"surfaced":0}}
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":0,"pending_topics":[],"surfaced":2}}
EOF
OUT=$(run_session_start "test-sid-9" "$TMP/proj-with" "")
assert_not_contains "$OUT" "AP3 silence debt carry-over" "T9: uses last entry (pending=0), not earlier"

# Clear AP3 history to isolate calibration tests
rm -f "$HIST"

CALIB_FILE="$SANDBOX_HOME/.claude/hooks/state/calibration-progress.json"
DONE_MARKER="$SANDBOX_HOME/.claude/hooks/state/calibration-v1.4-done.flag"

# --- Test 10: calibration under threshold → «копим» hint ---
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":5,"gentle_events_total":12,"proactive_events_total":3,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
rm -f "$DONE_MARKER"
OUT=$(run_session_start "test-sid-10" "$TMP/proj-with" "")
assert_contains "$OUT" "Калибровка v1.4.0: 5/30" "T10: under-threshold progress line present"
assert_contains "$OUT" "копим историю" "T10: accumulation phrasing"
assert_not_contains "$OUT" "готова" "T10: does not claim readiness"

# --- Test 11: calibration at threshold → «готова» hint ---
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":42,"gentle_events_total":120,"proactive_events_total":67,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
rm -f "$DONE_MARKER"
OUT=$(run_session_start "test-sid-11" "$TMP/proj-with" "")
assert_contains "$OUT" "Калибровка v1.4.0 готова" "T11: ready hint when valid>=threshold"
assert_contains "$OUT" "42/30" "T11: numerator/denominator shown"
assert_contains "$OUT" "gentle=120" "T11: gentle events total shown"
assert_contains "$OUT" "proactive=67" "T11: proactive events total shown"
assert_contains "$OUT" "scripts/calibrate.py" "T11: next-step pointer present"

# --- Test 12: done marker suppresses inject even at threshold ---
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":42,"gentle_events_total":120,"proactive_events_total":67,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
touch "$DONE_MARKER"
OUT=$(run_session_start "test-sid-12" "$TMP/proj-with" "")
assert_not_contains "$OUT" "Калибровка v1.4.0" "T12: done marker suppresses any calibration hint"

# --- Test 13: zero valid chunks → no hint (absence, not 0/30) ---
rm -f "$DONE_MARKER"
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":0,"gentle_events_total":0,"proactive_events_total":0,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
OUT=$(run_session_start "test-sid-13" "$TMP/proj-with" "")
assert_not_contains "$OUT" "Калибровка v1.4.0" "T13: zero valid chunks → silent (no noise)"

# --- Test 14: missing calibration file → no hint, no error ---
rm -f "$CALIB_FILE" "$DONE_MARKER"
OUT=$(run_session_start "test-sid-14" "$TMP/proj-with" "")
assert_not_contains "$OUT" "Калибровка v1.4.0" "T14: missing file → graceful skip"

echo ""
echo "Startup signals tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
