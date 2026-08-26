#!/usr/bin/env bash
# reformulation-tracker.sh — UserPromptSubmit: каскадная верификация предсказаний (FORWARD/PROPOSAL/BACKWARD), логирует outcome и напоминает фиксировать gap.
# en: UserPromptSubmit: cascading verification of predictions (FORWARD/PROPOSAL/BACKWARD), logs the outcome and prompts to record the gap.
#
# Cascading prediction-verification tracker. Detects three trigger types
# at every user turn — each is a verification point for the agent's
# hypothesis about user intent:
#
#   1. FORWARD  — agent reformulated in prior response ("правильно ли понимаю")
#                 => user reply verifies that explicit hypothesis
#
#   2. PROPOSAL — agent made a suggestion in prior response
#                 ("предлагаю", "рекомендую", "давай сделаем")
#                 => user reply validates or rejects the suggestion
#
#   3. BACKWARD — user current message contains correction markers
#                 ("не так", "не совсем", "я имел в виду")
#                 => agent implicit hypothesis was wrong — record it
#
# Cascading: fires on every turn where a trigger matches, not only first.
# Each round of clarification is a fresh prediction cycle.

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
HASH_LIB="${HASH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash-lib.sh}"
[ -f "$HASH_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$HASH_LIB"
INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook-input-lib.sh}"
[ -f "$INPUT_LIB" ] && source "$INPUT_LIB"
mkdir -p "$STATE_DIR"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
USER_PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // .prompt // empty')

# Приведение регистра — через общую библиотеку: GNU tr кириллицу не сворачивает ни в какой
# локали, поэтому на Linux все шаблоны ниже молча не совпадали (CI, 5 падений из 11).
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
elif [ -f "$HOME/.claude/hooks/portable-lib.sh" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.claude/hooks/portable-lib.sh"
else
    to_lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }
    reverse_lines() { tac "${1:-}" 2>/dev/null || tail -r "${1:-}" 2>/dev/null || true; }
fi

USER_LOWER=$(to_lower "$USER_PROMPT")

# -----------------------------------------------------------------------
# Scope guard: системный/инструментальный turn — не речь собеседника. Маркеры
# коррекции в теле tool_result — не коррекция юзера (pattern-guard-scope-
# blindness). Все три триггера (BACKWARD/FORWARD/PROPOSAL) предполагают настоящий
# ответ юзера — на системном turn его нет. Единый список тегов — hook-input-lib.sh.
# -----------------------------------------------------------------------
if command -v is_non_user_turn >/dev/null 2>&1 && is_non_user_turn "$USER_PROMPT"; then
    exit 0
fi

# -----------------------------------------------------------------------
# Trigger 3 (BACKWARD): correction markers in current user message
# -----------------------------------------------------------------------
CORRECTION_PATTERNS=(
    "не так"
    "не совсем"
    "не то"
    "не правильно"
    "неправильно"
    "не верно"
    "неверно"
    "я имел в виду"
    "я имела в виду"
    "я хотел чтобы"
    "я хотела чтобы"
    "я хотел сказать"
    "уточню"
    "поправлю"
    "должно быть иначе"
    "не это"
    "not quite"
    "that is not"
    "i meant"
    "actually"
)

# Граница слова обязательна. Без неё «не то» совпадало внутри «не только», и реплика
# «проверять нужно НЕ ТОЛЬКО причины ошибок» — согласие, развивающее мысль — приходила как
# «Пользователь КОРРЕКТИРУЕТ». Так же ложно совпадали «не так» ⊂ «не такой», «не это» ⊂ «не этой».
#
# Но граница НЕ через класс символов. Первая версия ставила `[^а-яёa-zA-Z]`, и я проверил её
# в bash и zsh на macOS — обе зелёные. Не хватало третьей оси: GNU grep в локали `C.UTF-8`
# кириллический диапазон в скобках просто ОТВЕРГАЕТ — «grep: Invalid collation character»,
# совпадения нет, детектор молчит. Замер в контейнере: локаль C — совпало, `C.UTF-8` — ошибка
# и тишина, `en_US.UTF-8` — совпало. Прогон CI идёт ровно в `C.UTF-8`.
#
# Поэтому граница делается без регулярных выражений вовсе: знаки препинания заменяются
# пробелами (только ASCII-символы, кириллица не трогается), пробелы схлопываются, строка
# обрамляется пробелами — и шаблон ищется как точная подстрока `" не то "`. От локали такой
# поиск не зависит ни на одной системе.
USER_PADDED=$(pad_words "$USER_LOWER")

BACKWARD_MATCH=""
for p in "${CORRECTION_PATTERNS[@]}"; do
    if grep -qF " $p " <<< "$USER_PADDED"; then
        BACKWARD_MATCH="$p"
        break
    fi
done

# -----------------------------------------------------------------------
# Last assistant message from transcript (for FORWARD and PROPOSAL)
# -----------------------------------------------------------------------
LAST_ASSISTANT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # `tail -r | while ... break` triggers SIGPIPE on tail when the while loop
    # exits early. С `set -eo pipefail` это распространяется как exit 141 и
    # тихо убивает хук. Отключаем pipefail только для этого pipeline.
    set +o pipefail
    LAST_ASSISTANT=$(reverse_lines "$TRANSCRIPT_PATH" | while IFS= read -r line; do
        role=$(echo "$line" | jq -r '.message.role // .role // empty' 2>/dev/null || echo "")
        if [ "$role" = "assistant" ]; then
            echo "$line" | jq -r '
                (.message.content // .content // []) |
                if type == "array" then
                    map(select(.type == "text") | .text) | join("\n")
                elif type == "string" then .
                else "" end
            ' 2>/dev/null
            break
        fi
    done)
    set -o pipefail
fi

ASSISTANT_LOWER=$(to_lower "$LAST_ASSISTANT")
# Нормализованная копия — та же граница слова, что у BACKWARD: «предлагаю» не должно
# совпадать внутри «предлагают» (третье лицо это не предложение агента).
ASSISTANT_PADDED=$(pad_words "$ASSISTANT_LOWER")

# Trigger 1 (FORWARD): reformulation in agent prior turn
REFORMULATION_PATTERNS=(
    "правильно ли я понимаю"
    "верно ли я понимаю"
    "если я правильно понял"
    "если я верно понял"
    "переформулирую"
    "то есть нужно"
    "то есть задача"
    "ты хочешь чтобы"
    "вы хотите чтобы"
    "правильно понимаю"
    "верно понимаю"
    "do i understand correctly"
    "if i understand correctly"
    "so you want"
    "let me rephrase"
)

FORWARD_MATCH=""
if [ -n "$ASSISTANT_LOWER" ]; then
    for p in "${REFORMULATION_PATTERNS[@]}"; do
        if grep -qF " $p " <<< "$ASSISTANT_PADDED"; then
            FORWARD_MATCH="$p"
            break
        fi
    done
fi

# Trigger 2 (PROPOSAL): suggestion in agent prior turn
PROPOSAL_PATTERNS=(
    "предлагаю"
    "рекомендую"
    "давай сделаем"
    "давайте сделаем"
    "лучше сделать"
    "стоит выбрать"
    "мой выбор"
    "рекомендация:"
    "предложение:"
    "i suggest"
    "i recommend"
    "my recommendation"
)

PROPOSAL_MATCH=""
if [ -n "$ASSISTANT_LOWER" ] && [ -z "$FORWARD_MATCH" ]; then
    for p in "${PROPOSAL_PATTERNS[@]}"; do
        if grep -qF " $p " <<< "$ASSISTANT_PADDED"; then
            PROPOSAL_MATCH="$p"
            break
        fi
    done
fi

# -----------------------------------------------------------------------
# Priority: BACKWARD > FORWARD > PROPOSAL
# -----------------------------------------------------------------------
TRIGGER=""
MARKER=""
NOTE=""

if [ -n "$BACKWARD_MATCH" ]; then
    TRIGGER="BACKWARD"
    MARKER="$BACKWARD_MATCH"
    NOTE="Пользователь КОРРЕКТИРУЕТ (маркер: \"$MARKER\"). Твоя предыдущая гипотеза о его намерении была неточной — это прямая обратная связь. Зафиксируй accuracy = miss или adjacent с уроком: что именно ты предположил vs что оказалось."
elif [ -n "$FORWARD_MATCH" ]; then
    TRIGGER="FORWARD"
    MARKER="$FORWARD_MATCH"
    NOTE="Ты давал переформулировку (маркер: \"$MARKER\") — это была открытая гипотеза. Сообщение пользователя сейчас = её верификация. Зафиксируй accuracy (exact / adjacent / miss) с уроком."
elif [ -n "$PROPOSAL_MATCH" ]; then
    TRIGGER="PROPOSAL"
    MARKER="$PROPOSAL_MATCH"
    NOTE="Ты давал предложение/рекомендацию (маркер: \"$MARKER\") — это гипотеза о лучшем пути. Реакция пользователя = её валидация. Принял = exact. Выбрал другое / скорректировал = adjacent или miss, зафиксируй что именно сработало иначе."
else
    exit 0
fi

# -----------------------------------------------------------------------
# Per-turn dedup: (assistant content + prompt prefix) hash. Allows new
# prompts in the same session to fire again on new assistant turns.
# -----------------------------------------------------------------------
TURN_KEY=$(hash_value "$(printf '%s:::%s' "$LAST_ASSISTANT" "${USER_PROMPT:0:200}")")

LAST_FIRE_FILE="$STATE_DIR/reformulation_last_fire_${SESSION_ID}"
if [ -f "$LAST_FIRE_FILE" ]; then
    PREV_KEY=$(cat "$LAST_FIRE_FILE" 2>/dev/null || echo "")
    if [ "$PREV_KEY" = "$TURN_KEY" ]; then
        exit 0
    fi
fi
echo "$TURN_KEY" > "$LAST_FIRE_FILE"

# -----------------------------------------------------------------------
# H11 measurement: append cascading event for confirmed gaps (BACKWARD).
# FORWARD/PROPOSAL are pending verifications, not confirmed gaps —
# we count only BACKWARD here. Aggregated by session-collector into
# intrusiveness-history.jsonl as cascading.backward_count.
# -----------------------------------------------------------------------
if [ "$TRIGGER" = "BACKWARD" ] && [ -n "$SESSION_ID" ]; then
    CASCADE_LOG="$STATE_DIR/cascading-events-${SESSION_ID}.jsonl"
    EVENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    printf '{"ts":"%s","trigger":"BACKWARD","marker":"%s"}\n' "$EVENT_TS" "${MARKER//\"/\\\"}" >> "$CASCADE_LOG" 2>/dev/null || true
fi

# -----------------------------------------------------------------------
# L6 gate: soften the formalization demand when engagement is idle/casual.
# Root cause (case-2026-06-02-over-formalization-casual-chat): persistence
# hooks pushed formalization (write SESSION.md) unconditionally, overriding
# the idle-state restraint that lived only as a fragile text-rule. Gate the
# SESSION.md demand against intrusiveness state — the same L6 4D-gate the
# system applies to gentle/proactive, now applied to the learning hook itself.
#
# Scope: soften only FORWARD/PROPOSAL in idle (speculative verifications).
# BACKWARD is a confirmed gap — always capture, never soften.
# If state file is absent (reasons == "unknown") — keep prior hard behavior.
# -----------------------------------------------------------------------
ITR_STATE="focus"
ITR_REASONS="unknown"
# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
ITR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/intrusiveness-state-lib.sh"
[ -f "$ITR_LIB" ] || ITR_LIB="$HOME/.claude/hooks/intrusiveness-state-lib.sh"
if [ -n "$SESSION_ID" ] && [ -f "$ITR_LIB" ]; then
    # shellcheck disable=SC1090
    source "$ITR_LIB" 2>/dev/null || true
    if command -v itr_get_state >/dev/null 2>&1; then
        ITR_TRIPLE=$(itr_get_state "$SESSION_ID" 2>/dev/null || echo "focus|1|unknown")
        ITR_STATE="${ITR_TRIPLE%%|*}"
        ITR_REASONS="${ITR_TRIPLE##*|}"
    fi
fi

if [ "$ITR_STATE" = "idle" ] && [ "$ITR_REASONS" != "unknown" ] && [ "$TRIGGER" != "BACKWARD" ]; then
    LOG_DIRECTIVE="Движок в state=idle (лёгкая, нецелевая вовлечённость). НЕ продавливай формализацию:
- Если обмен keep-worthy — можешь зафиксировать Pn в SESSION.md.
- Если просто болтаете и активного проекта в фокусе нет — фиксировать НЕ обязательно, не выходи из лёгкого режима ради церемонии.
- Не предлагай «войти в проект» только чтобы было куда писать лог."
else
    LOG_DIRECTIVE="ЗАФИКСИРУЙ accuracy в SESSION.md, секция \"### Predictions\" текущей записи, ДО основного ответа:

| # | Predicted | Actual | Accuracy | Lesson |
|---|-----------|--------|----------|--------|
| Pn | [что предположил] | [что оказалось] | exact / adjacent / miss | [один actionable урок] |

Правила:
- exact = в точку
- adjacent = рядом, та же область
- miss = мимо (обязательно извлечь урок)
- Каскадность: продолжай нумерацию (P1, P2, ...). Каждое уточнение/исправление = новая точка данных, не переписывание предыдущей.
- Через 5 сообщений ты уже не восстановишь точно что предполагал — фиксируй сейчас."
fi

# -----------------------------------------------------------------------
# Emit additionalContext
# -----------------------------------------------------------------------
MESSAGE="PREDICTION -> VERIFICATION [$TRIGGER]

$NOTE

$LOG_DIRECTIVE"

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
