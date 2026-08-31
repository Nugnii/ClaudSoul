#!/usr/bin/env bash
# pre-compact-finalizer.sh — PreCompact: фиксирует chunk-границу до компакта.
# en: PreCompact: snapshots the chunk boundary before context compaction.
#
# Purpose:
#   Claude Code compacts the transcript when context fills, replacing the
#   conversation with a summary. State files in ~/.claude/hooks/state survive,
#   but the transcript that itr-event-detector relies on for backfill does not.
#   Without a per-chunk digest snapshot, hypothesis calibration data (H9-H12)
#   accumulates only in memory until Stop — and Stop may never fire if the
#   session ends from context exhaustion or transitions to a new SID.
#
#   This hook writes a cumulative-snapshot digest with boundary="precompact"
#   on every compaction event. Analytics derive chunk deltas by subtracting
#   successive snapshots.
#
# Behaviour:
#   - Aggregates cascading_backward_count and injection_bytes_max from external
#     state files (same as session-collector).
#   - Calls itr_finalize_metrics + itr_append_history (boundary=precompact).
#   - Does NOT clean up state files — compact ≠ end-of-session.
#   - Silent: emits `{}`, no user-facing message.
#
# Input: JSON on stdin (session_id + trigger from Claude Code).
# Output: `{}` (empty JSON object, no hookSpecificOutput key).

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.claude/hooks/intrusiveness-state-lib.sh"

# Degrade silently if library missing or jq unavailable.
[ -f "$LIB" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# shellcheck source=/dev/null
source "$LIB"

INPUT=$(cat)
PAYLOAD_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-$PPID}"
ITR_SID="${PAYLOAD_SID:-$SESSION_ID}"
ITR_STATE="$STATE_DIR/intrusiveness-${ITR_SID}.json"

# No state file → nothing to snapshot. Silent exit.
[ -f "$ITR_STATE" ] || exit 0

# Aggregate H11/H12 signals into cost_hints (mirror of session-collector logic).
CASCADE_LOG="$STATE_DIR/cascading-events-${SESSION_ID}.jsonl"
if [ -f "$CASCADE_LOG" ]; then
    BWD_COUNT=$(grep -c '"trigger":"BACKWARD"' "$CASCADE_LOG" 2>/dev/null || echo 0)
    BWD_COUNT=$(printf '%s' "$BWD_COUNT" | tr -d '[:space:]')
    [ -z "$BWD_COUNT" ] && BWD_COUNT=0
    itr_set_cost_hint "$ITR_SID" cascading_backward_count "$BWD_COUNT" >/dev/null 2>&1 || true
fi
INJECT_PEAK_FILE="$STATE_DIR/injection-bytes-peak-${SESSION_ID}"
if [ -f "$INJECT_PEAK_FILE" ]; then
    INJ_PEAK=$(cat "$INJECT_PEAK_FILE" 2>/dev/null | tr -d '[:space:]')
    [ -z "$INJ_PEAK" ] && INJ_PEAK=0
    itr_set_cost_hint "$ITR_SID" injection_bytes_max "$INJ_PEAK" >/dev/null 2>&1 || true
fi

# Finalize → snapshot. boundary=precompact distinguishes chunk from session close.
itr_finalize_metrics "$ITR_SID" >/dev/null 2>&1 || true
itr_append_history "$ITR_SID" precompact >/dev/null 2>&1 || true

# Silent: no systemMessage, no additionalContext. Compaction is an internal
# event; surfacing it would add noise to the next post-compact prompt.
printf '{}\n'
exit 0
