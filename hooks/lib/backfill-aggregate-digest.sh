#!/usr/bin/env bash
# backfill-aggregate-digest.sh — agregate raw backfill events into history-digest format.
#
# Reads NDJSON from `intrusiveness-backfill-history.jsonl` (raw events emitted
# by backfill-replay-one.sh) and emits one digest line per aggregate_sid in
# the same schema as live `intrusiveness-history.jsonl`. The output is
# `intrusiveness-backfill-digest.jsonl` and is compatible with
# scripts/calibrate.py — same filter `boundary in {stop, precompact}` + same
# `metrics` / `budget` / `state_distribution` / `cascading` / `cost_peaks` /
# `debt` keys.
#
# Mapping raw events → digest aggregate (per aggregate_sid):
#   metrics.gentle_accepted   = count(type=gentle  AND outcome=accepted)
#   metrics.gentle_ignored    = count(type=gentle  AND outcome=ignored)
#   metrics.proactive_events  = count(type=proactive)
#   metrics.override_events   = 0  (no proxy in raw events; live-only field)
#   metrics.silence_debt_*    = 0  (idem)
#   budget.gentle_used        = min(gentle_total, gentle_max)
#   budget.proactive_used     = min(proactive_total, proactive_max)
#   budget.{gentle,proactive}_max = current defaults (4, 2)
#   budget.shrink_events      = 0
#   state_distribution        = {"idle": events_total}  (best-effort default;
#                               matches live observation that 100% of chunks
#                               are idle for this user — worth re-checking
#                               if data scope expands)
#   cost_peaks                = {} (no proxy)
#   debt                      = {surfaced:0, pending:0}
#   cascading.backward_count  = 0  (requires reformulation-tracker replay,
#                               separate work — v1.7 H11 baseline)
#   boundary                  = "stop"  (so calibrate.py filter matches)
#   source                    = "backfill"  (traceability marker)
#
# Usage:
#   bash hooks/lib/backfill-aggregate-digest.sh [input.jsonl] [output.jsonl]
# Defaults:
#   input  = ~/.claude/hooks/state/intrusiveness-backfill-history.jsonl
#   output = ~/.claude/hooks/state/intrusiveness-backfill-digest.jsonl

set -uo pipefail

INPUT="${1:-$HOME/.claude/hooks/state/intrusiveness-backfill-history.jsonl}"
OUTPUT="${2:-$HOME/.claude/hooks/state/intrusiveness-backfill-digest.jsonl}"
GENTLE_MAX="${BACKFILL_GENTLE_MAX:-4}"
PROACTIVE_MAX="${BACKFILL_PROACTIVE_MAX:-2}"

[ -f "$INPUT" ] || { echo "input not found: $INPUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"
[ -f "$OUTPUT" ] && mv "$OUTPUT" "${OUTPUT}.bak.$(date +%s)"

# Group by aggregate_sid, emit one digest per group.
# jq -sc reads all events into array. Collect into groups, derive fields.
jq -sc --argjson gmax "$GENTLE_MAX" --argjson pmax "$PROACTIVE_MAX" '
    group_by(.aggregate_sid)
    | map(
        . as $events
        | ($events | length) as $n
        | ($events | map(.ts) | min) as $tmin
        | ($events | map(.ts) | max) as $tmax
        | ($events | map(select(.type == "gentle"    and .outcome == "accepted")) | length) as $g_acc
        | ($events | map(select(.type == "gentle"    and .outcome == "ignored"))  | length) as $g_ign
        | ($events | map(select(.type == "proactive")) | length) as $p_tot
        | ($g_acc + $g_ign) as $g_tot
        | (if $tmin == $tmax or $tmin == null or $tmax == null then 0
           else (((($tmax | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))
                - (($tmin | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))) / 60 | floor) end
          ) as $dur_min
        | {
            session_id: $events[0].aggregate_sid,
            date: ($tmin // "" | sub("T.*"; "")),
            created_at: $tmin,
            closed_at: $tmax,
            duration_min: $dur_min,
            events_total: $n,
            boundary: "stop",
            source: "backfill",
            budget: {
                gentle_used: (if $g_tot < $gmax then $g_tot else $gmax end),
                gentle_max: $gmax,
                proactive_used: (if $p_tot < $pmax then $p_tot else $pmax end),
                proactive_max: $pmax,
                shrink_events: 0
            },
            metrics: {
                gentle_accepted: $g_acc,
                gentle_ignored: $g_ign,
                proactive_events: $p_tot,
                override_events: 0,
                silence_debt_surfaced: 0
            },
            debt: { surfaced: 0, pending: 0 },
            cost_peaks: {},
            state_distribution: { idle: $n },
            cascading: { backward_count: 0 }
          }
      )
    | .[]
' "$INPUT" > "$OUTPUT"

# Summary
TOTAL=$(wc -l < "$OUTPUT" | tr -d ' ')
G_ACC=$(jq -s '[.[] | .metrics.gentle_accepted] | add // 0' "$OUTPUT")
G_IGN=$(jq -s '[.[] | .metrics.gentle_ignored] | add // 0' "$OUTPUT")
P_TOT=$(jq -s '[.[] | .metrics.proactive_events] | add // 0' "$OUTPUT")
EVENTS=$(jq -s '[.[] | .events_total] | add // 0' "$OUTPUT")

echo "=== backfill aggregate digest"
echo "input:  $INPUT"
echo "output: $OUTPUT"
echo ""
echo "session digests written: $TOTAL"
echo "events covered:          $EVENTS"
echo "gentle accepted:         $G_ACC"
echo "gentle ignored:          $G_IGN"
echo "proactive events:        $P_TOT"
if [ "$TOTAL" -gt 0 ]; then
    echo ""
    echo "first digest:"
    head -1 "$OUTPUT" | jq '.'
fi
