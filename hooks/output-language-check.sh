#!/usr/bin/env bash
# output-language-check.sh — post-output scanner for mixed-alphabet tokens.
#
# Purpose:
#   Closes the L1 gap for output-level rules. Memory file
#   `feedback_pure_language_no_alphabet_mixing.md` forbids tokens mixing
#   Cyrillic and Latin letters in one word (e.g. "trёх", "fix'ом", "лookup'ов").
#   The rule lives as passive feedback in project memory and depends on the
#   agent remembering to proofread — which fails in practice (2 recorded
#   incidents: enrich v0.5.0 "лookup'ов"; 2026-04-24 "trёх").
#
#   Claude Code hook events do not include "BeforeAssistantMessage", so the
#   violation cannot be blocked pre-delivery. This hook implements level 2
#   (activator injection) of principle-knowledge-in-the-world:
#
#   - On Stop / PreCompact: scan last assistant message, persist violations
#     to state/output-violations-${SID}.jsonl.
#   - On UserPromptSubmit: if pending violations exist, inject context via
#     hookSpecificOutput.additionalContext so the agent acknowledges the
#     violation in the next response and avoids repetition in-session.
#
# Scope:
#   Per-speaker rule (this user explicitly forbids alphabet mixing in feedback
#   memory). Detection is cheap and static — runs on every turn close without
#   LLM cost. Cap list at 10 tokens to keep injection bounded.
#
# Exclusions (to avoid false positives):
#   - Fenced code blocks and inline code
#   - Filesystem paths (contain "/")
#   - URLs (http://, https://, mailto:)
#   - Identifier-like tokens (contain "@", ":", digits + letters, "_")
#
# Silent degradation: missing jq/python3, unreadable transcript, empty
# content — exit 0 without output. Never block the turn.

set -eo pipefail

HOOK_NAME="output-language-check"
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR="${HOOK_DIR}/lib/output-language-detect.py"
[ -f "$DETECTOR" ] || exit 0

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$SID" ] && exit 0
VIOLATIONS_FILE="${STATE_DIR}/output-violations-${SID}.jsonl"

scan_and_persist() {
    [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || return 0

    local last_assistant
    last_assistant=$(jq -s '
        def role(x): x.message.role // x.role // "";
        def get_text(x):
            (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then
                ($c | map(select(.type == "text") | .text) | join("\n"))
            elif ($c | type) == "string" then $c
            else "" end;
        . as $items | (length) as $n |
        ([range(0; $n) | ($n - 1 - .)
          | select((role($items[.]) == "user" and
                   ((get_text($items[.]) // "") | length > 0))
                   or (($items[.].type // "") == "last-prompt"))]
          | first) as $pu |
        if $pu == null then
            ([range(0; $n) | $items[.] | select(role(.) == "assistant")]
             | map(get_text(.)) | map(select(. != "")) | join("\n"))
        else
            ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]
             | map(get_text(.)) | map(select(. != "")) | join("\n"))
        end
    ' "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.' 2>/dev/null)

    [ -z "$last_assistant" ] && return 0
    [ "$last_assistant" = "null" ] && return 0

    local violations
    violations=$(printf '%s' "$last_assistant" | python3 "$DETECTOR" 2>/dev/null)

    [ -z "$violations" ] && return 0

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    while IFS= read -r token; do
        [ -z "$token" ] && continue
        # Dedup against already-recorded tokens (any status) for this session
        if [ -f "$VIOLATIONS_FILE" ]; then
            if jq -e --arg t "$token" 'select(.token==$t)' "$VIOLATIONS_FILE" >/dev/null 2>&1; then
                continue
            fi
        fi
        jq -cn \
            --arg ts "$ts" --arg sid "$SID" --arg token "$token" --arg event "$EVENT" \
            '{ts:$ts, sid:$sid, event:$event, token:$token, status:"pending"}' \
            >> "$VIOLATIONS_FILE" 2>/dev/null || true
    done <<< "$violations"
}

surface_pending() {
    # $1 — hookEventName for the output envelope (UserPromptSubmit | PreToolUse).
    # Same surface logic on both events; first-to-fire marks tokens surfaced,
    # subsequent calls see no pending and exit silent. This is level 2b
    # (PreToolUse channel) layered on level 2a (UserPromptSubmit channel) —
    # PreToolUse fires more often, closing the latency gap during multi-message
    # work bursts (case-2026-04-25-level-2-feedback-latency).
    local event_name="${1:-UserPromptSubmit}"

    [ -f "$VIOLATIONS_FILE" ] || return 0

    local pending
    pending=$(jq -r 'select(.status=="pending") | .token' "$VIOLATIONS_FILE" 2>/dev/null \
              | awk '!seen[$0]++' \
              | head -10)
    [ -z "$pending" ] && return 0

    local token_list
    token_list=$(printf '%s' "$pending" | awk 'BEGIN{ORS=""} NR>1{printf ", "} {printf "%s", $0}')
    [ -z "$token_list" ] && return 0

    local msg
    msg="🔤 Output language check: в предыдущем ответе обнаружены токены со смешением алфавитов — ${token_list}. Правило feedback_pure_language_no_alphabet_mixing: писать чисто по-русски или чисто латиницей, не смешивать в одном слове. Исправь в следующем ответе и не повторяй в текущей сессии."

    jq -cn --arg msg "$msg" --arg ev "$event_name" \
        '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $msg}}'

    # Mark surfaced tokens so we don't re-inject on every event.
    local tmp
    tmp=$(mktemp 2>/dev/null) || return 0
    jq -c 'if .status=="pending" then .status="surfaced" else . end' \
        "$VIOLATIONS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$VIOLATIONS_FILE" || rm -f "$tmp"
}

case "$EVENT" in
    Stop|PreCompact)
        scan_and_persist
        ;;
    UserPromptSubmit)
        surface_pending "UserPromptSubmit"
        ;;
    PreToolUse)
        surface_pending "PreToolUse"
        ;;
esac

exit 0
