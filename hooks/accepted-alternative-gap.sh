#!/usr/bin/env bash
# accepted-alternative-gap.sh — Stop: принятие варианта собеседника = событие промаха.
# en: Stop hook — detects "your variant is better" acceptance in the assistant's
# last reply and demands the same gap analysis as external-correction-gap.
#
# Зачем. external-correction-gap ловит пересланную внешнюю рецензию, но класс
# шире: обстоятельство, вскрывшееся в диалоге и меняющее разработку, — тоже
# пойманный чужими руками собственный промах. Момент события — собственная
# фраза принятия («твой вариант лучше», «отличная идея»); она видна только в
# транскрипте на Stop. Поверхность выбрана по своей реплике, а не по словарю
# собеседника: детект своей фразы механический, словарь встречных предложений —
# гадание с гарантированными пропусками. Расширение класса — решение
# собеседника 2026-08-08 (вместе со снятием одноразовости external-correction-gap).
#
# Guards: нет transcript/session → тихо; distressed → тихо (AP2); в той же
# реплике уже есть «гэп-разбор» → молчит (дисциплина исполнена). Throttle нет
# намеренно: каждый акт принятия — отдельное событие.
# Output: jq hookSpecificOutput с additionalContext (advisory, придёт следующим
# ходом — как у output-language-check на Stop).

set -eo pipefail

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
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0
[ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || exit 0

# Реплики ассистента после последнего сообщения собеседника (образец:
# output-language-check.sh — та же выборка, тот же формат транскрипта).
LAST_ASSISTANT=$(jq -s '
    def role(x): x.message.role // x.role // "";
    def get_text(x):
        (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then
            ($c | map(select(.type == "text") | .text) | join("\n"))
        elif ($c | type) == "string" then $c
        else "" end;
    . as $items | (length) as $n |
    ([range(0; $n) | ($n - 1 - .)
      | select(role($items[.]) == "user" and
               ((get_text($items[.]) // "") | length > 0))]
      | first) as $pu |
    if $pu == null then
        ([range(0; $n) | $items[.] | select(role(.) == "assistant")]
         | map(get_text(.)) | map(select(. != "")) | join("\n"))
    else
        ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]
         | map(get_text(.)) | map(select(. != "")) | join("\n"))
    end
' "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.' 2>/dev/null)

[ -z "$LAST_ASSISTANT" ] && exit 0
[ "$LAST_ASSISTANT" = "null" ] && exit 0

LOWER=$(to_lower "$LAST_ASSISTANT")

# Маркеры принятия чужого варианта — узко, по своей фразе (правило «узко,
# иначе алерт становится фоном»). Обычное согласие («да», «ок») не ловится.
MATCHED=0
case "$LOWER" in
    *"твой вариант лучше"*|*"ваш вариант лучше"*|*"вариант лучше моего"*|*"лучше моего варианта"*|*"отличная идея"*|*"беру твой вариант"*|*"беру ваш вариант"*) MATCHED=1 ;;
esac
[ "$MATCHED" -eq 0 ] && exit 0

# Дисциплина уже исполнена в той же реплике → молчим
case "$LOWER" in
    *"гэп-разбор"*|*"катчабельн"*) exit 0 ;;
esac

# AP2: в distressed ничего не инжектим
STATE_FILE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(jq -r '.state_axis // "idle"' "$STATE_FILE" 2>/dev/null)
    [ "$CURRENT_STATE" = "distressed" ] && exit 0
fi

MESSAGE="🔁 В прошлой реплике принят вариант/обстоятельство собеседника («твой вариант лучше» / «отличная идея»). Это то же событие, что внешняя рецензия: пойманный чужими руками собственный промах, а не только прогресс. Гэп-разбор, если ещё не сделан:

1. Катчабельно ли принятое внутренним знанием? Если да — назови файл знания и зафиксируй разрыв «знание→действие» (исход через knowledge-counter-bump.sh либо запись applicable_not_followed).
2. Цепочка «почему не предложил сам» — минимум 3 уровня «почему».
3. SESSION.md → Predictions: exact/adjacent/miss + при miss gap:literal/pragmatic/strategic.

Происхождение: case-2026-08-08-ablation-as-maturity-step (расширение класса external-correction-gap)."

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: .
  }
}'
