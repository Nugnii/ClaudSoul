#!/usr/bin/env bash
# decompose-detector.sh — pre-execution router в UserPromptSubmit: шаги→/decompose, решения→/grilling.
# en: UserPromptSubmit: pre-execution router — suggests /decompose for multi-step requests, /grilling for open-decision/vague ones.
# Одна подсказка за промпт (взаимоисключение), silent inject; агент решает применять.
#
# Две группы сигналов:
#   ШАГИ (→/decompose): нумерованные строки, буллеты, коннекторы затем/потом/далее, then/next.
#   РЕШЕНИЯ (→/grilling): маркеры выбора и дизайна — либо, как лучше, какой вариант,
#     не уверен, продумай/проработай, спроектируй, архитектур, как реализовать/организовать.
#
# Ветвление (чистое взаимоисключение, максимум одна подсказка):
#   решений ≥2 И решений > шагов → /grilling; иначе шагов ≥4 → /decompose; иначе тихо.
#   Почему решения в приоритете при равенстве-с-перевесом: открытые решения надо
#   разрешить ДО плана, иначе /decompose распланирует несогласованное.
#
# Гварды:
#   - prompt < 100 chars: skip (trivial)
#   - уже упомянут любой из инструментов (decompose/разбей/grilling/грилинг/грил/
#     adversary/противник/хейтер/прожар): skip. Список ведётся по ИМЕНАМ инструментов,
#     а не по их триггерам, и имя каждого нужно в ОБОИХ написаниях: скиллы зовутся
#     латиницей, но собеседник продолжает говорить по-русски. `adversary` и `противник`
#     здесь отсутствовали до 28 августа 2026 — стоял только триггер «прожар», из-за чего
#     «прогони adversary» получало совет вызвать то, что уже названо.
#   - state = focus или stuck: skip (неудачное окно)
#   - уже inject'или в этой сессии: skip (общий throttle-ключ — обе ветки не сработают разом)
#
# State: $STATE_DIR/*decompose*-${SESSION_ID}.jsonl (per-session dedup via throttle-lib)
# Output: jq hookSpecificOutput с additionalContext (gentle hint)

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

# Shared per-session throttle (single source — see throttle-lib.sh).
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
[ -f "$THROTTLE_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$THROTTLE_LIB"

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

# Guard 1: too short
PROMPT_LEN=${#USER_PROMPT}
[ "$PROMPT_LEN" -lt 100 ] && exit 0

# Guard 2: already mentioned decompose
# tr опускает регистр только у латиницы одинаково на обеих системах; кириллицу
# GNU tr (Linux) не трогает, а BSD tr (macOS) опускает — поэтому «Разбей» с заглавной
# ловится вторым написанием, а не приведением регистра.
USER_LOWER=$(to_lower "$USER_PROMPT")
case "$USER_LOWER" in
    *"/decompose"*|*"декомпоз"*|*"Декомпоз"*|*"разбей"*|*"Разбей"*|*"разбить"*|*"Разбить"*|*"раздроб"*|*"Раздроб"*) exit 0 ;;
    *"grilling"*|*"/грилинг"*|*"грилинг"*|*"Грилинг"*|*"грил "*) exit 0 ;;
    *"adversary"*|*"противник"*|*"Противник"*|*"хейтер"*|*"Хейтер"*|*"прожар"*|*"Прожар"*) exit 0 ;;
esac

# Guard 3: per-session dedup
THROTTLE_FILE=$(throttle_file "$STATE_DIR" decompose "$SESSION_ID")
throttle_seen "$THROTTLE_FILE" session && exit 0

# Guard 4: focus or stuck state — skip
STATE_FILE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(jq -r '.state.current // "idle"' "$STATE_FILE" 2>/dev/null)
    case "$CURRENT_STATE" in
        focus|stuck) exit 0 ;;
    esac
fi

# -----------------------------------------------------------------------
# Step-counting
# -----------------------------------------------------------------------
count_signals() {
    local prompt="$1"
    local total=0

    # Numbered list items: ^\s*\d+[.)]
    local n_num
    n_num=$(echo "$prompt" | awk '/^[[:space:]]*[0-9]+[.)]/ { c++ } END { print c+0 }')
    total=$((total + n_num))

    # Bullet items: ^\s*[-*]\s
    local n_bul
    n_bul=$(echo "$prompt" | awk '/^[[:space:]]*[-*][[:space:]]/ { c++ } END { print c+0 }')
    total=$((total + n_bul))

    # Russian connectors.
    # Регистр кириллицы здесь НЕ приводится через tr: BSD tr (macOS) знает многобайтные
    # символы и опускает «Затем» → «затем», GNU tr (Linux) работает побайтно и оставляет
    # заглавные как есть — при любой локали, включая C.UTF-8. Поэтому оба написания
    # перечислены явно: счёт получается одинаковым на обеих системах.
    # Перечисление обоих написаний («затем|Затем») покрывало только заглавную первую букву
    # и промахивалось на «ЗАТЕМ». Свёртка регистра делается по-настоящему — общей функцией.
    local ru_lower
    ru_lower=$(to_lower "$prompt")
    local n_ru=0
    for pat in "затем" "потом" "после этого" "далее" "сначала" "а ещё" "а еще"; do
        local c
        c=$(echo "$ru_lower" | grep -oE "$pat" | wc -l | tr -d ' ')
        n_ru=$((n_ru + c))
    done
    total=$((total + n_ru))

    # English connectors
    local n_en=0
    for pat in " then " " after that " " next," " next " " finally " " afterwards "; do
        local c
        c=$(echo " $ru_lower " | grep -o "$pat" | wc -l | tr -d ' ')
        n_en=$((n_en + c))
    done
    total=$((total + n_en))

    echo "$total"
}

# -----------------------------------------------------------------------
# Decision-counting (→/grilling): маркеры открытых решений и дизайна.
# Отдельная группа от шагов — чтобы router не путал «многошаговое» с
# «многорешенческим». Голое « или » намеренно НЕ считаем: слишком частотно,
# даёт ложные срабатывания. Регистр кириллицы наследует ограничение файла
# (to_lower надёжен на BSD; на GNU заглавная первая буква маркера промахнётся —
# но эти маркеры почти всегда в середине фразы со строчной).
# -----------------------------------------------------------------------
count_decision_signals() {
    local prompt lower total=0 c
    lower=$(to_lower "$1")
    for pat in "либо " "как лучше" "какой вариант" "какой подход" "не уверен" \
               "что выбрать" "выбрать между" "стоит ли" "а может" \
               "продумай" "проработай" "обмозгуй" "спроектир" "запроектир" \
               "архитектур" "как реализовать" "как организовать" "как устроить" "как лучше сделать"; do
        c=$(printf '%s' "$lower" | grep -oF "$pat" | grep -c . || true)
        total=$((total + c))
    done
    echo "$total"
}

STEP_COUNT=$(count_signals "$USER_PROMPT")
DECISION_COUNT=$(count_decision_signals "$USER_PROMPT")

THRESHOLD="${DECOMPOSE_THRESHOLD:-4}"
DECISION_THRESHOLD="${GRILL_THRESHOLD:-2}"

# Ветвление — максимум одна подсказка. Решения в приоритете, когда их ≥порога
# И строго больше шагов: открытые решения разрешают ДО плана.
if [ "$DECISION_COUNT" -ge "$DECISION_THRESHOLD" ] && [ "$DECISION_COUNT" -gt "$STEP_COUNT" ]; then
    ROUTE=grill
elif [ "$STEP_COUNT" -ge "$THRESHOLD" ]; then
    ROUTE=decompose
else
    exit 0
fi

# -----------------------------------------------------------------------
# Fire: общий throttle-ключ — вторая ветка в этой сессии уже не сработает.
# -----------------------------------------------------------------------
throttle_mark "$THROTTLE_FILE" session

if [ "$ROUTE" = grill ]; then
    MESSAGE="🧠 Открытые решения ($DECISION_COUNT сигналов, порог $DECISION_THRESHOLD; шагов $STEP_COUNT) — рекомендую /grilling.

Задача пахнет неразрешёнными решениями, а не готовым списком шагов. /grilling обойдёт дерево решений раундами (каждый вопрос с рекомендованным ответом), вытащит молчаливые допущения и доведёт до общего понимания — ДО плана и кода.

Если решения на деле уже улажены — проигнорируй. Готовый артефакт критиковать — это /хейтер, не /grilling."
else
    MESSAGE="🧭 Multi-step detected ($STEP_COUNT сигналов шагов, порог $THRESHOLD) — рекомендую /decompose.

Правило (rules/CLAUDE.md § Decompose-first):
- 4-7 шагов: показать план, можно начать сразу
- 8+ шагов: показать план, дождаться подтверждения
- Scope не расширять без явного решения

Если задача действительно простая (например, список-перечисление не равен списку шагов) — проигнорируй. Если декомпозиция нужна — сначала /decompose, потом execution."
fi

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
