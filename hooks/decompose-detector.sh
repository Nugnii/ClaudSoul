#!/usr/bin/env bash
# decompose-detector.sh — multi-step detection в UserPromptSubmit.
# en: UserPromptSubmit: multi-step detection — suggests /decompose when the request implies four or more steps.
# Если пользователь задал задачу на ≥4 шага — silent inject «🧭 Задача многошаговая,
# рекомендую /decompose». Агент решает применять или нет.
#
# Signals (каждый = +1 шаг):
#   1. Нумерованные строки: ^\s*\d+[\.\)]
#   2. Буллеты: ^\s*[-*]\s
#   3. Русские коннекторы: затем/потом/после\s+этого/далее/сначала/а\s+ещё
#   4. Английские коннекторы: then|after that|next|finally|afterwards
#
# Порог: ≥4 distinct signals → inject. Гвардов:
#   - prompt < 100 chars: skip (trivial)
#   - «/decompose», «декомпоз», «разбей» уже упомянуты: skip
#   - state = focus или stuck: skip (неудачное окно)
#   - уже inject'или в этой сессии: skip
#
# State: $STATE_DIR/decompose-fired-${SESSION_ID}.jsonl (per-session dedup via throttle-lib)
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
esac

# Guard 3: per-session dedup
THROTTLE_FILE=$(throttle_file "$STATE_DIR" decompose "$SESSION_ID")
throttle_seen "$THROTTLE_FILE" session && exit 0

# Guard 4: focus or stuck state — skip
STATE_FILE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(jq -r '.state_axis // "idle"' "$STATE_FILE" 2>/dev/null)
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

SIGNAL_COUNT=$(count_signals "$USER_PROMPT")

# Threshold
THRESHOLD="${DECOMPOSE_THRESHOLD:-4}"
if [ "$SIGNAL_COUNT" -lt "$THRESHOLD" ]; then
    exit 0
fi

# -----------------------------------------------------------------------
# Fire: write flag + emit hint
# -----------------------------------------------------------------------
throttle_mark "$THROTTLE_FILE" session

MESSAGE="🧭 Multi-step detected ($SIGNAL_COUNT сигналов шагов, порог $THRESHOLD) — рекомендую /decompose.

Правило (rules/CLAUDE.md § Decompose-first):
- 4-7 шагов: показать план, можно начать сразу
- 8+ шагов: показать план, дождаться подтверждения
- Scope не расширять без явного решения

Если задача действительно простая (например, список-перечисление не равен списку шагов) — проигнорируй. Если декомпозиция нужна — сначала /decompose, потом execution."

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
