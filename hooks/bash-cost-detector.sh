#!/usr/bin/env bash
# bash-cost-detector.sh — PreToolUse[Bash]: детектирует деструктивные команды (rm -rf, git push --force, DROP) и поднимает silence_cost сигнал для L6 gate.
# en: PreToolUse[Bash]: detects destructive commands (rm -rf, git push --force, DROP) and raises the silence_cost signal for the L6 gate.
#
# Purpose: When the agent is about to run a Bash command, detect destructive
# patterns (rm -rf, git push --force, DROP TABLE, etc.) and elevate the
# session's silence_cost_max signal. The L6 gate then uses this to decide
# if warnings should override the intrusiveness budget.
#
# Decision matrix (destructive_cost from intrusiveness-state-lib):
#   5: catastrophic  → permissionDecision "ask" + loud reason, log override
#   4: dangerous     → permissionDecision "ask" + reason, log override
#   3: moderate      → additionalContext warning (no block), update hints
#   0: safe          → silent, no state mutation
#
# State side-effects (via intrusiveness-state-lib):
#   - cost_hints.silence_cost_max: running max
#   - cost_hints.last_destructive: the command string (truncated to 80 chars)
#   - events += {type:"override", silence_cost, reason} for level >= 4
#   - events += {type:"silence_debt", silence_cost, reason} for level 3
#
# Input: JSON on stdin from Claude Code (PreToolUse event)
# Output: JSON with hookSpecificOutput or empty (for level 0)

set -eo pipefail

# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.claude/hooks/intrusiveness-state-lib.sh"

# Degrade silently if lib is missing or jq unavailable.
[ -f "$LIB" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
# shellcheck source=/dev/null
source "$LIB"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ -z "$SESSION_ID" ] && exit 0
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

COST=$(printf '%s' "$COMMAND" | itr_compute_destructive_cost 2>/dev/null || echo 0)
[ "${COST:-0}" -eq 0 ] && exit 0

itr_init_state "$SESSION_ID" >/dev/null 2>&1 || exit 0

# Truncate command for state storage (keep block readable)
CMD_PREVIEW=$(printf '%s' "$COMMAND" | head -c 80 | tr '\n' ' ')
itr_set_cost_hint "$SESSION_ID" silence_cost_max "$COST" >/dev/null 2>&1 || true
itr_set_cost_hint "$SESSION_ID" last_destructive "$CMD_PREVIEW" >/dev/null 2>&1 || true

case "$COST" in
    5)
        REASON="CATASTROPHIC destructive command detected (cost=5): \`${CMD_PREVIEW}\`. Silence_cost=5 triggers L6 emergency override — voice concerns before proceeding."
        itr_log_event "$SESSION_ID" override pending 5 "$CMD_PREVIEW" >/dev/null 2>&1 || true
        jq -n --arg reason "$REASON" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "ask",
                permissionDecisionReason: $reason
            }
        }'
        ;;
    4)
        REASON="Destructive command detected (cost=4): \`${CMD_PREVIEW}\`. Hard to reverse — confirm intent before running."
        itr_log_event "$SESSION_ID" override pending 4 "$CMD_PREVIEW" >/dev/null 2>&1 || true
        jq -n --arg reason "$REASON" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "ask",
                permissionDecisionReason: $reason
            }
        }'
        ;;
    3)
        CTX="⚠️ Moderate-risk command (silence_cost=3): \`${CMD_PREVIEW}\`. Not blocked — but warning budget will elevate on next gentle/proactive decision. If concerns exist, voice them via gentle suggestion."
        itr_log_event "$SESSION_ID" silence_debt pending 3 "$CMD_PREVIEW" >/dev/null 2>&1 || true
        jq -n --arg ctx "$CTX" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                additionalContext: $ctx
            }
        }'
        ;;
    *)
        exit 0
        ;;
esac
