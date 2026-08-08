#!/usr/bin/env bash
# test_backfill_aggregate.sh — backfill-aggregate-digest.sh coverage.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/lib/backfill-aggregate-digest.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0; FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected '$expected' got '$actual'"; fi
}
assert_contains() {
    local h="$1" n="$2" label="$3"
    if echo "$h" | grep -Fq "$n"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$n' not in:"; echo "$h"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# T1: synthetic events from 2 sessions → 2 digests
# ============================================================================
INPUT="$TMP/events.jsonl"
OUTPUT="$TMP/digest.jsonl"

# Session A: 2 gentle accepted, 1 gentle ignored, 1 proactive
{
    jq -cn '{ts:"2026-04-01T10:00:00Z", aggregate_sid:"backfill-A", type:"gentle",    outcome:"accepted", source:"backfill"}'
    jq -cn '{ts:"2026-04-01T10:01:00Z", aggregate_sid:"backfill-A", type:"gentle",    outcome:"accepted", source:"backfill"}'
    jq -cn '{ts:"2026-04-01T10:02:00Z", aggregate_sid:"backfill-A", type:"gentle",    outcome:"ignored",  source:"backfill"}'
    jq -cn '{ts:"2026-04-01T10:03:00Z", aggregate_sid:"backfill-A", type:"proactive", outcome:"accepted", source:"backfill"}'
    # Session B: 3 proactive
    jq -cn '{ts:"2026-04-02T11:00:00Z", aggregate_sid:"backfill-B", type:"proactive", outcome:"accepted", source:"backfill"}'
    jq -cn '{ts:"2026-04-02T11:05:00Z", aggregate_sid:"backfill-B", type:"proactive", outcome:"ignored",  source:"backfill"}'
    jq -cn '{ts:"2026-04-02T11:10:00Z", aggregate_sid:"backfill-B", type:"proactive", outcome:"accepted", source:"backfill"}'
} > "$INPUT"

bash "$SCRIPT" "$INPUT" "$OUTPUT" >/dev/null 2>&1

# Check digest count
LINES=$(wc -l < "$OUTPUT" | tr -d ' ')
assert_eq "$LINES" "2" "T1: 2 digest lines emitted"

# Check session A digest
A=$(jq -c 'select(.session_id=="backfill-A")' "$OUTPUT")
assert_contains "$A" '"gentle_accepted":2' "T1: session A gentle_accepted=2"
assert_contains "$A" '"gentle_ignored":1' "T1: session A gentle_ignored=1"
assert_contains "$A" '"proactive_events":1' "T1: session A proactive_events=1"
assert_contains "$A" '"events_total":4' "T1: session A events_total=4"
assert_contains "$A" '"boundary":"stop"' "T1: boundary=stop (calibrate.py compat)"
assert_contains "$A" '"source":"backfill"' "T1: source=backfill marker"
assert_contains "$A" '"date":"2026-04-01"' "T1: date from min ts"
assert_contains "$A" '"gentle_used":3' "T1: gentle_used = total (3 < gmax=4)"
assert_contains "$A" '"proactive_used":1' "T1: proactive_used = 1"

# Check session B digest
B=$(jq -c 'select(.session_id=="backfill-B")' "$OUTPUT")
assert_contains "$B" '"proactive_events":3' "T1: session B proactive_events=3"
assert_contains "$B" '"proactive_used":2' "T1: proactive_used capped at pmax=2"
assert_contains "$B" '"gentle_accepted":0' "T1: session B no gentle"

# state_distribution should have idle = events_total
assert_contains "$A" '"idle":4' "T1: state_distribution idle = events_total"

# ============================================================================
# T2: budget caps respected with --gmax/--pmax env override
# ============================================================================
OUTPUT2="$TMP/digest2.jsonl"
BACKFILL_GENTLE_MAX=10 BACKFILL_PROACTIVE_MAX=10 \
    bash "$SCRIPT" "$INPUT" "$OUTPUT2" >/dev/null 2>&1
A2=$(jq -c 'select(.session_id=="backfill-A")' "$OUTPUT2")
assert_contains "$A2" '"gentle_used":3' "T2: env override gentle_max=10 (still 3 since total=3)"
assert_contains "$A2" '"gentle_max":10' "T2: env gentle_max=10 reflected"
assert_contains "$A2" '"proactive_max":10' "T2: env proactive_max=10 reflected"

# ============================================================================
# T3: missing input file → exits with error
# ============================================================================
EC=0
bash "$SCRIPT" /nonexistent/file.jsonl "$TMP/x.jsonl" >/dev/null 2>&1 || EC=$?
if [ "$EC" -ne 0 ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T3: missing input should error]"; fi

# ============================================================================
# T4: schema compatibility with calibrate.py — required fields present
# ============================================================================
A=$(jq -c 'select(.session_id=="backfill-A")' "$OUTPUT")
for field in session_id boundary metrics budget cascading debt cost_peaks state_distribution; do
    if echo "$A" | jq -e ".$field" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [T4: missing field $field]"
    fi
done

# ============================================================================
# T5: existing output backed up (not overwritten without trace)
# ============================================================================
OUTPUT5="$TMP/digest5.jsonl"
echo "old content" > "$OUTPUT5"
bash "$SCRIPT" "$INPUT" "$OUTPUT5" >/dev/null 2>&1
BAK_COUNT=$(ls "${OUTPUT5}.bak."* 2>/dev/null | wc -l | tr -d ' ')
if [ "$BAK_COUNT" -ge 1 ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T5: backup should be created]"; fi

echo ""
echo "=== backfill-aggregate-digest tests ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
