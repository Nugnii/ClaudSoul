#!/usr/bin/env bash
# budget-gate.sh — PreToolUse[Edit|Write|MultiEdit|NotebookEdit]: самовольная правка при исчерпанном бюджете проактивных действий получает инжект «преврати в вопрос собеседнику» (ADR-010 Ф2).
# en: PreToolUse[Edit|Write|MultiEdit|NotebookEdit]: an unsolicited edit made on an exhausted proactive budget is told to become a question instead (ADR-010 phase 2).
#
# До этого хука `itr_remaining_budget` не читал НИКТО (D17): потолок печатался
# и не действовал. Гейт замыкает петлю: самовольная (unsolicited) правка при
# исчерпанном proactive-бюджете получает advisory-инжект «преврати в вопрос».
#
# Что гейт сознательно НЕ делает (по ADR-010):
#   - не блокирует жёстко: инжект, решение за агентом (исход наблюдаем);
#   - не срабатывает под действующей авторизацией — поручение собеседника
#     не лимитируется бюджетом по замыслу (разбор D19);
#   - не срабатывает без данных: нет файла состояния авторизации → молчание
#     (консервативный уклон: пропуск честнее ложного окрика);
#   - один инжект на сессию (throttle) — напоминание, ставшее фоном, не читают.
#
# Активирован после A/B-прогона Ф3 (scripts/ab-authorization-replay.sh) —
# порядок обязателен по ADR-010: сначала предмет счёта, потом исполнитель.

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
command -v jq >/dev/null 2>&1 || exit 0

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
for _lib in authorization-lib.sh intrusiveness-state-lib.sh; do
    if [ -f "$_HOOK_DIR/$_lib" ]; then . "$_HOOK_DIR/$_lib"
    elif [ -f "$HOME/.claude/hooks/$_lib" ]; then . "$HOME/.claude/hooks/$_lib"
    fi
done
command -v auth_is_active >/dev/null 2>&1 || exit 0
command -v itr_remaining_budget >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0

# Оборона в глубину: matcher уже фильтрует, но проверяем и сами.
case "$TOOL" in
    Edit|Write|MultiEdit|NotebookEdit) ;;
    *) exit 0 ;;
esac

# Действующая авторизация — поручение не лимитируется.
if auth_is_active "$SID" >/dev/null 2>&1; then
    exit 0
fi
# Нет данных об авторизации вовсе — молчание, не окрик.
[ -f "$(auth_state_path "$SID")" ] || exit 0

REMAINING=$(itr_remaining_budget "$SID" proactive 2>/dev/null || echo 1)
case "$REMAINING" in ''|*[!0-9]*) exit 0 ;; esac
[ "$REMAINING" -gt 0 ] && exit 0

# Throttle: один инжект на сессию.
MARKER="$STATE_DIR/budget-gate-fired-${SID}"
[ -f "$MARKER" ] && exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || true
date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER" 2>/dev/null || true

# Наблюдаемость: успех гейта считаем, не только провал (pattern-detector-wired-to-failure).
itr_log_event "$SID" "budget_gate" "surfaced" 0 "tool=$TOOL remaining=0" >/dev/null 2>&1 || true

MSG="⛔ Бюджет проактивных действий исчерпан, действующей авторизации на задачу нет (ADR-010 Ф2). Преврати правку в gentle-вопрос собеседнику или дождись поручения. Правило: самовольные правки при пустом бюджете — как раз то, о чём собеседник предпочёл бы услышать вопросом."
jq -cn --arg msg "$MSG" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $msg}}'
exit 0
