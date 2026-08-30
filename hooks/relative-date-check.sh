#!/usr/bin/env bash
# relative-date-check.sh — Stop/PreCompact: относительное время («вчера», «на днях», «час назад») без абсолютного якоря рядом — находка; в следующем ходе показывает её вместе с текущими датой и временем.
# en: Stop/PreCompact: flags relative time expressions ("вчера", "на днях", "час назад") written without an absolute date or clock-time anchor next to them; surfaces the correction plus the current date and time on the next turn.
#
# Правило «даты только абсолютные» в проекте уже механизировано, но лишь на
# одной поверхности: `test_backlog_relative_dates.sh` держит пункты BACKLOG
# (корень 2026-08-08 — «сегодня» в пункте прожило неделю, датировать пришлось
# раскопкой git). В тексте ответа то же правило держалось на памяти и не
# держалось: «вчера»/«сегодня» пишутся из близости события в разговоре, а не из
# вычитания дат (заявка собеседника 2026-08-21).
#
# В прозе относительное слово запрещать нельзя — запрещается слово БЕЗ даты
# рядом: «вчера (20 августа)» чисто. Требование написать дату делает вычитание
# обязательным шагом, а промах — видимым собеседнику сразу.
#
# Уровень 2 (activator injection) principle-knowledge-in-the-world: события
# «BeforeAssistantMessage» в Claude Code нет, поэтому реплику не перехватить —
# находка гасится в следующем ходе. Образец плюмбинга: output-language-check.sh.
#
# Тихая деградация: нет jq/python3/детектора/транскрипта — exit 0 без вывода.

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR="${HOOK_DIR}/lib/relative-date-detect.py"
[ -f "$DETECTOR" ] || DETECTOR="$HOME/.claude/hooks/lib/relative-date-detect.py"
[ -f "$DETECTOR" ] || exit 0

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$SID" ] && exit 0
FINDINGS_FILE="${STATE_DIR}/relative-date-findings-${SID}.jsonl"

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

    local findings
    findings=$(printf '%s' "$last_assistant" | python3 "$DETECTOR" 2>/dev/null)
    [ -z "$findings" ] && return 0

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    while IFS= read -r finding; do
        [ -z "$finding" ] && continue
        if [ -f "$FINDINGS_FILE" ]; then
            if jq -e --arg f "$finding" 'select(.finding==$f)' "$FINDINGS_FILE" >/dev/null 2>&1; then
                continue
            fi
        fi
        jq -cn \
            --arg ts "$ts" --arg sid "$SID" --arg finding "$finding" --arg event "$EVENT" \
            '{ts:$ts, sid:$sid, event:$event, finding:$finding, status:"pending"}' \
            >> "$FINDINGS_FILE" 2>/dev/null || true
    done <<< "$findings"
}

surface_pending() {
    local event_name="${1:-UserPromptSubmit}"
    [ -f "$FINDINGS_FILE" ] || return 0

    local pending
    pending=$(jq -r 'select(.status=="pending") | .finding' "$FINDINGS_FILE" 2>/dev/null \
              | awk '!seen[$0]++' | head -5)
    [ -z "$pending" ] && return 0

    local list now msg
    list=$(printf '%s' "$pending" | awk 'BEGIN{ORS=""} NR>1{printf " | "} {printf "%s", $0}')
    [ -z "$list" ] && return 0
    now=$(date '+%Y-%m-%d %H:%M %Z' 2>/dev/null)

    msg="📅 Относительное время без якоря (сейчас ${now}): ${list}. Правило «даты только абсолютные» (то же, что держит пункты BACKLOG): сверь время события с текущим и поставь абсолютный якорь рядом — «вчера (20 августа)», «час назад (в 19:40)» либо просто «20 августа». Если сверка показала, что слово было неверным — поправь по существу, а не только форму."

    jq -cn --arg msg "$msg" --arg ev "$event_name" \
        '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $msg}}'

    local tmp
    tmp=$(mktemp 2>/dev/null) || return 0
    jq -c 'if .status=="pending" then .status="surfaced" else . end' \
        "$FINDINGS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$FINDINGS_FILE" || rm -f "$tmp"
}

case "$EVENT" in
    Stop|PreCompact)  scan_and_persist ;;
    UserPromptSubmit) surface_pending "UserPromptSubmit" ;;
    PreToolUse)       surface_pending "PreToolUse" ;;
esac

exit 0
