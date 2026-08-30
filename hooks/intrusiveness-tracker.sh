#!/usr/bin/env bash
# intrusiveness-tracker.sh — UserPromptSubmit: поддерживает состояние L6 intrusiveness gate, классифицирует state (focus/idle/stuck/exploration), инжектит в контекст.
# en: UserPromptSubmit: maintains L6 intrusiveness gate state, classifies the interlocutor's state (focus/idle/stuck/exploration).
#
# Purpose:
#   Keeps the intrusiveness state alive across a session and injects the
#   current state into every UserPromptSubmit context block so that the
#   agent sees the remaining budget, silence debt, and last-event history
#   before it decides to speak.
#
# Schema and library: hooks/intrusiveness-state-lib.sh
# State files: ~/.claude/hooks/state/intrusiveness-<SESSION_ID>.json
#
# This hook does NOT mutate state automatically (that's the agent's job via
# Bash `intrusiveness-state-lib.sh log ...`). It only reads + injects.
# Exception: it prunes state files older than 7 days on each run.

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# Библиотека ищется рядом со скриптом (как PATHS_LIB выше), с откатом на
# установленную копию. Различие между машинами не в утилитах, а в наличии
# каталога: жёсткий $HOME-путь есть только там, где ClaudSoul уже установлен.
# На чистой машине (Linux-контейнер) прогон из репозитория его не находил —
# хук молча выходил, и проверка «состояние наполнено → хук говорит» получала
# тишину. В проде хук запускается как `bash ~/.claude/hooks/...`, поэтому
# сосед совпадает с прежним путём — поведение установленной системы не меняется.
LIB="${ITR_STATE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/intrusiveness-state-lib.sh}"
[ -f "$LIB" ] || LIB="$HOME/.claude/hooks/intrusiveness-state-lib.sh"

# Degrade silently if the library is missing (e.g. partial install).
[ -f "$LIB" ] || exit 0
# shellcheck source=/dev/null
source "$LIB"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# Ensure state exists (first turn creates empty scaffold — no injection yet).
itr_init_state "$SESSION_ID" >/dev/null 2>&1 || exit 0

# Compute timing_cost and state (4D gate 4th axis) from the user's prompt text.
# Prompt can live in .prompt (common) or .user_prompt — check both defensively.
PROMPT_TEXT=$(echo "$INPUT" | jq -r '(.prompt // .user_prompt // "") | tostring')
if [ -n "$PROMPT_TEXT" ] && [ "$PROMPT_TEXT" != "null" ]; then
    TIMING_COST=$(printf '%s' "$PROMPT_TEXT" | itr_compute_timing_cost 2>/dev/null || echo 0)
    itr_set_cost_hint "$SESSION_ID" timing_cost_current "$TIMING_COST" >/dev/null 2>&1 || true

    # State classifier (v1.3.3): focus | stuck | exploration | idle.
    # Output: "state|confidence|reasons_csv". Parse and persist.
    STATE_TRIPLE=$(itr_compute_state "$SESSION_ID" "$PROMPT_TEXT" 2>/dev/null || echo "idle|1|default")
    ST_CURRENT="${STATE_TRIPLE%%|*}"
    ST_REST="${STATE_TRIPLE#*|}"
    ST_CONF="${ST_REST%%|*}"
    ST_REASONS="${ST_REST#*|}"
    case "$ST_CURRENT" in
        focus|stuck|exploration|idle|distressed) ;;
        *) ST_CURRENT="idle"; ST_CONF=1; ST_REASONS="fallback" ;;
    esac
    itr_set_state "$SESSION_ID" "$ST_CURRENT" "$ST_CONF" "$ST_REASONS" >/dev/null 2>&1 || true
fi

# Format context block. Returns 1 when state is trivially empty — in which
# case we stay silent (no injection noise on a fresh session).
CONTEXT_BLOCK=$(itr_format_context "$SESSION_ID" 2>/dev/null) || exit 0
[ -z "$CONTEXT_BLOCK" ] && exit 0

# H12 measurement: track peak injection size per session as proxy for
# token-budget pressure from cascading guardrails. We measure THIS hook's
# context block (not all hooks combined — that would require coordination).
# Aggregated by session-collector into intrusiveness-history.cost_peaks.
PEAK_FILE="$STATE_DIR/injection-bytes-peak-${SESSION_ID}"
CTX_BYTES=$(printf '%s' "$CONTEXT_BLOCK" | wc -c | tr -d '[:space:]')
PREV_PEAK=0
if [ -f "$PEAK_FILE" ]; then
    PREV_PEAK=$(cat "$PEAK_FILE" 2>/dev/null | tr -d '[:space:]')
    [ -z "$PREV_PEAK" ] && PREV_PEAK=0
fi
if [ "${CTX_BYTES:-0}" -gt "${PREV_PEAK:-0}" ] 2>/dev/null; then
    echo "$CTX_BYTES" > "$PEAK_FILE"
fi

# Emit additionalContext for the agent.
jq -n \
    --arg ctx "$CONTEXT_BLOCK" \
    '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $ctx
        }
    }'

# Housekeeping: prune state files older than 7 days. Non-fatal on failure.
find "$STATE_DIR" -name "intrusiveness-*.json" -type f -mtime +7 -delete 2>/dev/null || true
