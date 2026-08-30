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
# Режим по умолчанию — тихий (see feedback_silent_correct_decisions.md):
#   - additionalContext, НЕ systemMessage и НЕ permissionDecision:ask
#   - видимая реакция — выбор агента, а не принуждение хука
#   - шум сам по себе failure mode: хук доставляет сигнал, и только
#
# Режим `enforcement: "deny"` у ОТДЕЛЬНОГО СИГНАЛА (2026-08-28). Повод: замер 19 случаев
# «знание было уместно и не применено» — минимум в девяти прямым текстом сказано, что
# знание было в контексте В МОМЕНТ ДЕЙСТВИЯ. Напоминание как класс поведения не меняет.
# Поправка собеседника: «нужен стопор, который будет заставлять, а не просто напоминать».
#
# Почему deny, а не ask. `ask` останавливает СОБЕСЕДНИКА — по корпусу ~10 вопросов за
# сессию. `deny` останавливает АГЕНТА и собеседника не трогает вовсе, то есть прежнее
# решение «наружу молчим» сохранено, а принуждение появилось. Отказ ОБЯЗАН называть
# замену: отказ по строке команды не убирает потребности
# (case-2026-08-07-denial-targets-command-string-not-intent), поэтому в причину идёт
# `blocker_reminder`, где стоит, чем пользоваться вместо.
#
# Режим у сигнала, а не у знания, намеренно: одно знание отказывает там, где код уезжает
# в файл, и лишь напоминает на разовой команде. Замер разделения за шесть сессий —
# 10 записей признака в файл под hooks/scripts против 35 разовых команд.

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
        # Признак совпал, страж промолчал по троттлу — знаменатель (D205): журнал
        # `blocker-fired` пишется ПОСЛЕ решения сказать, и доля «сказал против промолчал»
        # по нему непосчитаема по построению.
        _RC_LIB="${RC_LIB:-$LIB_DIR/root-cause-lib.sh}"
        [ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
        # shellcheck source=/dev/null
        [ -f "$_RC_LIB" ] && . "$_RC_LIB"
        command -v rc_note_detection >/dev/null 2>&1 && \
            rc_note_detection "$STATE_DIR" "$SESSION_ID" "blocker-tier-check" "muted" "$throttle_key"
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
# Знаменатель (D205): признак совпал И страж заговорил. Пара с `muted` выше делает долю
# «сказал против промолчал» посчитаемой — по одному лишь `blocker-fired` она непосчитаема.
_RC_LIB="${RC_LIB:-$LIB_DIR/root-cause-lib.sh}"
[ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
[ -f "$_RC_LIB" ] && . "$_RC_LIB"
command -v rc_note_detection >/dev/null 2>&1 && \
    rc_note_detection "$STATE_DIR" "$SESSION_ID" "blocker-tier-check" "said" "$MATCHED_KEY"

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

# Режим принуждения берётся у СОВПАВШЕГО сигнала, не у знания. Среди совпавших выбирается
# СИЛЬНЕЙШИЙ, а не первый по порядку.
#
# Найдено живой пробой 2026-08-28: `ds_evaluate` возвращает первый совпавший сигнал, и в
# знании первой стояла ветвь разовой команды без принуждения — отказ не наступал никогда.
# Исход зависел от порядка строк в файле знания, то есть от того, куда автор вписал ветвь.
# Порядок — не признак; это тот же класс, что ключ дедупа по виду сигнала.
ENFORCEMENT=""
if [ -n "${MATCHED_FILE:-}" ] && [ -n "${MATCHED_SIGNAL:-}" ]; then
    ENFORCEMENT=$(ds_extract_signals "$MATCHED_FILE" 2>/dev/null \
        | jq -r --arg n "$MATCHED_SIGNAL" '.[]? | select(.name == $n) | .enforcement // empty' 2>/dev/null | head -1)
    if [ "$ENFORCEMENT" != "deny" ]; then
        while IFS= read -r _strict; do
            [ -n "$_strict" ] || continue
            _sig_json=$(ds_extract_signals "$MATCHED_FILE" 2>/dev/null \
                | jq -c --arg n "$_strict" '.[]? | select(.name == $n)' 2>/dev/null | head -1)
            [ -n "$_sig_json" ] || continue
            if ds_evaluate_signal "$_sig_json" "$TOOL_NAME" "$TOOL_INPUT" "$PROMPT" >/dev/null 2>&1; then
                ENFORCEMENT="deny"
                MATCHED_SIGNAL="$_strict"
                break
            fi
        done <<< "$(ds_extract_signals "$MATCHED_FILE" 2>/dev/null \
            | jq -r '.[]? | select(.enforcement == "deny") | .name' 2>/dev/null)"
    fi
fi

# Замена у СИГНАЛА, а не только у знания. Отказ обязан называть, что делать вместо, —
# и для разных сигналов одного знания это разные вещи: «инструмента здесь нет» и «цикл
# под zsh не делится по словам» чинятся по-разному. Общий blocker_reminder на отказе
# читался как не относящийся к делу, а отказ, чью причину не понимают, обходят.
if [ -n "${MATCHED_FILE:-}" ] && [ -n "${MATCHED_SIGNAL:-}" ]; then
    _remedy=$(ds_extract_signals "$MATCHED_FILE" 2>/dev/null \
        | jq -r --arg n "$MATCHED_SIGNAL" '.[]? | select(.name == $n) | .remedy // empty' 2>/dev/null | head -1)
    [ -n "$_remedy" ] && REMINDER="$_remedy"
fi

# Assemble silent additionalContext
if [ -n "$REMINDER" ]; then
    CONTEXT=$(printf '🛑 Blocker: %s\nPattern: %s (confirmed %s×, confidence %s)\n%s' \
        "$MATCHED_SIGNAL" "$MATCHED_PATTERN" "${CONFIRMED:-?}" "${CONFIDENCE:-?}" "$REMINDER")
else
    CONTEXT=$(printf '🛑 Blocker: %s\nPattern: %s (confirmed %s×, confidence %s)' \
        "$MATCHED_SIGNAL" "$MATCHED_PATTERN" "${CONFIRMED:-?}" "${CONFIDENCE:-?}")
fi

if [ "${ENFORCEMENT:-}" = "deny" ]; then
    # Причина обязана нести замену — иначе отказ только мешает, а потребность остаётся.
    #
    # Собственная метка «⛔ ОТКАЗ» — не украшение. Замер эффекта стопоров считает отказы по
    # расшифровкам, а тихое напоминание и отказ до 28 августа 2026 несли ОДИН И ТОТ ЖЕ
    # текст (`🛑 Blocker: …`). На первом же прогоне замер насчитал 43 «отказа» у механизма,
    # прожившего час. Признак был взят из замысла, а не из наблюдаемого различия путей.
    CONTEXT="⛔ ОТКАЗ (вызов не выполнен). $CONTEXT"
    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $ctx
        }
    }'
    exit 0
fi

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0
