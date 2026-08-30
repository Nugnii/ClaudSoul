#!/usr/bin/env bash
# external-correction-gap.sh — детекция внешней рецензии в UserPromptSubmit.
# en: UserPromptSubmit: external review detection — demands a gap analysis (catchable by own knowledge?) before accepting third-party corrections.
#
# Зачем. Поправка внешнего рецензента — это пойманный чужими руками собственный
# промах, но ни один механизм её так не классифицировал: error-tracker видит
# только упавшие команды, Predictions требует гэп-разбора при miss, а поле
# заполнялось без разбора. Итог дня 2026-08-08: четыре из семи обязательных
# поправок рецензента были катчабельны уже имевшимися знаниями
# (pattern-inside-out-blindness инжектился в ту же сессию и не применился к
# собственному дизайну). Согласие — дешёвое продолжение; пауза «почему я это
# пропустил» против течения разговора и сама не возникает — отсюда инжект.
# Происхождение: _drafts/case-2026-08-08-ablation-as-maturity-step.md (5 итераций).
#
# Сигнал узкий, по решению (правило «узко, иначе алерт становится фоном»):
# только маркеры пересланной внешней рецензии (рецензент/рецензи/вердикт/
# оценщик/reviewer). Обычное «сделай ревью» — просьба ко мне, не внешняя
# правка, не ловится намеренно.
#
# Guards: no prompt/session → exit; distressed → silent (AP2). Throttle нет
# намеренно: рецензия приходит раундами, каждый раунд — отдельное событие
# промаха и требует своего гэп-разбора (решение собеседника, 2026-08-08).
# Output: jq hookSpecificOutput с additionalContext (advisory, не blocker).

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

mkdir -p "$STATE_DIR" 2>/dev/null || true

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
USER_PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null)

[ -z "$USER_PROMPT" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

# Системные уведомления (фоновые задачи, мониторы) — не внешняя рецензия:
# маркеры в них — эхо собственных слов агента (2-е ложное срабатывание 2026-08-08,
# «вердикт» в описании монитора CI).
case "$USER_PROMPT" in
    *"[SYSTEM NOTIFICATION"*|*"<task-notification>"*) exit 0 ;;
esac

# Маркеры пересланной внешней рецензии. Свёртка регистра — to_lower из
# portable-lib (GNU tr кириллицу не сворачивает); fallback-написания с заглавной
# перечислены явно на случай отсутствия библиотеки.
USER_LOWER=$(to_lower "$USER_PROMPT")
MATCHED=0
case "$USER_LOWER" in
    *"рецензент"*|*"Рецензент"*|*"рецензи"*|*"Рецензи"*|*"вердикт"*|*"Вердикт"*|*"оценщик"*|*"Оценщик"*|*"reviewer"*) MATCHED=1 ;;
esac
[ "$MATCHED" -eq 0 ] && exit 0

# AP2: в distressed ничего не инжектим
STATE_FILE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(jq -r '.state_axis // "idle"' "$STATE_FILE" 2>/dev/null)
    [ "$CURRENT_STATE" = "distressed" ] && exit 0
fi

MESSAGE="🔍 Внешняя рецензия/правка детектирована. Прежде чем принять поправки к своему артефакту — гэп-разбор, ДО «отличная поправка, вшил»:

1. По каждой принятой поправке: катчабельна ли она внутренним знанием? Если да — назови файл знания и зафиксируй разрыв «знание→действие» (исход через knowledge-counter-bump.sh либо запись applicable_not_followed).
2. Цепочка «почему не поймал сам» — минимум 3 уровня «почему» (проверял форму вместо пути? роль атакующего не назначена? промах не оставляет машинного следа?).
3. SESSION.md → Predictions: exact/adjacent/miss + при miss gap:literal/pragmatic/strategic.

Принятая внешняя поправка = пойманный чужими руками собственный промах, а не только прогресс артефакта. Происхождение: case-2026-08-08-ablation-as-maturity-step."

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
