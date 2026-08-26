#!/usr/bin/env bash
# user-correction-guard.sh — PreToolUse: pause when user just corrected me, before I do another tool action.
#
# Failure mode from a document-handling session: собеседник сказал «этот пункт никто
# не просит»; через несколько сообщений я писал документ, в котором пункт снова стоял
# как основной. Correction в transcript есть, но retrieval цепочка не превратила её
# в pre-action check. Этот хук — explicit gate: после correction следующее tool action
# требует подтверждения reformulation'а.
#
# Detection: last user message contains correction tokens.
#   - «не так», «не туда», «не то»
#   - «опять», «снова», «ты только что»
#   - «я говорил/говорила», «я сказал/сказала»
#   - «забудь», «не надо», «отмена»
#   - «не понял меня»
#   - «wrong», «that's not what I meant», «again»
#
# After detection: emit permissionDecision:"ask" with a reminder to reformulate
# user's actual intent before proceeding (Пункт 0).
#
# Throttle: one ask per (session, last_user_message_hash). New correction →
# new ask. Same correction message → no spam.

set -uo pipefail

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


STATE_DIR="${STATE_DIR:-${CORRECTION_STATE_DIR:-$HOME/.claude/hooks/state}}"

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

[ -z "$TRANSCRIPT_PATH" ] && exit 0
[ -f "$TRANSCRIPT_PATH" ] || exit 0

# --- Extract last user text message ---
# Pick last entry with type=user and a text content block (skip tool_result entries).
LAST_USER_TEXT=$(jq -r '
    select(.type == "user")
    | .message.content // []
    | map(select(.type == "text") | .text)
    | .[]?
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)

[ -z "$LAST_USER_TEXT" ] && exit 0

# --- Match correction tokens ---
# Регистр сворачивается через jq, а не через `tr '[:upper:]' '[:lower:]'`.
# Причина: BSD tr (macOS) читает многобайтовые символы и опускает «Подожди» → «подожди»,
# GNU tr (Linux) работает строго по байтам и кириллицу не трогает НИКОГДА — даже при
# LC_ALL=C.UTF-8 (проверено: `printf 'Подожди' | LC_ALL=C.UTF-8 tr '[:upper:]' '[:lower:]'`
# на debian возвращает «Подожди»). То есть это разница реализаций, а не настройка машины,
# и лечится только отказом от tr. jq здесь уже обязательная зависимость и работает с
# кодовыми точками независимо от локали: 1040..1071 = А-Я → +32 = а-я, 1025 = Ё → 1105 = ё.
# Приём (арифметика по кодовым точкам в jq) переехал в portable-lib как единственная копия:
# он же нужен ещё восьми хукам, а восемь копий разойдутся при первой правке.
USER_LOWER=$(to_lower "$LAST_USER_TEXT")
[ -z "$USER_LOWER" ] && USER_LOWER="$LAST_USER_TEXT"

# Словарь выведен из НАСТОЯЩИХ поправок, а не придуман (v1.13.3).
#
# Как измерялся прежний. За 214 сессий он дал 9 срабатываний, и большинство из них —
# не поправки («выведу деньги на холодный кошелёк», «оператор может передвинуть в
# CRM», «дополню, если ты пишешь перевод цифр»). На шести реальных поправках одной
# сессии — «хер пойми», «нихрена не понял», «не запомнить стоит, а починить», «3 раза
# делал одно и то же», «подожди, проблема глубже», «т.е. ты говоришь давай ничего не
# делать» — он не сработал НИ РАЗУ. При этом на собственных выдуманных фразах
# срабатывал исправно.
#
# Последствие цепочкой: пустой `correction-fired` → второму продюсеру контура
# опровержения (`dis_harvest_corrections`) нечего собирать → база структурно не может
# сказать «нет» → `contradicted_count` = 0 во всех 265 знаниях. Ноль был фактом об
# отсутствии канала, а не о правоте знания.
#
# Что различает поправку на самом деле — не отдельные слова, а несколько структур.
# Ниже они, каждая с примером из реальных данных:
#
#   1. Обсценная лексика — в этом диалоге почти безошибочный признак фрустрации
#      («хер пойми», «нихрена не понял», «а вот блядь и нет»).
#   2. Контрастная конструкция «не X, а Y» («не запомнить стоит, а починить»).
#   3. Императив остановки («подожди», «стоп», «погоди»).
#   4. Отрицание понимания («не понял», «непонятно», «не ясно»).
#   5. Указание на повтор («опять», «снова», «N раз одно и то же»).
#   6. Прежний словарь целиком — он давал мало, но не ноль.
#
# Ограничение названо прямо: любой лексический подход будет промахиваться, потому что
# поправка — отношение между моим утверждением и следующей репликой, а не набор слов.
# Это первое приближение с измеренной базой, а не решение.
#
# Место «одно слово» в конструкции «не X, а Y» записано как [^[:space:],]+, а не [а-яё]+.
# Причина: диапазон в скобках зависит от локали. В UTF-8 локали (macOS) [а-яё] — набор
# СИМВОЛОВ и `grep -oE '[а-яё]+'` на слове «запомнить» даёт «запомнить» целиком; в локали
# C (типичный контейнер, GNU grep) те же скобки читаются как набор БАЙТОВ, «т» = d1 82 в
# него не попадает, и то же выражение обрывается на «запомни». Отрицающий класс из одних
# ASCII-байтов ведёт себя одинаково в обеих локалях: многобайтовые последовательности
# просто не входят в перечисленное и проходят целиком.
CORRECTION_REGEX='не[[:space:]]+так|не[[:space:]]+туда|не[[:space:]]+то[[:space:]]|не[[:space:]]+то$|опять|снова|ты[[:space:]]+только[[:space:]]+что|я[[:space:]]+говорил|я[[:space:]]+сказал|я[[:space:]]+же[[:space:]]+говорил|забудь|не[[:space:]]+надо[[:space:]]+было|отмена|не[[:space:]]+понял|непонятно|не[[:space:]]+ясно|day[[:space:]]+wasted|день[[:space:]]+потрачен|стоп[[:space:]]|остановись|подожди|погоди|wrong|that.?s[[:space:]]+not[[:space:]]+what|хер|нихрена|ни[[:space:]]*хрена|хрень|бля|нахер|нафиг|не[[:space:]]+[^[:space:],]+[[:space:]]+стоит,?[[:space:]]*а|не[[:space:]]+[^[:space:],]+,[[:space:]]*а[[:space:]]|[0-9]+[[:space:]]+раз[а]?[[:space:]]+.*одно[[:space:]]+и[[:space:]]+то[[:space:]]+же|одно[[:space:]]+и[[:space:]]+то[[:space:]]+же'

# --- Сигнал A: контекст, а не словарь (v1.13.4) ---
#
# Формулировка собеседника: «поправка или нет должно проверяться не по словарю, а по
# контексту — проверка предыдущих сообщений перед тем, как ты что-то правишь».
#
# Ключевое в ней — не «классифицируй точнее», а «не правь вслепую». Поэтому здесь нет
# попытки навесить ярлык: если правится файл, который уже правился, и между двумя
# правками была реплика человека, показывается САМА реплика, а причину называет агент.
# Классификация, в которой словарь ошибался в обе стороны, из задачи исчезает.
#
# Измерено на живом транскрипте (2274 записи, 22 реплики, 103 правки): повторных
# правок после реплики — 8. Как классификатор это слабо (половина — рутинные правки
# CHANGELOG и architecture в релизном цикле). Как повод посмотреть назад — ровно то,
# что нужно: восемь мест, где стоило спросить себя, чья это правка.
#
# Сигнал лексический (ниже) остаётся вторым: он ловит поправки, не приводящие к
# повторной правке файла. Его словарь выведен из реальных реплик в v1.13.3.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
CONTEXT_HIT=0
if [ -n "$FILE_PATH" ]; then
    # Одним проходом: была ли правка ЭТОГО файла, и была ли после неё человеческая
    # реплика. Человеческая = type user с текстовым блоком и без tool_result.
    CONTEXT_HIT=$(jq -rs --arg f "$FILE_PATH" '
        [ .[]
          | if .type == "user" then
                ( (.message.content // []) as $c
                  | if ($c | type) == "string" then (if ($c | length) > 0 then "H" else empty end)
                    elif ($c | type) == "array" then
                      ( if ([$c[] | select(.type == "tool_result")] | length) > 0 then empty
                        elif ([$c[] | select(.type == "text") | select(.text // "" | length > 0)] | length) > 0 then "H"
                        else empty end )
                    else empty end )
            elif .type == "assistant" then
                ( [ (.message.content // [])[]
                    | select(.type == "tool_use")
                    | select(.name == "Edit" or .name == "Write" or .name == "MultiEdit")
                    | select((.input.file_path // "") == $f) ] | if length > 0 then "E" else empty end )
            else empty end ]
        | join("")
        # Есть ли образец «правка этого файла, затем человеческая реплика»?
        | if test("EH") then 1 else 0 end
    ' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
    CONTEXT_HIT=${CONTEXT_HIT:-0}
fi

LEXICAL_HIT=0
grep -qE -- "$CORRECTION_REGEX" <<< "$USER_LOWER" && LEXICAL_HIT=1

# Ни контекста, ни слов — молчим.
[ "$CONTEXT_HIT" = "1" ] || [ "$LEXICAL_HIT" = "1" ] || exit 0

# --- Throttle by message hash ---
hash_value() {
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$1" | md5
    else
        printf '%s' "$1" | cksum | awk '{print $1}'
    fi
}

MSG_HASH=$(hash_value "$LAST_USER_TEXT")
THROTTLE_FILE="$STATE_DIR/correction-fired-${SESSION_ID}.jsonl"
if [ -f "$THROTTLE_FILE" ] && grep -Fq "\"hash\":\"$MSG_HASH\"" "$THROTTLE_FILE" 2>/dev/null; then
    exit 0
fi
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SNIPPET=$(printf '%s' "$LAST_USER_TEXT" | head -c 160 | tr '\n' ' ' | sed 's/"/\\"/g')
printf '{"date":"%s","hash":"%s","snippet":"%s"}\n' \
    "$NOW" "$MSG_HASH" "$SNIPPET" >> "$THROTTLE_FILE"

# --- Emit permissionDecision:ask ---
# Формулировка зависит от того, что сработало. Контекстный сигнал ничего не
# утверждает про намерение собеседника — он лишь показывает, что между двумя
# правками одного файла была реплика, и требует назвать причину. Лексический
# говорит прямее, но он вторичен и заведомо промахивается на иронии.
if [ "$CONTEXT_HIT" = "1" ]; then
    REASON=$(printf '🔁 Ты правишь файл, который уже правил, и между правками была реплика собеседника:\n\n  «%s»\n\nНазови причину прежде чем продолжить:\n  · правка от его слов → это поправка. Переформулируй ЧТО он сказал (не интерпретацию), зафиксируй исход знания.\n  · правка от твоего плана → так и скажи, продолжай.\n\nСмысл проверки не в ярлыке, а в том, чтобы не править вслепую: словарь поправок ошибался в обе стороны, положение реплики в диалоге — нет.' \
        "$SNIPPET")
else
    REASON=$(printf '🔁 В последней реплике собеседника есть признаки поправки:\n\n  «%s»\n\nПрежде чем продолжить — Пункт 0:\n1. Переформулируй ЧТО он сказал, а не свою интерпретацию.\n2. Какая потребность стоит за поправкой?\n3. Подтверди понимание прежде чем действовать.\n\nСигнал лексический и заведомо неточный: иронию он не ловит. Если это не поправка — игнорируй.' \
        "$SNIPPET")
fi

jq -n --arg ctx "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $ctx
    }
}'

exit 0
