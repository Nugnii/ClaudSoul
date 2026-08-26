#!/usr/bin/env bash
# test_backfill.sh — backfill-replay-one.sh smoke + orchestrator coverage.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKER="$HOOKS_DIR/lib/backfill-replay-one.sh"
ORCHESTRATOR="$HOOKS_DIR/backfill-intrusiveness.sh"

[ -f "$WORKER" ] || { echo "FAIL: $WORKER not found"; exit 1; }
[ -f "$ORCHESTRATOR" ] || { echo "FAIL: $ORCHESTRATOR not found"; exit 1; }

PASS=0; FAIL=0
assert_contains() {
    local h="$1" n="$2" label="$3"
    if grep -Fq "$n" <<< "$h"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$label]: '$n' not in:"; echo "$h"; fi
}
assert_empty() {
    local a="$1" label="$2"
    if [ -z "$a" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$label]: expected empty, got: $a"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# T1: non-existent transcript → worker exits silently
# ============================================================================
OUT=$("$WORKER" /nonexistent/file.jsonl 2>/dev/null || true)
assert_empty "$OUT" "T1: missing transcript → silent"

# ============================================================================
# T2: synthetic transcript with gentle marker → produces event
# ============================================================================
TR2="$TMP/synth-gentle.jsonl"
{
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:00Z",
             message:{role:"user", content:[{type:"text", text:"напиши функцию"}]}}'
    jq -cn '{type:"assistant", timestamp:"2026-04-01T10:00:05Z",
             message:{role:"assistant", content:[{type:"text",
               text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:30Z",
             message:{role:"user", content:[{type:"text", text:"да"}]}}'
} > "$TR2"

OUT=$("$WORKER" "$TR2" 2>/dev/null)
assert_contains "$OUT" '"type":"gentle"' "T2: gentle event produced"
assert_contains "$OUT" '"outcome":"accepted"' "T2: accepted outcome"
assert_contains "$OUT" '"source":"backfill"' "T2: backfill marker"
# Historical timestamp preserved (from user record)
assert_contains "$OUT" '"ts":"2026-04-01T10:00:30Z"' "T2: historical ts"
# aggregate_sid derived from transcript basename
assert_contains "$OUT" '"aggregate_sid":"backfill-synth-gentle"' "T2: aggregate sid"

# ============================================================================
# T3: synthetic transcript with proactive tool use → produces proactive event
# ============================================================================
TR3="$TMP/synth-proactive.jsonl"
{
    jq -cn '{type:"user", timestamp:"2026-04-02T10:00:00Z",
             message:{role:"user", content:[{type:"text", text:"нужен план"}]}}'
    jq -cn '{type:"assistant", timestamp:"2026-04-02T10:00:05Z",
             message:{role:"assistant", content:[
               {type:"text", text:"План готов."},
               {type:"tool_use", name:"Edit", id:"t1", input:{}}
             ]}}'
    jq -cn '{type:"user", timestamp:"2026-04-02T10:00:30Z",
             message:{role:"user", content:[{type:"text", text:"ок"}]}}'
} > "$TR3"

OUT=$("$WORKER" "$TR3" 2>/dev/null)
assert_contains "$OUT" '"type":"proactive"' "T3: proactive event"
assert_contains "$OUT" '"source":"backfill"' "T3: backfill marker"

# ============================================================================
# T4: transcript with no user→assistant→user triad → no events
# ============================================================================
TR4="$TMP/synth-user-only.jsonl"
jq -cn '{type:"user", timestamp:"2026-04-03T10:00:00Z",
         message:{role:"user", content:[{type:"text", text:"hello"}]}}' > "$TR4"
OUT=$("$WORKER" "$TR4" 2>/dev/null)
assert_empty "$OUT" "T4: no triad → no events"

# ============================================================================
# T5: orchestrator --dry-run respects --limit and reports counts
# ============================================================================
# Build mini projects dir with two synthetic transcripts
PROJ_DIR="$TMP/projects"
mkdir -p "$PROJ_DIR/sess-a" "$PROJ_DIR/sess-b"
cp "$TR2" "$PROJ_DIR/sess-a/t1.jsonl"
cp "$TR3" "$PROJ_DIR/sess-b/t2.jsonl"

OUT_FILE="$TMP/out.jsonl"
OUT=$(BACKFILL_PROJECTS_DIR="$PROJ_DIR" BACKFILL_OUT="$OUT_FILE" \
      bash "$ORCHESTRATOR" --dry-run 2>&1)
assert_contains "$OUT" "transcripts found: 2" "T5: dry-run counts 2"
assert_contains "$OUT" "dry run, no replay" "T5: dry-run marker"
[ ! -f "$OUT_FILE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5: no output on dry-run]"; }

# ============================================================================
# T6: orchestrator produces NDJSON file with events from mini dir
# ============================================================================
OUT=$(BACKFILL_PROJECTS_DIR="$PROJ_DIR" BACKFILL_OUT="$OUT_FILE" \
      BACKFILL_PARALLEL=2 bash "$ORCHESTRATOR" 2>&1)
assert_contains "$OUT" "=== Backfill complete" "T6: completion marker"
# Переносимость mktemp: GNU падает на шаблоне без X'ов, ошибка видна в stderr
if grep -q 'mktemp:' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [T6: mktemp not portable]: $OUT"
else PASS=$((PASS+1)); fi
[ -f "$OUT_FILE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6: output file missing]"; }
EVENTS=$(wc -l < "$OUT_FILE" | tr -d ' ')
if [ "$EVENTS" -ge 2 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6: expected >=2 events, got $EVENTS]"; cat "$OUT_FILE"; fi
# Both gentle and proactive should be present
if grep -q '"type":"gentle"' "$OUT_FILE" && grep -q '"type":"proactive"' "$OUT_FILE"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T6: both types expected]"; cat "$OUT_FILE"
fi

echo ""
echo "=== backfill tests ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
