#!/usr/bin/env bash
# inquiry-gap.sh — UserPromptSubmit: вопрос собеседника ≠ поручение.
# en: a user QUESTION gets an answer first — not a build; if the question exposes a missing mechanism, gap analysis comes before any construction.
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

grep -q '?' <<< "$USER_PROMPT" || exit 0

# Свёртка регистра — to_lower из portable-lib (GNU tr кириллицу не сворачивает);
# заглавные написания перечислены явно на случай отсутствия библиотеки —
# тот же канон, что в external-correction-gap.
# Отсев чужой речи (D88, применено 2026-08-28). Словарь применяется к речи собеседника,
# а в неё попадают цитаты, пересылки и вставленные документы — они дают срабатывания на
# тексте, которого собеседник не писал. Замер по корпусу: отсев меняет 30 реплик из 107,
# полностью обнуляет 1 — то есть примерно раз на сотню хук ослепнет на настоящей реплике.
# Цена принята: у user-correction-guard замер D88 дал 96 срабатываний вне цитат.
INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hook-input-lib.sh}"
[ -f "$INPUT_LIB" ] || INPUT_LIB="$HOME/.claude/hooks/hook-input-lib.sh"
# shellcheck source=/dev/null
[ -f "$INPUT_LIB" ] && . "$INPUT_LIB"
own_speech_of() {   # текст собеседника без чужого; без библиотеки — как было
    if command -v user_own_speech >/dev/null 2>&1; then user_own_speech "${1:-}"; else printf %s "${1:-}"; fi
}
LOWER=$(to_lower "$(own_speech_of "$USER_PROMPT")")
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

# ── Вопрос становится СОСТОЯНИЕМ сессии, а не только репликой в ходе ──────────
# До 29 августа 2026 хук печатал предписание и не оставлял следа: ни одной записи в
# состояние, только чтение `intrusiveness-<SID>.json` выше. Следствие двоякое и
# измеренное в тот же день: гейт разбора (`five-whys-gate.sh`) не мог считать вопрос
# поводом для спуска, потому что читает состояние, а на Write/Edit некому было спросить
# «вопрос открыт, слова строить не было». Повод собеседника дословно: «сигнал поправки
# наравне с переделкой и провалами а как же мои вопросы?».
#
# Повод, не оставляющий следа, не может быть предметом НИКАКОЙ последующей проверки —
# это и есть звено, которое здесь убирается.
#
# НАЗВАННЫЙ ПРЕДЕЛ: словарь ловит вопросительное слово, а не род вопроса. Вопрос о ФАКТЕ
# («как запустить тесты?») попадёт в сигнал наравне с вопросом, вскрывающим дыру, хотя
# закрывается он справкой, а не спуском к причине. Поэтому сигнал СТОЯЧИЙ: гейт по нему
# напоминает и не отказывает — расширять отказ на неизмеренный признак запрещено тем же
# правилом, что записано в шапке `five-whys-gate.sh`.
# Условие снятия: предел перестаёт держаться, когда измерена доля вопросов о факте среди
# срабатываний и она отделима признаком — тогда род вопроса становится частью сигнала.
QFILE="$STATE_DIR/question-open-${SESSION_ID}.jsonl"
mkdir -p "$STATE_DIR" 2>/dev/null
# Дозапись в JSONL требует, чтобы файл кончался переводом строки: оборванная последняя
# строка склеится с новой и обе станут нечитаемыми. Тот же дефект чинили 29 августа 2026
# в `knowledge-counter-bump.sh`.
if [ -s "$QFILE" ] && [ "$(tail -c 1 "$QFILE" 2>/dev/null | od -An -c | tr -d ' ')" != "\\n" ]; then
    printf '\n' >> "$QFILE" 2>/dev/null
fi
Q_DIGEST=$(printf '%s' "$LOWER" | cksum 2>/dev/null | awk '{print $1}')
printf '{"date":"%s","kind":"question","digest":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${Q_DIGEST:-0}" >> "$QFILE" 2>/dev/null

MESSAGE="❓ Это вопрос, не поручение. Порядок: (1) ОТВЕТИТЬ на вопрос; (2) если вопрос вскрывает отсутствие механизма или дыру — разбор «почему этого нет и почему сам не догадался» (катчабельность внутренним знанием, счётчики, цепочка почему) ДО какой-либо стройки; (3) строить — только после явного слова собеседника. Инерция односложных поручений не перекрашивает вопрос в заказ. (4) НЕТ СЛОВА — ход всё равно кончается ИСХОДОМ, а не пустотой: запись пункта в BACKLOG.md либо названный план с вопросом «приступать?». Оба исполнимы без разрешения; «жду слова» без плана перекладывает проектирование на собеседника. Происхождение: поправка собеседника 2026-08-08 («и ты ринулся»); пункт (4) — 29 августа 2026, ход кончился разбором до корня и нулём исхода."

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
