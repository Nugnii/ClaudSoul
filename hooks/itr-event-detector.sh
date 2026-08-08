#!/usr/bin/env bash
# itr-event-detector.sh — UserPromptSubmit hook
#
# Detects gentle-suggestion events from the assistant's prior turn and
# classifies the user's response polarity (accepted / ignored), then
# logs the event via itr_log_event so that L6 budget metrics
# (gentle_accepted, gentle_ignored) actually accumulate during real
# work — not only during smoke tests.
#
# Single-pass design: no persistent "pending" file. Each UserPromptSubmit
# inspects the immediately-prior assistant message and the current prompt
# together; if a gentle marker is present in the assistant's last paragraph
# AND the prompt has a clear polarity signal (or the absence of one is itself
# signal), we record once and dedup on (assistant + prompt-prefix) hash.
#
# Why this hook exists:
#   itr_log_event for type=gentle/proactive is currently called only by the
#   v132 smoke test. Real sessions accumulate zero gentle events, which means
#   gentle_max budget calibration (the v1.4.0 milestone) has no input data.
#   Pattern-detection in the transcript replaces unreliable agent discipline.
#
# Conservative bias: prefer false negatives over false positives. A missed
# gentle is one fewer data point; a wrongly-attributed gentle pollutes the
# acceptance-rate signal that drives budget tuning.

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.claude/hooks/intrusiveness-state-lib.sh"

[ -f "$LIB" ] || exit 0
# shellcheck source=/dev/null
source "$LIB"

# Shared hash helper (single source — see hash-lib.sh).
HASH_LIB="${HASH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash-lib.sh}"
[ -f "$HASH_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$HASH_LIB"

# ADR-010 Ф1: авторизация как состояние задачи (writer + reader здесь).
AUTH_LIB="${AUTH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/authorization-lib.sh}"
[ -f "$AUTH_LIB" ] || AUTH_LIB="$HOME/.claude/hooks/authorization-lib.sh"
# shellcheck source=/dev/null
[ -f "$AUTH_LIB" ] && source "$AUTH_LIB"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
USER_PROMPT=$(echo "$INPUT" | jq -r '(.prompt // .user_prompt // "") | tostring')

[ -z "$SESSION_ID" ] && exit 0
[ -z "$TRANSCRIPT_PATH" ] && exit 0
[ ! -f "$TRANSCRIPT_PATH" ] && exit 0
[ -z "$USER_PROMPT" ] && exit 0

# Scope guard: системный/инструментальный turn — не реплика юзера на предложение.
# Маркеры коррекции/отказа в теле tool_result не должны классифицироваться как
# исход (pattern-guard-scope-blindness). Единый список тегов — hook-input-lib.sh.
INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook-input-lib.sh}"
[ -f "$INPUT_LIB" ] && source "$INPUT_LIB"
if command -v is_non_user_turn >/dev/null 2>&1 && is_non_user_turn "$USER_PROMPT"; then exit 0; fi

mkdir -p "$STATE_DIR"

# ADR-010 Ф1: состояние авторизации читается ДО обновления — проактивность
# ПРОШЛОГО хода оценивается по состоянию, действовавшему в момент того хода
# (его записала предыдущая реальная реплика). Текущая реплика пишет новое
# состояние: поручение/продолжение взводит, всё прочее гасит. Синтетические
# user-строки сюда не доходят по построению (UserPromptSubmit + guard выше).
AUTH_WAS_ACTIVE=0
AUTH_ACTIVE_MARKER=""
AUTH_STATE_EXISTED=0
# AUTH_ONESHOT_ONLY=1 — измерительная ручка A/B (ADR-010 Ф3): состояние не читается
# и не пишется, работает только одношаговая fallback-проверка = семантика до v1.22.0.
# Боевой путь ручку не выставляет никогда.
if [ "${AUTH_ONESHOT_ONLY:-0}" != "1" ] && command -v auth_is_active >/dev/null 2>&1; then
    # Существование файла фиксируется ДО записи: писатель создаёт файл на этой же
    # реплике, и проверка «файла нет» после записи была бы недостижима (поймано
    # тестом S3 до коммита).
    [ -f "$(auth_state_path "$SESSION_ID")" ] && AUTH_STATE_EXISTED=1
    if AUTH_ACTIVE_MARKER=$(auth_is_active "$SESSION_ID"); then
        AUTH_WAS_ACTIVE=1
    fi
    auth_update "$SESSION_ID" "$USER_PROMPT" || true
fi

# -----------------------------------------------------------------------
# Extract prior-turn context via a single jq pass:
#   - prior_user:     latest user-role message with text content (the
#                     prompt that triggered the current assistant turn)
#   - assistant_text: joined text of ALL assistant records after prior_user
#                     (the assistant's full response — text across multiple
#                     content blocks)
#   - assistant_tools: comma-joined, deduplicated tool names used
#
# Why walk the full logical turn, not just the newest record: in Claude
# Code transcripts a single assistant turn is split into multiple JSONL
# entries (text / tool_use interleaved with user tool_result). The newest
# entry might be a tool_use with empty text, which would cause the gentle
# detector to miss "запускаем?" text that appeared earlier in the same turn.
# -----------------------------------------------------------------------
CTX=$(jq -s '
    def role(x): x.message.role // x.role // "";
    def has_text_content(x):
        (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then
            ($c | map(select(.type == "text" and ((.text // "") | length > 0))) | length > 0)
        elif ($c | type) == "string" then ($c | length > 0)
        else false end;
    def get_text(x):
        (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then
            ($c | map(select(.type == "text") | .text) | join("\n"))
        elif ($c | type) == "string" then $c
        else "" end;
    def get_tools(x):
        (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then
            ($c | map(select(.type == "tool_use") | .name))
        else [] end;

    . as $items | (length) as $n |
    ([range(0; $n) | ($n - 1 - .)
      | select(role($items[.]) == "user" and has_text_content($items[.]))]
      | first) as $pu |
    if $pu == null then
        # No prior user message — still collect all assistant content so
        # gentle detection works even without a preceding user turn (test
        # fixtures, opening message, etc.). Proactive needs prior_user
        # and will not fire here.
        ([range(0; $n) | $items[.] | select(role(.) == "assistant")]) as $a |
        {
            prior_user: "",
            assistant_text: ($a | map(get_text(.)) | map(select(. != "")) | join("\n")),
            assistant_tools: ($a | map(get_tools(.)) | add // [] | unique | join(","))
        }
    else
        ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]) as $a |
        {
            prior_user: get_text($items[$pu]),
            assistant_text: ($a | map(get_text(.)) | map(select(. != "")) | join("\n")),
            assistant_tools: ($a | map(get_tools(.)) | add // [] | unique | join(","))
        }
    end
' "$TRANSCRIPT_PATH" 2>/dev/null)

LAST_ASSISTANT=$(printf '%s' "$CTX" | jq -r '.assistant_text // ""' 2>/dev/null)
LAST_ASSISTANT_TOOLS=$(printf '%s' "$CTX" | jq -r '.assistant_tools // ""' 2>/dev/null)
PRIOR_USER_PROMPT=$(printf '%s' "$CTX" | jq -r '.prior_user // ""' 2>/dev/null)

[ -z "$LAST_ASSISTANT" ] && [ -z "$LAST_ASSISTANT_TOOLS" ] && exit 0

# -----------------------------------------------------------------------
# Focus on the *last paragraph* of the assistant message. Gentle suggestions
# almost always sit at the end ("...запускаем?"). Mid-text question marks are
# usually rhetorical or pedagogical and produce false positives.
#
# Strategy: take everything after the final blank line; if no blank line,
# use the whole message but cap at last 400 chars.
# -----------------------------------------------------------------------
LAST_PARA=$(printf '%s' "$LAST_ASSISTANT" | awk 'BEGIN{RS=""; ORS="\n\n"} {p=$0} END{print p}')
if [ -z "$LAST_PARA" ]; then
    LAST_PARA="$LAST_ASSISTANT"
fi
# Cap to last 400 chars to keep matches localized.
LAST_PARA_LEN=${#LAST_PARA}
if [ "$LAST_PARA_LEN" -gt 400 ]; then
    LAST_PARA="${LAST_PARA:$((LAST_PARA_LEN - 400))}"
fi
# Свёртка регистра, не зависящая от реализации tr. ПРИЧИНА РАСХОЖДЕНИЯ:
# GNU coreutils tr (Linux) работает побайтово и многобайтовые символы не
# сворачивает — «Запускаем?» остаётся с заглавной «З» в любой локали, включая
# C.UTF-8. BSD tr (macOS) кириллицу сворачивает. Из-за этого на Linux ни один
# русский маркер не находился и события не порождались вовсе. grep -i заменой
# не служит: BSD grep многобайтовую кириллицу не сворачивает ни в какой локали.
# Поэтому ASCII отдаём tr, а кириллицу заменяем побуквенно: sed ищет одну и ту
# же последовательность байтов в обеих реализациях и при любой локали.
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

LAST_PARA_LOWER=$(to_lower "$LAST_PARA")

# -----------------------------------------------------------------------
# Gentle markers: interrogative suggestion phrases that explicitly invite
# the user to confirm an action. Conservative — every entry is a phrase
# that, in normal Russian/English usage, almost never appears outside a
# request-for-confirmation context.
#
# The match must co-occur with a question mark in the last paragraph,
# otherwise it's likely descriptive ("я могу запускать тесты — но не делаю").
# -----------------------------------------------------------------------
GENTLE_MARKERS=(
    # Russian — short confirmation asks
    "запускаем?"
    "запускать?"
    "запускаю?"
    "запустим?"
    "продолжаем?"
    "продолжать?"
    "продолжим?"
    "делаем?"
    "делать?"
    "сделаем?"
    "поехали?"
    "пойдёт?"
    "годится?"
    "ок?"
    "ok?"
    "согласен?"
    "согласна?"
    # Russian — explicit request for permission
    "хочешь чтобы я"
    "хотите чтобы я"
    "стоит ли мне"
    "мне это сделать"
    "не лучше ли"
    "может стоит"
    "предпочитаешь"
    "предпочитаете"
    "что выбираешь"
    "что выбираете"
    "какой вариант"
    # English
    "should i "
    "want me to"
    "do you want me to"
    "shall we"
    "shall i"
    "is that ok"
    "ok with you"
    "go ahead?"
    "proceed?"
    "ready to "
    "happy with"
    "which do you prefer"
)

GENTLE_MATCH=""
# Require '?' in the last paragraph — strong signal of an actual question.
if [ -n "$LAST_PARA" ] && printf '%s' "$LAST_PARA" | grep -qF '?'; then
    for marker in "${GENTLE_MARKERS[@]}"; do
        if printf '%s' "$LAST_PARA_LOWER" | grep -qF "$marker"; then
            GENTLE_MATCH="$marker"
            break
        fi
    done
fi

# -----------------------------------------------------------------------
# Determine event type:
#   gentle    — assistant ended with a confirmation question
#   proactive — assistant ran a destructive tool (Edit/Write/MultiEdit/
#               NotebookEdit) without explicit user request or continuation
#   none      — exit silently
#
# Gentle takes precedence: if the assistant both ran a tool AND asked a
# question, we treat it as gentle (asking permission post-hoc), avoiding
# double-counting on the same turn.
# -----------------------------------------------------------------------
EVENT_TYPE=""
EVENT_MARKER=""

if [ -n "$GENTLE_MATCH" ]; then
    EVENT_TYPE="gentle"
    EVENT_MARKER="$GENTLE_MATCH"
fi

if [ -z "$EVENT_TYPE" ] && [ -n "$LAST_ASSISTANT_TOOLS" ]; then
    # Destructive tools — file mutations. Read/Grep/Glob/ToolSearch are
    # zero-cost discovery and never count as proactive. Bash is excluded
    # here because its destructiveness depends on the command — bash-cost-
    # detector handles that signal separately and feeds silence_cost hints.
    DESTRUCTIVE_TOOL=""
    OLDIFS="$IFS"; IFS=','
    for t in $LAST_ASSISTANT_TOOLS; do
        case "$t" in
            Edit|Write|MultiEdit|NotebookEdit)
                DESTRUCTIVE_TOOL="$t"
                break
                ;;
        esac
    done
    IFS="$OLDIFS"

    # ADR-010 Ф1: решает состояние авторизации, действовавшее в момент хода,
    # а не маркер в одной предыдущей реплике (та часто — task-notification).
    # Библиотека недоступна → пропуск данных честнее ложной атрибуции
    # (консервативный уклон детектора; case-2026-06-20-hook-dependency-install-drift).
    if [ -n "$DESTRUCTIVE_TOOL" ] && command -v auth_is_active >/dev/null 2>&1; then
        if [ "$AUTH_WAS_ACTIVE" = "1" ]; then
            EVENT_TYPE="solicited"
            EVENT_MARKER="auth:${AUTH_ACTIVE_MARKER}:${DESTRUCTIVE_TOOL}"
        elif [ "$AUTH_STATE_EXISTED" = "0" ] && [ -n "$PRIOR_USER_PROMPT" ]; then
            # Состояние ещё не писалось (первый ход после установки) — прежняя
            # одношаговая проверка по маркерам из той же библиотеки (единый источник).
            if auth_classify "$PRIOR_USER_PROMPT" >/dev/null; then
                EVENT_TYPE="solicited"
                EVENT_MARKER="prior:${DESTRUCTIVE_TOOL}"
            else
                EVENT_TYPE="proactive"
                EVENT_MARKER="$DESTRUCTIVE_TOOL"
            fi
        else
            EVENT_TYPE="proactive"
            EVENT_MARKER="$DESTRUCTIVE_TOOL"
        fi
    fi
fi

# Neither gentle nor proactive → nothing to record.
[ -z "$EVENT_TYPE" ] && exit 0

# -----------------------------------------------------------------------
# Per-turn dedup: same (assistant + prompt-prefix) hash → already counted.
# Allows the agent to re-edit/re-fire on later turns without double-logging.
# -----------------------------------------------------------------------
# Ключ БЕЗ типа события: с ADR-010 тип зависит от состояния авторизации, и один
# и тот же ход мог записаться дважды под разными типами (поймано t28 до коммита).
# Один ход = одно событие; ходы различаются содержимым, не классификацией.
TURN_KEY=$(hash_value "$(printf '%s:::%s' "$LAST_ASSISTANT" "${USER_PROMPT:0:200}")")

LAST_FIRE_FILE="$STATE_DIR/itr_event_last_fire_${SESSION_ID}"
if [ -f "$LAST_FIRE_FILE" ]; then
    PREV_KEY=$(cat "$LAST_FIRE_FILE" 2>/dev/null || echo "")
    if [ "$PREV_KEY" = "$TURN_KEY" ]; then
        exit 0
    fi
fi

# -----------------------------------------------------------------------
# Classify the user's response polarity.
# -----------------------------------------------------------------------
USER_LOWER=$(to_lower "$USER_PROMPT")
# Нормализованная копия для поиска КОРОТКИХ маркеров: «да» — подстрока «дальше»,
# «данные», «два»; «нет» — «нету»; «не то» — «не только»; «no» — почти любого
# английского слова. Длинные фразы ищутся по-прежнему подстрокой.
USER_PADDED=$(pad_words "$USER_LOWER")
USER_TRIMMED=$(printf '%s' "$USER_LOWER" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
# Length of trimmed prompt — short replies (≤30 chars) are higher-signal.
USER_LEN=${#USER_TRIMMED}

# Acceptance markers — explicit positive replies.
ACCEPT_MARKERS=(
    "да"
    "ок"
    "ok"
    "окей"
    "да, "
    "да."
    "да!"
    "ок,"
    "ок."
    "ок!"
    "давай"
    "давайте"
    "поехали"
    "погнали"
    "запускай"
    "запускайте"
    "делай"
    "делайте"
    "продолжай"
    "продолжайте"
    "начнём"
    "начнем"
    "конечно"
    "хорошо"
    "пойдёт"
    "пойдет"
    "годится"
    "работаем"
    "приступай"
    "приступайте"
    "согласен"
    "согласна"
    "yes"
    "go"
    "go ahead"
    "sure"
    "do it"
    "proceed"
    "sounds good"
    "+1"
    "lgtm"
)

# Decline markers — explicit negative replies.
DECLINE_MARKERS=(
    "нет"
    "не надо"
    "не нужно"
    "не сейчас"
    "стоп"
    "стой"
    "пропусти"
    "отложим"
    "не делай"
    "не запускай"
    "no"
    "stop"
    "skip"
    "don't"
    "do not"
    "hold off"
    "wait"
)

# Correction (BACKWARD) markers — also count as ignored from gate POV.
CORRECTION_MARKERS=(
    "не так"
    "не совсем"
    "не то"
    "я имел в виду"
    "я имела в виду"
    "уточню"
    "поправлю"
    "not quite"
    "i meant"
    "actually"
)

is_match_short() {
    # Returns 0 if first word/phrase of trimmed user prompt matches needle.
    # Treats the prompt as "starting with" the marker — most acceptance/decline
    # replies are sent as the first thing, often the only thing.
    local needle="$1"
    case "$USER_TRIMMED" in
        "$needle"|"$needle "*|"$needle,"*|"$needle."*|"$needle!"*|"$needle?"*)
            return 0
            ;;
    esac
    return 1
}

OUTCOME=""
OUTCOME_MARKER=""

# solicited: исход — сам факт действующей авторизации, полярность ответа не про него.
if [ "$EVENT_TYPE" = "solicited" ]; then
    OUTCOME="authorized"
    OUTCOME_MARKER="standing_auth"
fi

# Short replies (≤30 chars) — high precision: must START with marker.
if [ -z "$OUTCOME" ] && [ "$USER_LEN" -le 30 ]; then
    for m in "${ACCEPT_MARKERS[@]}"; do
        if is_match_short "$m"; then
            OUTCOME="accepted"
            OUTCOME_MARKER="$m"
            break
        fi
    done
    if [ -z "$OUTCOME" ]; then
        for m in "${DECLINE_MARKERS[@]}"; do
            if is_match_short "$m"; then
                OUTCOME="ignored"
                OUTCOME_MARKER="$m"
                break
            fi
        done
    fi
fi

# Long replies — lower precision: scan anywhere for explicit decline / correction
# markers, otherwise treat as "moved on" → ignored. We DON'T look for accept
# markers in long replies because "да, но..." or "yes but actually..." are
# common patterns where the substantive reply changes direction.
if [ -z "$OUTCOME" ]; then
    for m in "${DECLINE_MARKERS[@]}"; do
        if printf '%s' "$USER_PADDED" | grep -qF " $m "; then
            OUTCOME="ignored"
            OUTCOME_MARKER="$m"
            break
        fi
    done
fi
if [ -z "$OUTCOME" ]; then
    for m in "${CORRECTION_MARKERS[@]}"; do
        if printf '%s' "$USER_PADDED" | grep -qF " $m "; then
            OUTCOME="ignored"
            OUTCOME_MARKER="correction:$m"
            break
        fi
    done
fi
# Default: long, neutral reply — semantics differ by event type:
#   gentle    → ignored (user did not take the suggestion)
#   proactive → accepted (user did not push back; silent consent for an
#               action that is already complete)
if [ -z "$OUTCOME" ]; then
    if [ "$EVENT_TYPE" = "proactive" ]; then
        OUTCOME="accepted"
        OUTCOME_MARKER="silent_accept"
    else
        OUTCOME="ignored"
        OUTCOME_MARKER="moved_on"
    fi
fi

# -----------------------------------------------------------------------
# Record the event. Reason field carries the gentle marker + outcome marker
# for later debugging via /knowledge-audit.
# -----------------------------------------------------------------------
REASON="$EVENT_TYPE:'$EVENT_MARKER' → $OUTCOME_MARKER"

# itr_log_event signature: sid type outcome silence_cost reason
itr_log_event "$SESSION_ID" "$EVENT_TYPE" "$OUTCOME" 0 "$REASON" >/dev/null 2>&1 || exit 0

echo "$TURN_KEY" > "$LAST_FIRE_FILE"

# This hook does NOT inject context — purely accumulates metrics. The
# intrusiveness-tracker.sh that runs after us will pick up the new state
# in its own format_context call on the next prompt.
exit 0
