#!/usr/bin/env bash
# blocker-tier-check.sh — PreToolUse: silent 🛑 marker для знаний с `blocker: true`, когда действие совпадает с detection_signals паттерна.
# en: PreToolUse: silent 🛑 marker for knowledge with `blocker: true` when the action matches the pattern's detection_signals.
#
# Purpose: close the knowledge-action gap for patterns that keep triggering despite
# being in the knowledge base at confidence 5. Retrieval via knowledge-activator
# relies on anchor similarity — for some patterns the anchors describe situations
# that don't overlap with where the pattern actually fires. Blocker-tier is the
# backstop: relational detection by concrete signals (tool + path + size + text),
# delivered as SILENT additionalContext so the agent can adjust internally without
# noisy banners to the user.
#
# Contract:
#   Input  (stdin): {session_id, tool_name, tool_input, cwd, ...}  (PreToolUse JSON)
#   Output (stdout): {hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: "..."}}
#                    on match; empty on no-match.
#   Exit code:      always 0 (degrade gracefully on any failure).
#
# Throttle state: $HOME/.claude/hooks/state/blocker-fired-<SESSION_ID>.jsonl
#   One JSON line per (pattern, file_path OR signal). Same key won't fire twice
#   in the same session.
#
# Silent by design (see feedback_silent_correct_decisions.md):
#   - Uses hookSpecificOutput.additionalContext, NOT systemMessage or permissionDecision:ask
#   - Visible reaction is the agent's choice, not the hook's forcing
#   - Noise/bloat is itself a failure mode — the hook just delivers the signal

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; fi
STATE_DIR="${BLOCKER_STATE_DIR:-$HOME/.claude/hooks/state}"
KNOWLEDGE_DIR="${BLOCKER_KNOWLEDGE_DIR:-$LESSONS_DIR}"
LIB_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
LIB="$LIB_DIR/detection-signals-lib.sh"
THROTTLE_LIB="${THROTTLE_LIB:-$LIB_DIR/throttle-lib.sh}"

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
[ -d "$KNOWLEDGE_DIR" ] || exit 0
[ -f "$LIB" ] || exit 0
[ -f "$THROTTLE_LIB" ] || exit 0

# shellcheck source=/dev/null
source "$LIB"
# shellcheck source=/dev/null
source "$THROTTLE_LIB"

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"
[ -z "$TOOL_NAME" ] && exit 0

# Last user prompt — best effort from intrusiveness state (optional dep)
PROMPT=""
ITR_STATE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$ITR_STATE" ]; then
    PROMPT=$(jq -r '.state.reasons[-1] // ""' "$ITR_STATE" 2>/dev/null)
fi

THROTTLE_FILE=$(throttle_file "$STATE_DIR" blocker "$SESSION_ID")

# Iterate blocker-tier knowledge. Principles rarely need blocker status, but
# include them for completeness.
MATCHED_PATTERN=""
MATCHED_SIGNAL=""
REMINDER_FIELD="blocker_reminder"

for pfile in "$KNOWLEDGE_DIR"/pattern-*.md "$KNOWLEDGE_DIR"/principle-*.md; do
    [ -f "$pfile" ] || continue
    ds_has_blocker_flag "$pfile" || continue

    signal_name=$(ds_evaluate "$pfile" "$TOOL_NAME" "$TOOL_INPUT" "$PROMPT" 2>/dev/null)
    [ -z "$signal_name" ] && continue

    pattern_name=$(basename "$pfile" .md)

    # Throttle key: per-file for file tools, per-signal otherwise
    file_path=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
    if [ -n "$file_path" ]; then
        throttle_key="${pattern_name}@${file_path}"
    else
        throttle_key="${pattern_name}:${signal_name}"
    fi

    if throttle_seen "$THROTTLE_FILE" "$throttle_key"; then
        continue
    fi

    MATCHED_PATTERN="$pattern_name"
    MATCHED_SIGNAL="$signal_name"
    MATCHED_FILE="$pfile"
    MATCHED_KEY="$throttle_key"
    break
done

# --- Cross-hook recall gate (escalation for pattern-inside-out-blindness) ---
# The pattern has 27 confirmations across 27 *different* dimensions; per-dimension
# detection_signals can't converge. The one domain-independent invariant: "I am
# about to CREATE something without checking external context." We can't read that
# from content, but a *fired protective guard* is domain-independent evidence the
# system already detected improvisation. So: if any allowlisted guard fired this
# session and the agent is about to Write a file, surface the recall reminder.
# A pattern opts in via `cross_hook_recall_gate: true`. Throttled per (pattern,guard).
if [ -z "$MATCHED_PATTERN" ] && [ "$TOOL_NAME" = "Write" ]; then
    GUARD_MARKERS="${GUARD_FIRED_MARKERS:-correction-fired bulk-copy-fired internal-doc-leak-fired playwright-cli-guard-fired}"
    FIRED_GUARD=""
    for gm in $GUARD_MARKERS; do
        if [ -s "$STATE_DIR/${gm}-${SESSION_ID}.jsonl" ]; then
            FIRED_GUARD="$gm"
            break
        fi
    done
    if [ -n "$FIRED_GUARD" ]; then
        for pfile in "$KNOWLEDGE_DIR"/pattern-*.md; do
            [ -f "$pfile" ] || continue
            awk '
                /^---$/ { if (++n == 2) exit; next }
                n == 1 && /^cross_hook_recall_gate:[[:space:]]*true[[:space:]]*$/ { found = 1; exit }
                END { exit (found ? 0 : 1) }
            ' "$pfile" || continue

            gate_pattern=$(basename "$pfile" .md)
            gate_key="${gate_pattern}:cross_hook_recall_gate@${FIRED_GUARD}"
            if throttle_seen "$THROTTLE_FILE" "$gate_key"; then
                continue
            fi

            MATCHED_PATTERN="$gate_pattern"
            MATCHED_SIGNAL="cross_hook_recall_gate (after ${FIRED_GUARD})"
            MATCHED_FILE="$pfile"
            MATCHED_KEY="$gate_key"
            REMINDER_FIELD="cross_hook_recall_reminder"
            break
        done
    fi
fi

[ -z "$MATCHED_PATTERN" ] && exit 0

# Record fire in throttle JSONL (key + diagnostic pattern/signal)
throttle_mark "$THROTTLE_FILE" "$MATCHED_KEY" \
    "$(printf '"pattern":"%s","signal":"%s"' "$MATCHED_PATTERN" "$MATCHED_SIGNAL")"

# Extract reminder text + stats from pattern frontmatter.
# REMINDER_FIELD selects which reminder to surface: blocker_reminder (signal match)
# or cross_hook_recall_reminder (cross-hook gate).
REMINDER=$(awk -v field="$REMINDER_FIELD" '
    /^---$/ { if (++n == 2) exit; next }
    n == 1 && index($0, field ":") == 1 {
        sub("^" field ":[[:space:]]*", "")
        gsub(/^"|"$/, "")
        gsub(/^'"'"'|'"'"'$/, "")
        print
        exit
    }
' "$MATCHED_FILE")

CONFIRMED=$(awk '
    /^---$/ { if (++n == 2) exit; next }
    n == 1 && /^confirmed_count:/ { print $2; exit }
' "$MATCHED_FILE")

CONFIDENCE=$(awk '
    /^---$/ { if (++n == 2) exit; next }
    n == 1 && /^confidence:/ { print $2; exit }
' "$MATCHED_FILE")

# Assemble silent additionalContext
if [ -n "$REMINDER" ]; then
    CONTEXT=$(printf '🛑 Blocker: %s\nPattern: %s (confirmed %s×, confidence %s)\n%s' \
        "$MATCHED_SIGNAL" "$MATCHED_PATTERN" "${CONFIRMED:-?}" "${CONFIDENCE:-?}" "$REMINDER")
else
    CONTEXT=$(printf '🛑 Blocker: %s\nPattern: %s (confirmed %s×, confidence %s)' \
        "$MATCHED_SIGNAL" "$MATCHED_PATTERN" "${CONFIRMED:-?}" "${CONFIDENCE:-?}")
fi

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0
