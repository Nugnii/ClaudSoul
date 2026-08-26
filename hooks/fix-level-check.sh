#!/usr/bin/env bash
# fix-level-check.sh — детектор пост-инцидентного фикса, оставшегося текстом.
# en: detects post-incident text-rule fixes in the agent's own reply and reminds to lift them to a mechanism (activator/blocker)
#
# Заявка на эскалацию pattern-inside-out-blindness (открыта 2026-04-23, закрыта
# этим хуком): 15-е проявление (case-2026-04-23-text-rule-vs-mechanism) показало,
# что blocker-tier сигналы знания не ловят сам момент, когда агент после инцидента
# предлагает ФИКС УРОВНЯ 1 — текстовое правило, обещание «буду внимательнее» —
# вместо механизма (уровни embedded-ness: см. principle-knowledge-in-the-world).
#
# Словарь НЕ придуман (урок v1.13.3: придуманный словарь — девять срабатываний за
# 214 сессий и ноль на реальных поправках). Фразы взяты из задокументированных
# проявлений:
#   - case-2026-04-23-model-vs-system-source-blindness: «надо вынести урок»,
#     «не хватает жёсткого чеклиста», и жанровый ряд оттуда же: ретро → «нужен
#     чеклист», post-mortem → «будем осторожнее», ошибка → «учту на будущее»
#   - правило Source-check (rules/CLAUDE.md v0.3): «надо X / будем осторожнее /
#     учту» — маркеры модельной пост-инцидентной фразы
#
# Механика — как у output-language-check.sh (уровень 2, activator injection):
#   - Stop / PreCompact: скан последнего ответа агента, находки → state (pending)
#   - UserPromptSubmit / PreToolUse: инжект напоминания, pending → surfaced
#
# Подавление: если в том же ответе назван механизм (хук, скрипт, тест, детектор,
# blocker, инжект) или стоит пометка model-generated — фикс уже не текстовый
# (или источник уже размечен), молчим. Сознательное ограничение: фразы внутри
# кода/цитат не отличаются от прозы — принято, инжект советующий, не блокирующий.
#
# Silent degradation: нет jq / расшифровки / session_id — exit 0 без вывода.

set -eo pipefail

HOOK_NAME="fix-level-check"
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || exit 0

# portable-lib: to_lower (кириллица), pad_words. Порядок поиска: рядом с собой,
# потом установленный каталог — обратный порядок выключил бы хук на чистой машине.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib in "$HOOK_DIR/portable-lib.sh" "$HOME/.claude/hooks/portable-lib.sh"; do
    [ -f "$lib" ] && { . "$lib"; break; }
done
command -v to_lower >/dev/null 2>&1 || exit 0

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$SID" ] && exit 0
PENDING_FILE="${STATE_DIR}/fix-level-${SID}.jsonl"

# Фразы-маркеры текстового фикса. Каждая — из задокументированного проявления
# (см. шапку), сравнение по нормализованному нижнему регистру с границами слов.
FIX_PHRASES=(
    "надо вынести урок"
    "не хватает чеклиста"
    "не хватает жёсткого чеклиста"
    "нужен чеклист"
    "надо чеклист"
    "будем осторожнее"
    "будем аккуратнее"
    "буду внимательнее"
    "буду осторожнее"
    "буду аккуратнее"
    "учту на будущее"
    "запомню на будущее"
    "надо запомнить"
    "запишу правило"
    "добавлю правило"
)

# Маркеры механизма/разметки: подстрочное совпадение, ловит словоформы.
MECHANISM_MARKERS=("хук" "hook" "скрипт" "детектор" "инжект" "blocker" "detection_signal" "механизм" "тест" "model-generated")

scan_and_persist() {
    [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || return 0

    local last_assistant
    last_assistant=$(jq -s '
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

    [ -z "$last_assistant" ] && return 0
    [ "$last_assistant" = "null" ] && return 0

    local lower padded
    lower=$(to_lower "$last_assistant")
    padded=$(pad_words "$lower")

    local m
    for m in "${MECHANISM_MARKERS[@]}"; do
        case "$lower" in *"$m"*) return 0 ;; esac
    done

    local ts phrase
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    for phrase in "${FIX_PHRASES[@]}"; do
        case "$padded" in
            *" $phrase "*)
                if [ -f "$PENDING_FILE" ] && \
                   jq -e --arg p "$phrase" 'select(.phrase==$p)' "$PENDING_FILE" >/dev/null 2>&1; then
                    continue
                fi
                jq -cn --arg ts "$ts" --arg sid "$SID" --arg p "$phrase" --arg event "$EVENT" \
                    '{ts:$ts, sid:$sid, event:$event, phrase:$p, status:"pending"}' \
                    >> "$PENDING_FILE" 2>/dev/null || true
                ;;
        esac
    done
}

surface_pending() {
    local event_name="${1:-UserPromptSubmit}"
    [ -f "$PENDING_FILE" ] || return 0

    local pending
    pending=$(jq -r 'select(.status=="pending") | .phrase' "$PENDING_FILE" 2>/dev/null \
              | awk '!seen[$0]++' | head -5)
    [ -z "$pending" ] && return 0

    local phrase_list
    phrase_list=$(printf '%s' "$pending" | awk 'BEGIN{ORS=""} NR>1{printf ", "} {printf "«%s»", $0}')
    [ -z "$phrase_list" ] && return 0

    local msg
    msg="🧱 Fix-level check: в предыдущем ответе — ${phrase_list}. Это пост-инцидентный фикс уровня 1 (текст, который надо вспомнить). Source-check: назови механизм системы, породивший вывод, — либо явно пометь фразу как model-generated observation. Если фикс настоящий — подними до уровня 2 (activator injection) или 3 (blocker-tier hook), см. principle-knowledge-in-the-world; текстовое правило после инцидента — описание проблемы, не fix."

    jq -cn --arg msg "$msg" --arg ev "$event_name" \
        '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $msg}}'

    local tmp
    tmp=$(mktemp 2>/dev/null) || return 0
    jq -c 'if .status=="pending" then .status="surfaced" else . end' \
        "$PENDING_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$PENDING_FILE" || rm -f "$tmp"
}

case "$EVENT" in
    Stop|PreCompact)
        scan_and_persist
        ;;
    UserPromptSubmit)
        surface_pending "UserPromptSubmit"
        ;;
    PreToolUse)
        surface_pending "PreToolUse"
        ;;
esac

exit 0
