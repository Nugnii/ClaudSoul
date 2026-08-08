#!/usr/bin/env bash
# Unit tests for intrusiveness-state-lib.sh
# Run: bash hooks/tests/test_intrusiveness_lib.sh

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/intrusiveness-state-lib.sh"

# Isolate state to a temp dir — do NOT touch real ~/.claude/hooks/state
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export ITR_STATE_DIR="$TMP_DIR"

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

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: '$haystack' does not contain '$needle'")
    fi
}

assert_file_exists() {
    local label="$1" path="$2"
    if [ -f "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: expected file '$path' to exist")
    fi
}

# Метка времени «N суток назад» в UTC. Ключей `-j -v-45d` нет у GNU date: на Linux вызов
# печатал «invalid option -- 'j'» и возвращал пустую строку, из-за чего в состояние
# записывалось пустое created_at — файл выглядел неразбираемым, очистка его пропускала,
# и тест обвинял очистку в том, чего не делал он сам. Считаем эпоху арифметикой, затем
# форматируем: сначала GNU (`-d @эпоха`), потом BSD (`-r эпоха`).
iso_days_ago() {
    local epoch=$(( $(date -u +%s) - $1 * 86400 ))
    date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null && return
    date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ"
}

SID="test-session-$$"

# --- itr_init_state ---
itr_init_state "$SID"
STATE_PATH="$TMP_DIR/intrusiveness-${SID}.json"
assert_file_exists "init creates state file" "$STATE_PATH"
assert_eq "init sets gentle_max=5"      "5" "$(jq -r '.budget.gentle_max' "$STATE_PATH")"
assert_eq "init sets proactive_max=3"   "3" "$(jq -r '.budget.proactive_max' "$STATE_PATH")"
assert_eq "init sets gentle_used=0"     "0" "$(jq -r '.budget.gentle_used' "$STATE_PATH")"
assert_eq "init sets events empty"      "0" "$(jq -r '.events | length' "$STATE_PATH")"
assert_eq "init idempotent — same gentle_used after re-init" "0" \
    "$(itr_init_state "$SID"; jq -r '.budget.gentle_used' "$STATE_PATH")"

# --- itr_remaining_budget ---
assert_eq "remaining gentle on fresh state" "5" "$(itr_remaining_budget "$SID" gentle)"
assert_eq "remaining proactive on fresh state" "3" "$(itr_remaining_budget "$SID" proactive)"
assert_eq "remaining unknown type returns 0" "0" "$(itr_remaining_budget "$SID" bogus)"

# --- itr_log_event: gentle accepted ---
itr_log_event "$SID" "gentle" "accepted" 2 "suggested gate reformulation"
assert_eq "after gentle accepted: gentle_used=1" "1" "$(jq -r '.budget.gentle_used' "$STATE_PATH")"
assert_eq "after gentle accepted: accepted metric=1" "1" "$(jq -r '.metrics.gentle_accepted' "$STATE_PATH")"
assert_eq "after gentle accepted: events=1" "1" "$(jq -r '.events | length' "$STATE_PATH")"
assert_eq "remaining gentle decreased to 4" "4" "$(itr_remaining_budget "$SID" gentle)"

# --- itr_log_event: gentle ignored triggers shrink ---
itr_log_event "$SID" "gentle" "ignored" 1 "user moved on"
assert_eq "ignored does not increment gentle_used" "1" "$(jq -r '.budget.gentle_used' "$STATE_PATH")"
assert_eq "ignored increments gentle_ignored" "1" "$(jq -r '.metrics.gentle_ignored' "$STATE_PATH")"
assert_eq "ignored shrinks gentle_max" "4" "$(jq -r '.budget.gentle_max' "$STATE_PATH")"
assert_eq "ignored records shrink event" "1" "$(jq -r '.budget.shrink_events' "$STATE_PATH")"
assert_eq "after shrink: remaining gentle = 4-1 = 3" "3" "$(itr_remaining_budget "$SID" gentle)"

# --- itr_log_event: proactive event ---
itr_log_event "$SID" "proactive" "accepted" 3 "pre-read follow-up file"
assert_eq "proactive_used=1" "1" "$(jq -r '.budget.proactive_used' "$STATE_PATH")"
assert_eq "proactive_events metric=1" "1" "$(jq -r '.metrics.proactive_events' "$STATE_PATH")"

# --- itr_log_event: override detected by silence_cost threshold ---
itr_log_event "$SID" "gentle" "accepted" 5 "imminent irreversible action"
assert_eq "silence_cost=5 increments override_events" "1" "$(jq -r '.metrics.override_events' "$STATE_PATH")"

# --- itr_add_silence_debt and itr_mark_debt_surfaced ---
itr_add_silence_debt "$SID" "race condition on shared registry" 3
assert_eq "debt added" "1" "$(jq -r '.silence_debt | length' "$STATE_PATH")"
assert_eq "debt status pending" "pending" "$(jq -r '.silence_debt[0].status' "$STATE_PATH")"

itr_mark_debt_surfaced "$SID" "race condition"
assert_eq "debt surfaced after match" "surfaced" "$(jq -r '.silence_debt[0].status' "$STATE_PATH")"

itr_log_event "$SID" "silence_debt" "surfaced" 3 "surfaced during natural pause"
assert_eq "silence_debt_surfaced metric=1" "1" "$(jq -r '.metrics.silence_debt_surfaced' "$STATE_PATH")"

# --- itr_format_context produces a block when state has events ---
CTX=$(itr_format_context "$SID")
assert_contains "context includes Budget gentle" "$CTX" "Budget gentle:"
assert_contains "context mentions shrinks when present" "$CTX" "Shrinks:"
assert_contains "context notes emergency threshold" "$CTX" "emergency override"

# --- itr_format_context returns nothing on a fresh empty state ---
EMPTY_SID="empty-session-$$"
itr_init_state "$EMPTY_SID"
EMPTY_CTX_RC=0
EMPTY_CTX=$(itr_format_context "$EMPTY_SID") || EMPTY_CTX_RC=$?
assert_eq "fresh state: format_context returns non-zero" "1" "$EMPTY_CTX_RC"
assert_eq "fresh state: format_context stdout empty" "" "$EMPTY_CTX"

# --- itr_summary prints the expected counts ---
SUMMARY=$(itr_summary "$SID")
assert_contains "summary has Events total" "$SUMMARY" "Events total: 5"
assert_contains "summary shows accepted count" "$SUMMARY" "Gentle accepted: 2"
assert_contains "summary shows ignored count" "$SUMMARY" "Gentle ignored: 1"
assert_contains "summary shows override count" "$SUMMARY" "Emergency overrides: 1"

# --- Exhausting gentle budget ---
EX_SID="exhaust-$$"
itr_init_state "$EX_SID"
for i in 1 2 3 4 5; do
    itr_log_event "$EX_SID" "gentle" "accepted" 1 "run $i"
done
assert_eq "remaining gentle after 5 accepted = 0" "0" "$(itr_remaining_budget "$EX_SID" gentle)"

# --- Repeat ignores cannot push gentle_max below 0 ---
MIN_SID="min-$$"
itr_init_state "$MIN_SID"
for i in 1 2 3 4 5 6 7; do
    itr_log_event "$MIN_SID" "gentle" "ignored" 0 "ignore $i"
done
MIN_MAX=$(jq -r '.budget.gentle_max' "$TMP_DIR/intrusiveness-${MIN_SID}.json")
# 5 initial − 7 ignores, clamped at 0
assert_eq "gentle_max clamped at 0 after excess ignores" "0" "$MIN_MAX"

# ===========================================================================
# v1.3.1 — Cost detectors (timing / destructive / closing) and cost_hints
# ===========================================================================

# --- itr_compute_timing_cost ---
assert_eq "timing: empty → 0"                "0" "$(echo '' | itr_compute_timing_cost)"
assert_eq "timing: short casual → 0"         "0" "$(echo 'привет' | itr_compute_timing_cost)"
assert_eq "timing: tech marker only → 1"     "1" "$(echo 'fix TypeError in foo.ts at line 42' | itr_compute_timing_cost)"
assert_eq "timing: focus marker → 2"         "2" "$(echo 'не отвлекай меня сейчас' | itr_compute_timing_cost)"
assert_eq "timing: multi-step only → 1"      "1" "$(echo 'сначала фикс, потом тесты' | itr_compute_timing_cost)"

# Length trigger: craft a 600+ char prompt with only length contributing
LONG_TEXT=$(printf 'обычный текст без технических маркеров, ничего особенного %.0s' {1..15})
LONG_COST=$(printf '%s' "$LONG_TEXT" | itr_compute_timing_cost)
# Should hit length (+1) at least — could be 1 if no other triggers
assert_eq "timing: long prose → at least 1"  "1" "$LONG_COST"

# Full stack of triggers → clamp at 5
BIG_PROMPT=$(cat <<'EOF'
не отвлекай меня, я в работе над миграцией. Сначала починим TypeError в main.ts:42, потом прогоним git push --force.
Стек:
```
at x (main.ts:42)
```
Второй блок:
```
panic at goroutine 5
```
Подробнее см. файл main.ts и api.ts:78. Нужно продолжать без отвлечений, это важно для деплоя в прод сегодня.
EOF
)
BIG_COST=$(printf '%s' "$BIG_PROMPT" | itr_compute_timing_cost)
assert_eq "timing: full stack → clamped 5"   "5" "$BIG_COST"

# --- itr_compute_destructive_cost ---
# Level 5: catastrophic
assert_eq "destr: rm -rf / → 5"              "5" "$(echo 'rm -rf /' | itr_compute_destructive_cost)"
assert_eq "destr: DROP DATABASE → 5"         "5" "$(echo 'psql -c \"DROP DATABASE prod\"' | itr_compute_destructive_cost)"
assert_eq "destr: DELETE no WHERE → 5"       "5" "$(echo 'DELETE FROM users;' | itr_compute_destructive_cost)"
assert_eq "destr: mkfs → 5"                  "5" "$(echo 'mkfs.ext4 /dev/sdb1' | itr_compute_destructive_cost)"
assert_eq "destr: dd to disk → 5"            "5" "$(echo 'dd if=/dev/zero of=/dev/sda bs=1M' | itr_compute_destructive_cost)"

# Level 4: dangerous
assert_eq "destr: rm -rf dir → 4"            "4" "$(echo 'rm -rf node_modules' | itr_compute_destructive_cost)"
assert_eq "destr: rm -fr dir → 4"            "4" "$(echo 'rm -fr build' | itr_compute_destructive_cost)"
assert_eq "destr: git push --force → 4"      "4" "$(echo 'git push origin main --force' | itr_compute_destructive_cost)"
assert_eq "destr: git push -f → 4"           "4" "$(echo 'git push -f origin feature' | itr_compute_destructive_cost)"
assert_eq "destr: git reset --hard → 4"      "4" "$(echo 'git reset --hard HEAD~3' | itr_compute_destructive_cost)"
assert_eq "destr: git branch -D main → 4"    "4" "$(echo 'git branch -D main' | itr_compute_destructive_cost)"

# Level 3: moderate
assert_eq "destr: DROP TABLE → 3"            "3" "$(echo 'DROP TABLE users' | itr_compute_destructive_cost)"
assert_eq "destr: --force-with-lease → 3"    "3" "$(echo 'git push --force-with-lease origin feature' | itr_compute_destructive_cost)"
assert_eq "destr: rm -r dir → 3"             "3" "$(echo 'rm -r build' | itr_compute_destructive_cost)"

# Level 0: safe
assert_eq "destr: ls → 0"                    "0" "$(echo 'ls -la' | itr_compute_destructive_cost)"
assert_eq "destr: safe git push → 0"         "0" "$(echo 'git push origin main' | itr_compute_destructive_cost)"
assert_eq "destr: DELETE WHERE → 0"          "0" "$(echo 'DELETE FROM users WHERE id=5' | itr_compute_destructive_cost)"
assert_eq "destr: rm file → 0"               "0" "$(echo 'rm junk.txt' | itr_compute_destructive_cost)"
assert_eq "destr: git branch -D feature → 0" "0" "$(echo 'git branch -D feature-x' | itr_compute_destructive_cost)"

# --- itr_compute_closing_cost ---
CL_SID="closing-$$"
itr_init_state "$CL_SID"
assert_eq "closing: no debt → 0"             "0" "$(itr_compute_closing_cost "$CL_SID")"
itr_add_silence_debt "$CL_SID" "typo" 1
assert_eq "closing: low-cost debt only → 2"  "2" "$(itr_compute_closing_cost "$CL_SID")"
itr_add_silence_debt "$CL_SID" "bug-a" 3
assert_eq "closing: 1 low + 1 high → 3"      "3" "$(itr_compute_closing_cost "$CL_SID")"
itr_add_silence_debt "$CL_SID" "bug-b" 4
itr_add_silence_debt "$CL_SID" "bug-c" 5
itr_add_silence_debt "$CL_SID" "bug-d" 3
assert_eq "closing: 4+ high, bonus cap → 5"  "5" "$(itr_compute_closing_cost "$CL_SID")"
assert_eq "closing: unknown sid → 0"         "0" "$(itr_compute_closing_cost "nonexistent-sid")"

# --- cost_hints set/get + running max for silence_cost_max ---
CH_SID="hints-$$"
itr_init_state "$CH_SID"
CH_PATH="$TMP_DIR/intrusiveness-${CH_SID}.json"
assert_eq "hints: initial timing 0"          "0" "$(itr_get_cost_hint "$CH_SID" timing_cost_current)"
itr_set_cost_hint "$CH_SID" timing_cost_current 3
assert_eq "hints: set timing=3"              "3" "$(itr_get_cost_hint "$CH_SID" timing_cost_current)"
itr_set_cost_hint "$CH_SID" timing_cost_current 9
assert_eq "hints: timing clamped to 5"       "5" "$(itr_get_cost_hint "$CH_SID" timing_cost_current)"
itr_set_cost_hint "$CH_SID" timing_cost_current -3
assert_eq "hints: timing clamped to 0"       "0" "$(itr_get_cost_hint "$CH_SID" timing_cost_current)"
itr_set_cost_hint "$CH_SID" silence_cost_max 2
itr_set_cost_hint "$CH_SID" silence_cost_max 4
itr_set_cost_hint "$CH_SID" silence_cost_max 1
assert_eq "hints: silence_cost_max is running max" "4" "$(itr_get_cost_hint "$CH_SID" silence_cost_max)"
itr_set_cost_hint "$CH_SID" last_destructive "rm -rf /tmp/x"
assert_eq "hints: last_destructive string"   "rm -rf /tmp/x" "$(itr_get_cost_hint "$CH_SID" last_destructive)"

# --- Schema v1 → v2 migration ---
MIG_SID="migrate-$$"
MIG_PATH="$TMP_DIR/intrusiveness-${MIG_SID}.json"
# Write a v1-shaped file
cat > "$MIG_PATH" <<'JSON'
{"session_id":"migrate-placeholder","created_at":"2026-04-21T00:00:00Z","schema_version":1,"budget":{"gentle_max":5,"gentle_used":2,"proactive_max":2,"proactive_used":0,"shrink_events":0},"events":[{"ts":"2026-04-21T00:01:00Z","type":"gentle","outcome":"accepted","silence_cost":0,"reason":"test"}],"silence_debt":[],"metrics":{"gentle_accepted":1,"gentle_ignored":0,"proactive_events":0,"override_events":0,"silence_debt_surfaced":0}}
JSON
# init should migrate in place
itr_init_state "$MIG_SID"
assert_eq "migrate: schema_version bumped to 4" "4" "$(jq -r '.schema_version' "$MIG_PATH")"
assert_eq "migrate: cost_hints added"           "true" "$(jq -r '.cost_hints != null' "$MIG_PATH")"
assert_eq "migrate: preserves budget"           "2" "$(jq -r '.budget.gentle_used' "$MIG_PATH")"
assert_eq "migrate: preserves events"           "1" "$(jq -r '.events | length' "$MIG_PATH")"

# --- v1.3.2 migration: adds timing_cost_peak to pre-existing v2 files ---
MIG2_SID="legacy-v2-no-peak-$$"
MIG2_PATH="$TMP_DIR/intrusiveness-${MIG2_SID}.json"
cat > "$MIG2_PATH" <<'JSON'
{"session_id":"legacy-v2","created_at":"2026-04-21T00:00:00Z","schema_version":2,"budget":{"gentle_max":5,"gentle_used":0,"proactive_max":2,"proactive_used":0,"shrink_events":0},"events":[],"silence_debt":[],"metrics":{"gentle_accepted":0,"gentle_ignored":0,"proactive_events":0,"override_events":0,"silence_debt_surfaced":0},"cost_hints":{"timing_cost_current":3,"silence_cost_max":2,"last_destructive":"","last_closing_cost":0,"last_updated":"2026-04-21T00:00:00Z"}}
JSON
itr_init_state "$MIG2_SID"
assert_eq "v1.3.2 migrate: timing_cost_peak added"       "0" "$(jq -r '.cost_hints.timing_cost_peak' "$MIG2_PATH")"
assert_eq "v1.3.2 migrate: preserves timing_cost_current" "3" "$(jq -r '.cost_hints.timing_cost_current' "$MIG2_PATH")"
assert_eq "v1.3.2 migrate: preserves silence_cost_max"    "2" "$(jq -r '.cost_hints.silence_cost_max' "$MIG2_PATH")"

# ============================================================================
# v1.3.2 — finalize / history / cleanup
# ============================================================================

# --- itr_finalize_metrics: idempotent no-op when metrics already match events ---
FIN_SID="finalize-test-$$"
itr_init_state "$FIN_SID"
itr_log_event "$FIN_SID" "gentle"    "accepted" 1 "ok"
itr_log_event "$FIN_SID" "gentle"    "ignored"  0 "no"
itr_log_event "$FIN_SID" "proactive" "accepted" 2 "did it"
itr_log_event "$FIN_SID" "override"  "accepted" 5 "emergency"
itr_finalize_metrics "$FIN_SID"
FIN_PATH="$TMP_DIR/intrusiveness-${FIN_SID}.json"
assert_eq "finalize: gentle_accepted = 1"       "1" "$(jq -r '.metrics.gentle_accepted' "$FIN_PATH")"
assert_eq "finalize: gentle_ignored = 1"        "1" "$(jq -r '.metrics.gentle_ignored' "$FIN_PATH")"
assert_eq "finalize: proactive_events = 1"      "1" "$(jq -r '.metrics.proactive_events' "$FIN_PATH")"
assert_eq "finalize: override_events = 1"       "1" "$(jq -r '.metrics.override_events' "$FIN_PATH")"
# Call again to verify idempotency
itr_finalize_metrics "$FIN_SID"
assert_eq "finalize idempotent: gentle_accepted still 1" "1" "$(jq -r '.metrics.gentle_accepted' "$FIN_PATH")"

# --- itr_finalize_metrics: backfill — events exist but metrics zeroed ---
BF_SID="backfill-test-$$"
BF_PATH="$TMP_DIR/intrusiveness-${BF_SID}.json"
# Write a file with events but zero metrics (simulates pre-v1.3.2 session)
cat > "$BF_PATH" <<'JSON'
{"session_id":"backfill","created_at":"2026-04-21T00:00:00Z","schema_version":2,"budget":{"gentle_max":5,"gentle_used":0,"proactive_max":2,"proactive_used":0,"shrink_events":0},"events":[
  {"ts":"t1","type":"gentle","outcome":"accepted","silence_cost":1,"reason":""},
  {"ts":"t2","type":"gentle","outcome":"ignored","silence_cost":0,"reason":""},
  {"ts":"t3","type":"gentle","outcome":"ignored","silence_cost":0,"reason":""},
  {"ts":"t4","type":"proactive","outcome":"accepted","silence_cost":2,"reason":""},
  {"ts":"t5","type":"override","outcome":"accepted","silence_cost":5,"reason":""},
  {"ts":"t6","type":"silence_debt","outcome":"surfaced","silence_cost":3,"reason":""}
],"silence_debt":[],"metrics":{"gentle_accepted":0,"gentle_ignored":0,"proactive_events":0,"override_events":0,"silence_debt_surfaced":0},"cost_hints":{"timing_cost_current":0,"timing_cost_peak":0,"silence_cost_max":0,"last_destructive":"","last_closing_cost":0,"last_updated":"2026-04-21T00:00:00Z"}}
JSON
itr_finalize_metrics "$BF_SID"
assert_eq "backfill: gentle_accepted recovered"       "1" "$(jq -r '.metrics.gentle_accepted' "$BF_PATH")"
assert_eq "backfill: gentle_ignored recovered"        "2" "$(jq -r '.metrics.gentle_ignored' "$BF_PATH")"
assert_eq "backfill: proactive_events recovered"      "1" "$(jq -r '.metrics.proactive_events' "$BF_PATH")"
assert_eq "backfill: override_events recovered"       "1" "$(jq -r '.metrics.override_events' "$BF_PATH")"
assert_eq "backfill: silence_debt_surfaced recovered" "1" "$(jq -r '.metrics.silence_debt_surfaced' "$BF_PATH")"

# --- itr_set_cost_hint: timing_cost_peak tracks running max ---
PEAK_SID="peak-test-$$"
itr_init_state "$PEAK_SID"
PEAK_PATH="$TMP_DIR/intrusiveness-${PEAK_SID}.json"
itr_set_cost_hint "$PEAK_SID" timing_cost_current 2
itr_set_cost_hint "$PEAK_SID" timing_cost_current 5
itr_set_cost_hint "$PEAK_SID" timing_cost_current 1
assert_eq "peak: current reflects latest"     "1" "$(jq -r '.cost_hints.timing_cost_current' "$PEAK_PATH")"
assert_eq "peak: peak holds running max"      "5" "$(jq -r '.cost_hints.timing_cost_peak' "$PEAK_PATH")"

# --- itr_append_history: writes one JSONL line with all expected fields ---
HIST_SID="history-test-$$"
HISTORY_FILE="$TMP_DIR/intrusiveness-history.jsonl"
itr_init_state "$HIST_SID"
itr_log_event "$HIST_SID" "gentle" "accepted" 2 "foo"
itr_log_event "$HIST_SID" "gentle" "ignored"  1 "bar"
itr_set_cost_hint "$HIST_SID" timing_cost_current 4
itr_set_cost_hint "$HIST_SID" silence_cost_max 3
itr_set_cost_hint "$HIST_SID" last_closing_cost 2
itr_set_cost_hint "$HIST_SID" cascading_backward_count 7
itr_set_cost_hint "$HIST_SID" injection_bytes_max 1234
itr_finalize_metrics "$HIST_SID"
itr_append_history "$HIST_SID"
assert_file_exists "history: jsonl file created" "$HISTORY_FILE"
assert_eq "history: one line written"            "1" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"
LINE=$(cat "$HISTORY_FILE")
assert_eq "history: session_id"                  "$HIST_SID" "$(echo "$LINE" | jq -r '.session_id')"
assert_eq "history: events_total"                "2" "$(echo "$LINE" | jq -r '.events_total')"
assert_eq "history: metrics.gentle_accepted"     "1" "$(echo "$LINE" | jq -r '.metrics.gentle_accepted')"
assert_eq "history: metrics.gentle_ignored"      "1" "$(echo "$LINE" | jq -r '.metrics.gentle_ignored')"
assert_eq "history: cost_peaks.timing_max"       "4" "$(echo "$LINE" | jq -r '.cost_peaks.timing_max')"
assert_eq "history: cost_peaks.silence_max"      "3" "$(echo "$LINE" | jq -r '.cost_peaks.silence_max')"
assert_eq "history: cost_peaks.closing"          "2" "$(echo "$LINE" | jq -r '.cost_peaks.closing')"
assert_eq "history: cost_peaks.injection_bytes_max (H12)" "1234" "$(echo "$LINE" | jq -r '.cost_peaks.injection_bytes_max')"
assert_eq "history: cascading.backward_count (H11)"       "7" "$(echo "$LINE" | jq -r '.cascading.backward_count')"
assert_eq "history: debt.pending"                "0" "$(echo "$LINE" | jq -r '.debt.pending')"
assert_eq "history: has duration_min (int)"      "true" "$(echo "$LINE" | jq -r '.duration_min | type == "number"')"
assert_eq "history: boundary defaults to stop"   "stop" "$(echo "$LINE" | jq -r '.boundary')"
# Second append for same session — history should have 2 lines (session can legitimately be
# re-closed, e.g. resumed then closed again; append is dumb by design)
itr_append_history "$HIST_SID"
assert_eq "history: appends additive"            "2" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# --- itr_append_history: explicit boundary=precompact marker ---
PCT_SID="precompact-test-$$"
PCT_HISTORY="$TMP_DIR/intrusiveness-history.jsonl"
itr_init_state "$PCT_SID"
itr_log_event "$PCT_SID" "gentle" "accepted" 1 "chunk1"
itr_set_cost_hint "$PCT_SID" injection_bytes_max 500
itr_set_cost_hint "$PCT_SID" cascading_backward_count 2
itr_finalize_metrics "$PCT_SID"
PCT_BEFORE=$(wc -l < "$PCT_HISTORY" | tr -d ' ')
itr_append_history "$PCT_SID" precompact
PCT_AFTER=$(wc -l < "$PCT_HISTORY" | tr -d ' ')
assert_eq "precompact: line appended" "$((PCT_BEFORE + 1))" "$PCT_AFTER"
PCT_LINE=$(tail -1 "$PCT_HISTORY")
assert_eq "precompact: boundary marker"            "precompact" "$(echo "$PCT_LINE" | jq -r '.boundary')"
assert_eq "precompact: injection_bytes_max snapshot" "500" "$(echo "$PCT_LINE" | jq -r '.cost_peaks.injection_bytes_max')"
assert_eq "precompact: backward_count snapshot"      "2" "$(echo "$PCT_LINE" | jq -r '.cascading.backward_count')"

# --- itr_append_history: invalid boundary falls back to stop ---
itr_append_history "$PCT_SID" garbage
GARBAGE_LINE=$(tail -1 "$PCT_HISTORY")
assert_eq "boundary: invalid value falls back to stop" "stop" "$(echo "$GARBAGE_LINE" | jq -r '.boundary')"

# --- itr_append_history: pending debt surfaces in digest ---
DBT_SID="debt-history-$$"
itr_init_state "$DBT_SID"
itr_add_silence_debt "$DBT_SID" "topic-A" 3
itr_add_silence_debt "$DBT_SID" "topic-B" 2
itr_log_event "$DBT_SID" "gentle" "accepted" 0 "x"
itr_finalize_metrics "$DBT_SID"
itr_append_history "$DBT_SID"
DBT_LINE=$(tail -1 "$HISTORY_FILE")
assert_eq "history: debt.pending counts unresolved" "2" "$(echo "$DBT_LINE" | jq -r '.debt.pending')"

# --- AP3 v1.5.8: history digest includes pending_topics array (up to 5) ---
AP3_SID="ap3-topics-$$"
itr_init_state "$AP3_SID"
itr_add_silence_debt "$AP3_SID" "topic-X" 2
itr_add_silence_debt "$AP3_SID" "topic-Y" 3
itr_add_silence_debt "$AP3_SID" "topic-Z" 4
itr_log_event "$AP3_SID" "gentle" "accepted" 0 "x"
itr_finalize_metrics "$AP3_SID"
itr_append_history "$AP3_SID"
AP3_LINE=$(tail -1 "$HISTORY_FILE")
assert_eq "AP3: pending_topics count in digest" "3" "$(echo "$AP3_LINE" | jq -r '.debt.pending_topics | length')"
assert_eq "AP3: pending_topics contains topic-X" "true" "$(echo "$AP3_LINE" | jq -r '.debt.pending_topics | any(. == "topic-X")')"
assert_eq "AP3: pending_topics contains topic-Z" "true" "$(echo "$AP3_LINE" | jq -r '.debt.pending_topics | any(. == "topic-Z")')"

# --- AP3 v1.5.8: pending_topics caps at 5 when more debts present ---
AP3_CAP_SID="ap3-cap-$$"
itr_init_state "$AP3_CAP_SID"
for i in 1 2 3 4 5 6 7; do
    itr_add_silence_debt "$AP3_CAP_SID" "topic-$i" 2
done
itr_log_event "$AP3_CAP_SID" "gentle" "accepted" 0 "x"
itr_finalize_metrics "$AP3_CAP_SID"
itr_append_history "$AP3_CAP_SID"
AP3_CAP_LINE=$(tail -1 "$HISTORY_FILE")
assert_eq "AP3: pending count is 7" "7" "$(echo "$AP3_CAP_LINE" | jq -r '.debt.pending')"
assert_eq "AP3: pending_topics capped at 5" "5" "$(echo "$AP3_CAP_LINE" | jq -r '.debt.pending_topics | length')"

# --- AP3 v1.5.8: empty pending_topics when all surfaced ---
AP3_EMPTY_SID="ap3-empty-$$"
itr_init_state "$AP3_EMPTY_SID"
itr_add_silence_debt "$AP3_EMPTY_SID" "topic-surfaced" 5
itr_mark_debt_surfaced "$AP3_EMPTY_SID" "topic-surfaced"
itr_log_event "$AP3_EMPTY_SID" "silence_debt" "surfaced" 5 "done"
itr_finalize_metrics "$AP3_EMPTY_SID"
itr_append_history "$AP3_EMPTY_SID"
AP3_EMPTY_LINE=$(tail -1 "$HISTORY_FILE")
assert_eq "AP3: no pending when all surfaced" "0" "$(echo "$AP3_EMPTY_LINE" | jq -r '.debt.pending')"
assert_eq "AP3: pending_topics empty" "0" "$(echo "$AP3_EMPTY_LINE" | jq -r '.debt.pending_topics | length')"

# --- itr_cleanup_old_states: deletes stale files, preserves fresh ---
CLEAN_TMP="$TMP_DIR/cleanup-scratch-$$"
mkdir -p "$CLEAN_TMP"
OLD_ITR_STATE_DIR="$ITR_STATE_DIR"
export ITR_STATE_DIR="$CLEAN_TMP"
# Create fresh file
FRESH_PATH="$CLEAN_TMP/intrusiveness-fresh.json"
jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{session_id:"fresh",created_at:$now,schema_version:2,budget:{},events:[],silence_debt:[],metrics:{},cost_hints:{}}' > "$FRESH_PATH"
# Create stale file (45 days old)
STALE_PATH="$CLEAN_TMP/intrusiveness-stale.json"
STALE_TS=$(iso_days_ago 45)
jq -n --arg ts "$STALE_TS" '{session_id:"stale",created_at:$ts,schema_version:2,budget:{},events:[],silence_debt:[],metrics:{},cost_hints:{}}' > "$STALE_PATH"
# Create history file — must NOT be touched
HIST_IN_CLEAN="$CLEAN_TMP/intrusiveness-history.jsonl"
echo '{"session_id":"old-hist"}' > "$HIST_IN_CLEAN"
DELETED=$(itr_cleanup_old_states 30)
assert_eq "cleanup: deleted 1 stale file"     "1" "$DELETED"
assert_file_exists "cleanup: fresh survived"  "$FRESH_PATH"
assert_file_exists "cleanup: history preserved" "$HIST_IN_CLEAN"
if [ ! -f "$STALE_PATH" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("cleanup: stale file still exists at $STALE_PATH")
fi
# Re-run cleanup — no files matching criteria left, so deleted = 0
DELETED2=$(itr_cleanup_old_states 30)
assert_eq "cleanup: idempotent — second run deletes 0" "0" "$DELETED2"
# Threshold applied to older test artefact: synthesise 3-day-old fresh file,
# cleanup with days=1 must remove it (age 3d > threshold 1d).
THREEDAY_PATH="$CLEAN_TMP/intrusiveness-3dayold.json"
THREEDAY_TS=$(iso_days_ago 3)
jq -n --arg ts "$THREEDAY_TS" '{session_id:"3d",created_at:$ts,schema_version:2,budget:{},events:[],silence_debt:[],metrics:{},cost_hints:{}}' > "$THREEDAY_PATH"
DELETED3=$(itr_cleanup_old_states 1)
assert_eq "cleanup: days=1 removes 3-day-old" "1" "$DELETED3"
assert_file_exists "cleanup: still-fresh file preserved (age < 1d)" "$FRESH_PATH"
export ITR_STATE_DIR="$OLD_ITR_STATE_DIR"

# ============================================================================
# v1.3.3: state classifier (4th axis of 4D gate)
# ============================================================================

# Helper: parse "state|conf|reasons" and assert state + min confidence.
_parse_state() { printf '%s' "$1" | awk -F'|' '{print $1}'; }
_parse_conf()  { printf '%s' "$1" | awk -F'|' '{print $2}'; }
_parse_reasons() { printf '%s' "$1" | awk -F'|' '{print $3}'; }

# --- empty / trivial input → idle ---
SC=$(itr_compute_state "" "")
assert_eq "state: empty input → idle" "idle" "$(_parse_state "$SC")"

SC=$(itr_compute_state "" "ok")
assert_eq "state: short confirmation → idle" "idle" "$(_parse_state "$SC")"

# --- focus: code blocks + length + tech markers ---
LONG_TEXT=$(printf 'Long technical prompt with code blocks below:\n\n```python\ndef foo():\n    return 1\n```\n\n```bash\ngit push origin main\n```\n\nerror: src/foo.ts:42 stack trace\n'; for i in $(seq 1 15); do printf 'padding text that extends the prompt past the 500 char length threshold easily '; done)
SC=$(itr_compute_state "" "$LONG_TEXT")
assert_eq "state: long + code + tech → focus"       "focus" "$(_parse_state "$SC")"
assert_contains "state: focus reasons include long" "$SC" "long"
assert_contains "state: focus reasons include code" "$SC" "code_blocks"
assert_contains "state: focus reasons include tech" "$SC" "tech_markers"

# --- focus: explicit focus phrase alone is enough (score +2) ---
SC=$(itr_compute_state "" "не отвлекай, я в работе")
assert_eq "state: focus phrase alone → focus" "focus" "$(_parse_state "$SC")"

# Та же фраза с заглавной. Все остальные входы классификатора набраны строчными, поэтому
# регистр кириллицы не проверялся ни разу — а под локалью C регистронезависимое сравнение
# GNU grep складывает только ASCII, и реплика с начала предложения теряла состояние focus.
# Единственный сигнал здесь — заглавная «Не отвлекай»: «я в работе» намеренно убрано,
# иначе строчное вхождение совпало бы и без складывания регистра, и проверка была бы слепой.
SC=$(itr_compute_state "" "Не отвлекай меня сейчас")
assert_eq "state: focus phrase capitalised → focus" "focus" "$(_parse_state "$SC")"

# --- focus: multi-step imperative + tech markers ---
SC=$(itr_compute_state "" "сначала собери артефакты в src/foo.ts file, потом запусти git push origin main, после этого разложи по полкам")
assert_eq "state: multi-step + tech → focus" "focus" "$(_parse_state "$SC")"

# --- stuck: explicit frustration phrase ---
SC=$(itr_compute_state "" "опять не работает")
assert_eq "state: 'не работает' → stuck" "stuck" "$(_parse_state "$SC")"

SC=$(itr_compute_state "" "still not working, same error as before")
assert_eq "state: English frustration → stuck" "stuck" "$(_parse_state "$SC")"

# --- stuck: via error-tracker streak (pure cross-hook signal, neutral prompt) ---
STK_SID="stuck-via-err-$$"
itr_init_state "$STK_SID"
printf '3\n' > "$ITR_STATE_DIR/error_count_${STK_SID}"
SC=$(itr_compute_state "$STK_SID" "какой у нас вариант?")
assert_eq "state: error_streak=3 + neutral prompt → stuck" "stuck" "$(_parse_state "$SC")"
assert_contains "state: reason includes error_streak"      "$SC" "error_streak"
rm -f "$ITR_STATE_DIR/error_count_${STK_SID}"

# --- stuck: via recent ignored gentles (session-context signal) ---
STK2_SID="stuck-via-ignored-$$"
itr_init_state "$STK2_SID"
itr_log_event "$STK2_SID" "gentle" "ignored" 0 "t1"
itr_log_event "$STK2_SID" "gentle" "ignored" 0 "t2"
SC=$(itr_compute_state "$STK2_SID" "ещё раз не работает")
assert_contains "state: recent_ignored_gentles adds stuck reason" "$SC" "recent_ignored_gentles"
assert_eq "state: stuck confirmed"                                 "stuck" "$(_parse_state "$SC")"

# --- exploration: hypothetical ---
SC=$(itr_compute_state "" "а что если сделать по-другому?")
assert_eq "state: 'а что если' → exploration" "exploration" "$(_parse_state "$SC")"

SC=$(itr_compute_state "" "какие альтернативы есть? давай сравним варианты")
assert_eq "state: alternatives + compare → exploration" "exploration" "$(_parse_state "$SC")"
assert_contains "state: multiple exploration reasons" "$SC" "alternatives"

SC=$(itr_compute_state "" "what if we could do it differently? think about tradeoffs")
assert_eq "state: English hypothetical → exploration" "exploration" "$(_parse_state "$SC")"

# --- priority: stuck wins over focus (frustration in tech prompt) ---
PRIOR_TEXT=$(printf 'опять не работает — git push file .ts error:\n```\nstack trace here\n```\n'; for i in $(seq 1 15); do printf 'padding padding padding padding padding padding padding padding '; done)
SC=$(itr_compute_state "" "$PRIOR_TEXT")
assert_eq "state: stuck > focus when both signals" "stuck" "$(_parse_state "$SC")"

# --- priority: focus wins over exploration ---
FOC_EXP_TEXT=$(printf 'а что если попробовать?\n```ts\nconst x = 1\n```\n```ts\nconst y = 2\n```\n'; for i in $(seq 1 15); do printf 'padding padding padding padding padding padding padding padding '; done)
SC=$(itr_compute_state "" "$FOC_EXP_TEXT")
assert_eq "state: focus > exploration" "focus" "$(_parse_state "$SC")"

# --- confidence: single signal → conf 1-2, multiple → conf 3 ---
SC=$(itr_compute_state "" "альтернатива?")
assert_eq "state: single exploration signal → conf 1" "1" "$(_parse_conf "$SC")"

# --- itr_set_state + itr_get_state roundtrip ---
SET_SID="set-get-$$"
itr_init_state "$SET_SID"
itr_set_state "$SET_SID" "focus" 3 "long,code_blocks,tech_markers"
GS=$(itr_get_state "$SET_SID")
assert_eq "set_state roundtrip: state"      "focus" "$(_parse_state "$GS")"
assert_eq "set_state roundtrip: confidence" "3"     "$(_parse_conf "$GS")"
assert_contains "set_state roundtrip: reasons" "$GS" "tech_markers"

# --- itr_set_state rejects invalid state ---
INVALID_PATH=$(_itr_state_path "$SET_SID")
PREV_JSON=$(jq -c '.state' "$INVALID_PATH")
if itr_set_state "$SET_SID" "garbage" 3 "x" 2>/dev/null; then
    FAIL=$((FAIL + 1)); FAILED_TESTS+=("set_state: invalid state should have failed")
else
    PASS=$((PASS + 1))
fi
POST_JSON=$(jq -c '.state' "$INVALID_PATH")
assert_eq "set_state: state unchanged after invalid input" "$PREV_JSON" "$POST_JSON"

# --- distribution counter increments per set_state ---
DIST_SID="dist-$$"
itr_init_state "$DIST_SID"
itr_set_state "$DIST_SID" "focus" 2 "a"
itr_set_state "$DIST_SID" "focus" 2 "b"
itr_set_state "$DIST_SID" "exploration" 1 "c"
itr_set_state "$DIST_SID" "stuck" 3 "d"
DIST_PATH=$(_itr_state_path "$DIST_SID")
assert_eq "distribution: focus counter"       "2" "$(jq -r '.state.distribution.focus' "$DIST_PATH")"
assert_eq "distribution: exploration counter" "1" "$(jq -r '.state.distribution.exploration' "$DIST_PATH")"
assert_eq "distribution: stuck counter"       "1" "$(jq -r '.state.distribution.stuck' "$DIST_PATH")"
assert_eq "distribution: idle counter (unused)" "0" "$(jq -r '.state.distribution.idle' "$DIST_PATH")"

# --- history digest includes state_distribution ---
HIST_SID="hist-state-$$"
itr_init_state "$HIST_SID"
itr_set_state "$HIST_SID" "focus" 3 "x"
itr_set_state "$HIST_SID" "stuck" 2 "y"
OLD_HIST="$ITR_STATE_DIR/intrusiveness-history.jsonl"
rm -f "$OLD_HIST"
itr_append_history "$HIST_SID" >/dev/null
HIST_LINE=$(tail -1 "$OLD_HIST")
assert_eq "history: state_distribution.focus" "1" "$(echo "$HIST_LINE" | jq -r '.state_distribution.focus')"
assert_eq "history: state_distribution.stuck" "1" "$(echo "$HIST_LINE" | jq -r '.state_distribution.stuck')"

# --- v3 migration: v2 file without state block gains state on init ---
MIG3_SID="legacy-v2-no-state-$$"
MIG3_PATH="$TMP_DIR/intrusiveness-${MIG3_SID}.json"
cat > "$MIG3_PATH" <<'JSON'
{"session_id":"legacy-v2-s","created_at":"2026-04-21T00:00:00Z","schema_version":2,"budget":{"gentle_max":5,"gentle_used":0,"proactive_max":2,"proactive_used":0,"shrink_events":0},"events":[],"silence_debt":[],"metrics":{"gentle_accepted":0,"gentle_ignored":0,"proactive_events":0,"override_events":0,"silence_debt_surfaced":0},"cost_hints":{"timing_cost_current":0,"timing_cost_peak":0,"silence_cost_max":0,"last_destructive":"","last_closing_cost":0,"last_updated":"2026-04-21T00:00:00Z"}}
JSON
itr_init_state "$MIG3_SID"
assert_eq "v1.5.7 migrate: schema bumped to 4"  "4"    "$(jq -r '.schema_version' "$MIG3_PATH")"
assert_eq "v1.5.7 migrate: state added"         "true" "$(jq -r '.state != null' "$MIG3_PATH")"
assert_eq "v1.5.7 migrate: state.current=idle"  "idle" "$(jq -r '.state.current' "$MIG3_PATH")"
assert_eq "v1.5.7 migrate: distribution.focus=0" "0"   "$(jq -r '.state.distribution.focus' "$MIG3_PATH")"
assert_eq "v1.5.7 migrate: distribution.distressed=0" "0" "$(jq -r '.state.distribution.distressed' "$MIG3_PATH")"

# --- context injection: non-idle state surfaces on trivial session ---
CTX_SID="ctx-state-$$"
itr_init_state "$CTX_SID"
itr_set_state "$CTX_SID" "focus" 3 "long,tech_markers"
CTX_OUT=$(itr_format_context "$CTX_SID")
assert_contains "context: non-idle state surfaces block" "$CTX_OUT" "focus (conf 3)"
assert_contains "context: reasons in block"              "$CTX_OUT" "tech_markers"

# ============================================================================
# v1.5.7: distressed state axis (AP2 affect prosthetic)
# ============================================================================

# --- class A frustration alone is not enough (needs 2+ classes) ---
SC=$(itr_compute_state "" "я устал, ничего не получается")
assert_eq "distressed: frustration phrase alone → not distressed (2+ classes required)" \
    "stuck" "$(_parse_state "$SC")"

# --- class C explicit distress alone fires distressed ---
SC=$(itr_compute_state "" "я в отчаянии, помоги хоть как-нибудь")
assert_eq "distressed: explicit distress alone → distressed" \
    "distressed" "$(_parse_state "$SC")"
assert_contains "distressed: explicit reason in output" "$SC" "explicit_distress"

# --- class A + class B (frustration + backward cascade) → distressed ---
D_SID="distressed-a-b-$$"
itr_init_state "$D_SID"
CASC_FILE="$ITR_STATE_DIR/cascading-events-${D_SID}.jsonl"
printf '{"ts":"2026-04-23T10:00:00Z","trigger":"BACKWARD","marker":"не так"}\n' > "$CASC_FILE"
printf '{"ts":"2026-04-23T10:01:00Z","trigger":"BACKWARD","marker":"не то"}\n' >> "$CASC_FILE"
printf '{"ts":"2026-04-23T10:02:00Z","trigger":"BACKWARD","marker":"не то"}\n' >> "$CASC_FILE"
SC=$(itr_compute_state "$D_SID" "я устал, надоело уже")
assert_eq "distressed: frustration + cascade ≥ 3 → distressed" \
    "distressed" "$(_parse_state "$SC")"
assert_contains "distressed: frustration reason" "$SC" "frustration_phrase"
assert_contains "distressed: cascade reason"     "$SC" "backward_cascade_3"

# --- priority: distressed wins over stuck when both signals present ---
SC=$(itr_compute_state "" "still not working, i am exhausted, please just help me, i don't know what to do")
assert_eq "distressed > stuck when both fire" "distressed" "$(_parse_state "$SC")"

# --- itr_set_state accepts distressed ---
DSET_SID="dset-$$"
itr_init_state "$DSET_SID"
itr_set_state "$DSET_SID" "distressed" 3 "explicit_distress,frustration_phrase"
GS=$(itr_get_state "$DSET_SID")
assert_eq "set_state: distressed valid" "distressed" "$(_parse_state "$GS")"

# --- distribution counter for distressed ---
DD_PATH=$(_itr_state_path "$DSET_SID")
assert_eq "distribution: distressed counter" "1" "$(jq -r '.state.distribution.distressed' "$DD_PATH")"

# --- remaining budget: proactive forced to 0 in distressed ---
DB_SID="dbud-$$"
itr_init_state "$DB_SID"
itr_set_state "$DB_SID" "distressed" 3 "explicit_distress"
assert_eq "budget: proactive = 0 in distressed" "0" "$(itr_remaining_budget "$DB_SID" proactive)"

# --- remaining budget: gentle halved in distressed (5 → 2) ---
assert_eq "budget: gentle halved in distressed (5→2)" "2" "$(itr_remaining_budget "$DB_SID" gentle)"

# --- context: AP2 marker surfaces in distressed ---
DCTX_OUT=$(itr_format_context "$DB_SID")
assert_contains "context: distressed state surfaces" "$DCTX_OUT" "distressed (conf 3)"
assert_contains "context: AP2 prosthetic marker"     "$DCTX_OUT" "AP2 distressed"
assert_contains "context: gentle effective line"     "$DCTX_OUT" "effective 2 in distressed"
assert_contains "context: proactive effective 0"     "$DCTX_OUT" "effective 0 in distressed"

# --- priority: distressed wins over focus too (technical + distress markers) ---
PRIOR_DISTRESS=$(printf 'please just help me, i don'"'"'t know what to do:\n```python\ndef foo():\n    return 1\n```\n'; for i in $(seq 1 15); do printf 'padding padding padding padding padding padding '; done)
SC=$(itr_compute_state "" "$PRIOR_DISTRESS")
assert_eq "distressed > focus when both fire" "distressed" "$(_parse_state "$SC")"

# --- Report ---

# --- регрессия: itr_compute_state не читает stdin при явном аргументе ---
# Условие `[ -z "$text" ] && [ ! -t 0 ]` съедало stdin, когда второй аргумент
# передан пустым, и висело вечно, если stdin — открытая труба (хук-раннер, CI).
# Проверяем через подпроцесс с трубой, которую никто не закрывает: без фикса
# тест не завершится, с фиксом отвечает мгновенно.
PROBE=$(cat <<'PROBE_EOF'
source "$LIB_PATH"
itr_compute_state "" ""
PROBE_EOF
)
if command -v python3 >/dev/null 2>&1; then
    RESULT=$(LIB_PATH="$LIB" PROBE="$PROBE" python3 - <<'PY_EOF'
import os, subprocess
r, w = os.pipe()
try:
    out = subprocess.run(["bash", "-c", os.environ["PROBE"]], stdin=r,
                         capture_output=True, text=True, timeout=10,
                         env={**os.environ})
    print(out.stdout.strip())
except subprocess.TimeoutExpired:
    print("HANG")
finally:
    os.close(r); os.close(w)
PY_EOF
)
    assert_eq "itr_compute_state не виснет на открытом stdin" "idle|1|empty" "$RESULT"
fi

TOTAL=$((PASS + FAIL))

echo ""
echo "intrusiveness-state-lib tests: $PASS/$TOTAL passed"


if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failures:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
exit 0
