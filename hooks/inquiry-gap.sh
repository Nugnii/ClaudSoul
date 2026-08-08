#!/usr/bin/env bash
# inquiry-gap.sh — UserPromptSubmit: вопрос собеседника ≠ поручение.
# en: a user QUESTION gets an answer first — not a build; if the question
# exposes a missing mechanism, gap analysis comes before any construction.
#
# Происхождение (2026-08-08, три поправки собеседника подряд): вопрос «как это
# работает? мне постоянно нужно помнить про фазу?» был встречен стройкой
# механизма — без ответа, без разбора «почему этого нет и почему сам не
# догадался». Классы «пересланная рецензия» (external-correction-gap) и «принятие
# альтернативы» (accepted-alternative-gap) покрыты, а «вскрывающий вопрос» не
# ловил никто — разбор держался на воле модели, воля проиграла инерции
# односложных поручений («делай», «резь», «добивай»).
#
# Сигнал узкий: короткое сообщение + знак вопроса + вопросительное слово.
# Guards: системные уведомления — мимо; distressed (AP2) — тихо; длинные
# сообщения (вопрос внутри вставки/лога) — мимо. Throttle нет: каждый вопрос —
# отдельное событие (решение 2026-08-08 о постоянных механизмах).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
elif [ -f "$HOME/.claude/hooks/portable-lib.sh" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.claude/hooks/portable-lib.sh"
else
    to_lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }
fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
USER_PROMPT=$(printf '%s' "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null)

[ -z "$USER_PROMPT" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

# Системные уведомления — эхо своих слов, не вопрос собеседника.
case "$USER_PROMPT" in
    *"[SYSTEM NOTIFICATION"*|*"<task-notification>"*) exit 0 ;;
esac

# Длинное сообщение = вопрос внутри вставки (лог, цитата) — не наш случай.
[ "${#USER_PROMPT}" -gt 400 ] && exit 0

printf '%s' "$USER_PROMPT" | grep -q '?' || exit 0

# Свёртка регистра — to_lower из portable-lib (GNU tr кириллицу не сворачивает);
# заглавные написания перечислены явно на случай отсутствия библиотеки —
# тот же канон, что в external-correction-gap.
LOWER=$(to_lower "$USER_PROMPT")
MATCHED=0
case "$LOWER" in
    *"как "*|*"Как "*|*"почему "*|*"Почему "*|*"зачем "*|*"Зачем "*|*"нужно ли"*|*"Нужно ли"*|*"мне нужно"*|*"Мне нужно"*|*"нужно помнить"*|*"откуда "*|*"Откуда "*) MATCHED=1 ;;
esac
[ "$MATCHED" -eq 0 ] && exit 0

# AP2: в distressed ничего не инжектим.
STATE_FILE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(jq -r '.state_axis // "idle"' "$STATE_FILE" 2>/dev/null)
    [ "$CURRENT_STATE" = "distressed" ] && exit 0
fi

MESSAGE="❓ Это вопрос, не поручение. Порядок: (1) ОТВЕТИТЬ на вопрос; (2) если вопрос вскрывает отсутствие механизма или дыру — разбор «почему этого нет и почему сам не догадался» (катчабельность внутренним знанием, счётчики, цепочка почему) ДО какой-либо стройки; (3) строить — только после явного слова собеседника. Инерция односложных поручений не перекрашивает вопрос в заказ. Происхождение: поправка собеседника 2026-08-08 («и ты ринулся»)."

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
