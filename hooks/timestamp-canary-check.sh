#!/usr/bin/env bash
# timestamp-canary-check.sh — Stop: механическая проверка таймштамп-канарейки.
# en: Stop hook — verifies the last reply starts with the injected timestamp;
# alerts user+agent when the canary died (context drift).
#
# Уровень 3 правила «Таймштамп-канарейка» (rules/CLAUDE.md): собеседник-детектор
# заменён машинным алертом (решение собеседника 2026-08-08, «строй стража»).
# Семантика: инжект живой (timestamp-inject задеплоен), а последняя реплика не
# начинается с «🕐 YYYY-MM-DD HH:MM» — контекст, вероятно, уплыл; таймштамп
# старше 6 часов — эхо протухло, тот же сигнал. Успех молчит (silent correct),
# алерт — systemMessage собеседнику + additionalContext агенту.
#
# AP2 сюда сознательно НЕ применяется: страж — заказанный собеседником детектор
# качества, не проактивное вмешательство агента; глушить его в distressed —
# прятать сигнал ровно тогда, когда он нужнее всего.
#
# Guards: нет transcript → тихо; механизм инжекта не задеплоен → тихо
# (нет инжекта ≠ уплывание — другой класс проблемы, чинится install'ом).

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || exit 0

# Канарейка осмысленна только при живом инжекторе. Явный TIMESTAMP_INJECT_PATH
# (тесты) — без fallback; иначе sibling-first, затем установленный.
if [ -n "${TIMESTAMP_INJECT_PATH:-}" ]; then
    INJECTOR="$TIMESTAMP_INJECT_PATH"
else
    INJECTOR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/timestamp-inject.sh"
    [ -f "$INJECTOR" ] || INJECTOR="$HOME/.claude/hooks/timestamp-inject.sh"
fi
[ -f "$INJECTOR" ] || exit 0

# Последняя реплика ассистента (образец: output-language-check.sh).
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
      | select((role($items[.]) == "user" and
               ((get_text($items[.]) // "") | length > 0))
               or (($items[.].type // "") == "last-prompt"))]
      | first) as $pu |
    if $pu == null then
        ([range(0; $n) | $items[.] | select(role(.) == "assistant")]
         | map(get_text(.)) | map(select(. != "")) | last // "")
    else
        ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]
         | map(get_text(.)) | map(select(. != "")) | last // "")
    end
' "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.' 2>/dev/null)

[ -z "$LAST_ASSISTANT" ] && exit 0
[ "$LAST_ASSISTANT" = "null" ] && exit 0

alert() {
    jq -cn --arg m "$1" '{
      systemMessage: $m,
      hookSpecificOutput: {hookEventName: "Stop", additionalContext: $m}
    }'
    exit 0
}

# Первая непустая строка ответа должна начинаться с «🕐 YYYY-MM-DD HH:MM».
FIRST_LINE=$(printf '%s\n' "$LAST_ASSISTANT" | grep -m1 -v '^[[:space:]]*$' || true)
TS=$(printf '%s' "$FIRST_LINE" | grep -oE '^[[:space:]]*🕐 [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' || true)

[ -z "$TS" ] && alert "🚨 Канарейка контекста: ответ начат БЕЗ таймштампа при живом инжекте — инструкции, вероятно, размылись. Правило: предложить собеседнику перезапустить сессию (/save → новая сессия)."

# Свежесть: эхо старше 6 часов — протухший таймштамп, тот же сигнал.
EPOCH=$(date -j -f '%Y-%m-%d %H:%M' "$TS" +%s 2>/dev/null || date -d "$TS" +%s 2>/dev/null || true)
if [ -n "$EPOCH" ]; then
    NOW=$(date +%s)
    AGE=$(( NOW - EPOCH ))
    if [ "$AGE" -gt 21600 ] || [ "$AGE" -lt -21600 ]; then
        alert "🚨 Канарейка контекста: таймштамп ответа ($TS) отстаёт от часов больше чем на 6 часов — эхо протухло, контекст, вероятно, уплыл. Предложить собеседнику перезапуск сессии."
    fi
fi

exit 0
