#!/usr/bin/env bash
# timestamp-canary-check.sh — Stop: механическая проверка таймштамп-канарейки.
# en: Stop hook — verifies the last reply starts with the injected timestamp; alerts user+agent when the canary died (context drift).
#
# Уровень 3 правила «Таймштамп-канарейка» (rules/CLAUDE.md): собеседник-детектор
# заменён машинным алертом (решение собеседника 2026-08-08, «строй стража»).
# Семантика: инжект живой (timestamp-inject задеплоен), а последняя реплика не
# начинается с «🕐 YYYY-MM-DD HH:MM» — контекст, вероятно, уплыл; шапка не
# совпадает со значением инжекта — время не эхо, а оценка. Успех молчит
# (silent correct), алерт — systemMessage собеседнику + additionalContext агенту.
#
# Сверка ЗНАЧЕНИЯ добавлена 2026-08-26 (case-2026-08-26-timestamp-on-wrong-block-
# and-invented-value): до неё страж проверял только ФОРМУ первой строки и свежесть
# ±6 часов, поэтому выдуманный, но правильно оформленный таймштамп с расхождением
# в 35 минут проходил молча — детектор был привязан к виду строки, а не к её
# источнику (pattern-detector-wired-to-failure). Значение берётся из самого
# транскрипта (записи attachment/hook_additional_context), а не из нового файла
# состояния: инжектор остаётся без состояния, и читателя без писателя не заводим.
# Инжекта в транскрипте нет (старый формат, чужой харнесс) → откат на прежнюю
# проверку свежести, а не алерт: отсутствие данных ≠ уплывание.
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

# Самозацикливание (2026-08-15): алерт уходит как additionalContext и ПРОДОЛЖАЕТ
# ход; продолжение по построению без свежего инжекта (инжектор — UserPromptSubmit,
# владелец молчит) → снова нет шапки → снова алерт → цепочка «Без изменений»
# до бесконечности. Два предохранителя, оба до любого алерта:
# 1) документированный флаг харнесса «ход уже продолжен Stop-хуком»;
STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

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
PARSED=$(jq -s '
    def role(x): x.message.role // x.role // "";
    def get_text(x):
        (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then
            ($c | map(select(.type == "text") | .text) | join("\n"))
        elif ($c | type) == "string" then $c
        else "" end;
    # Реплика собеседника: role=user, не meta, не sidechain, с текстом.
    # Записи type=="last-prompt" НЕ считаются границей хода: движок пишет их
    # многократно внутри одного хода (чекпойнты), и по ним «первый ответ хода»
    # съезжал на продолжение — таймштампа там нет по построению → ложный алерт.
    def real_user(x): role(x) == "user"
        and ((x.isMeta // false) | not)
        and ((x.isSidechain // false) | not)
        and ((get_text(x) // "") | length > 0);
    # Ход может быть запущен не репликой владельца, а самим хуком (Stop → новый
    # ход). Пока владелец молчит, $pu не двигается, и «первый ответ после
    # реплики» навсегда указывает на НАЧАЛО цепочки — ответ, который уже не
    # изменить: 6 самовоспроизводящихся алертов подряд на шапке предыдущего дня
    # (2026-08-09). Границу хода при этом из транскрипта не восстановить:
    # type=="last-prompt" пишется и внутри хода (c71af66), а «текст без
    # tool_use между блоками» ломается на многоблочных ответах.
    # Поэтому проверяется ПОСЛЕДНЯЯ выданная шапка: среди ответов после реплики
    # владельца берётся последний блок, чья первая строка выглядит шапкой. Нет
    # ни одного такого блока — шапка пропала, это и есть уплывание (алерт ниже
    # по пустому TS). Свежесть и сегмент фазы проверяются у неё же.
    def head_line(t): (t | split("\n") | map(select(test("^[[:space:]]*$") | not)) | first // "");
    def is_header(t): (head_line(t) | test("^\\s*(🕐 )?[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}"));
    . as $items | (length) as $n |
    ([range(0; $n) | ($n - 1 - .) | select(real_user($items[.]))] | first) as $pu |
    ([range((if $pu == null then -1 else $pu end) + 1; $n) | $items[.]
      | select(role(.) == "assistant" and ((.isSidechain // false) | not))]
     | map(get_text(.)) | map(select(. != ""))) as $texts |
    {pu: ($pu // -1),
     header_blocks: ([$texts[] | select(is_header(.))] | length),
     texts_after_pu: ($texts | length),
     text: (([$texts[] | select(is_header(.))] | last) // ($texts | first) // "")}
' "$TRANSCRIPT_PATH" 2>/dev/null)

PU=$(printf '%s' "$PARSED" | jq -r '.pu // -1' 2>/dev/null)
HEADER_COUNT=$(printf '%s' "$PARSED" | jq -r '.header_blocks // 0' 2>/dev/null)
TEXTS_AFTER_PU=$(printf '%s' "$PARSED" | jq -r '.texts_after_pu // 0' 2>/dev/null)
LAST_ASSISTANT=$(printf '%s' "$PARSED" | jq -r '.text // empty' 2>/dev/null)

[ -z "$LAST_ASSISTANT" ] && exit 0
[ "$LAST_ASSISTANT" = "null" ] && exit 0

# 2) маркер «на этот ход владельца уже алертили»: ключ — сессия + позиция
# последней реплики владельца ($PU не двигается, пока владелец молчит).
# Один алерт на ход; новая реплика владельца взводит канарейку заново.
# Не полагается на семантику флага из п.1 — проверяется тестами.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
STATE_DIR="${CANARY_STATE_DIR:-$HOME/.claude/hooks/state}"
MARK="$STATE_DIR/canary-alerted-${SESSION_ID}"
[ -f "$MARK" ] && [ "$(cat "$MARK" 2>/dev/null)" = "$PU" ] && exit 0

alert() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    printf '%s' "$PU" > "$MARK" 2>/dev/null
    # Debug-лог: одна строка на каждый alert (событие редкое). Ловит, ЧТО страж
    # видел в момент срабатывания — чтобы следующий ложный alert был доказан, не
    # додуман. Ключевые различители: header_blocks=0 → header-ответа не было в
    # транскрипте (race/недописан); header_blocks≥1 но пустой ts → извлечение ts
    # промахнулось. transcript_mtime_age_s мал (~0-1) → файл писался в момент чтения.
    _now=$(date +%s 2>/dev/null || echo 0)
    # Порядок обязателен: GNU-форма `-c` ПЕРВОЙ. Обратный порядок молча ломается на
    # Linux — `stat -f %m` там означает «сведения о файловой системе», печатает справку
    # с «File: ...» в stdout и возвращает КОД 0. Фоллбек `||` не наступает, потому что
    # провала нет, и в переменную уезжает многострочный текст; дальше он раскрывается
    # как имя переменной и роняет хук под `set -u`. На macOS дефект невидим.
    # Канон — file_mtime из portable-lib.sh, здесь повторён порядок, а не изобретён.
    _mt=$(stat -c %Y "$TRANSCRIPT_PATH" 2>/dev/null || stat -f %m "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
    _lines=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ' || echo 0)
    jq -cn \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '')" \
        --arg sid "${SESSION_ID:-}" \
        --argjson pu "${PU:-0}" \
        --argjson hdr "${HEADER_COUNT:-0}" \
        --argjson tap "${TEXTS_AFTER_PU:-0}" \
        --arg first "${FIRST_LINE:-}" \
        --arg tsval "${TS:-}" \
        --argjson mtage "$(( _now - _mt ))" \
        --argjson lines "${_lines:-0}" \
        --arg stopact "${STOP_ACTIVE:-}" \
        --arg msg "${1:0:48}" \
        '{at:$at, sid:$sid, pu:$pu, header_blocks:$hdr, texts_after_pu:$tap,
          first_line:$first, ts:$tsval, transcript_mtime_age_s:$mtage,
          transcript_lines:$lines, stop_active:$stopact, alert:$msg}' \
        >> "$STATE_DIR/canary-debug.jsonl" 2>/dev/null || true
    jq -cn --arg m "$1" '{
      systemMessage: $m,
      hookSpecificOutput: {hookEventName: "Stop", additionalContext: $m}
    }'
    exit 0
}

# Первая непустая строка ответа должна начинаться с «🕐 YYYY-MM-DD HH:MM».
FIRST_LINE=$(printf '%s\n' "$LAST_ASSISTANT" | grep -m1 -v '^[[:space:]]*$' || true)
# Значок 🕐 необязателен: канарейка ловит уплывание контекста, а не дисциплину
# эмодзи — эхо «2026-08-08 23:05 CEST» доказывает, что инструкция жива.
TS=$(printf '%s' "$FIRST_LINE" | grep -oE '^[[:space:]]*(🕐 )?[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' || true)

# Значение инжекта этого хода: последняя строка hook_additional_context,
# начинающаяся с «🕐 <дата> <время>». Контракт — сам значок 🕐, не формулировка
# инжектора: текст подсказки менялся и ещё будет, маркер времени — нет.
INJECTED=$(jq -rs '
    [ .[]
      | select(.type == "attachment")
      | .attachment // empty
      | select(.type == "hook_additional_context")
      | .content // []
      | .[]?
      | select(type == "string")
      | capture("^🕐 (?<ts>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2})").ts
    ] | last // empty' "$TRANSCRIPT_PATH" 2>/dev/null || true)

# Нет инжекта — нет и таймштампа: так велит само правило, и молчание здесь верно.
# До 28 августа 2026 страж утверждал «БЕЗ таймштампа ПРИ ЖИВОМ ИНЖЕКТЕ», ни разу не
# проверив вторую половину утверждения: признак строился по форме ОТВЕТА, а вывод делался
# об ИСТОЧНИКЕ. После сжатия контекста инжект в окне отсутствовал 470 строк подряд, а
# страж всё это время требовал перезапускать живую сессию. Сломанный инжектор — другой
# класс задачи (чинится хук, не сессия), и смешивать их нельзя.
if [ -z "$TS" ]; then
    if [ -n "$INJECTED" ]; then
        alert "🚨 Канарейка контекста: ответ начат БЕЗ таймштампа при живом инжекте ($INJECTED) — инструкции, вероятно, размылись. Правило: предложить собеседнику перезапустить сессию (/save → новая сессия)."
    fi
    exit 0
fi

# Фаза ablation: в VSCode-расширении диалог — единственная владелец-видимая
# поверхность (statusline/systemMessage не рендерятся; amendment phase-3,
# 2026-08-09). При активной фазе шапка ответа обязана нести сегмент 🧪.
PHM="${ABLATION_DIR:-$HOME/.claude/ablation}/active-phase.json"
if [ -f "$PHM" ]; then
    PH=$(jq -r '.phase // empty' "$PHM" 2>/dev/null)
    if [ -n "$PH" ] && ! grep -qF "🧪" <<< "$FIRST_LINE"; then
        alert "🚨 Канарейка: фаза ablation «${PH}» активна, а шапка ответа без сегмента фазы — владелец видит фазу только в диалоге (VSCode). Формат шапки: «🕐 <время> · 🧪 ${PH} · очередь N/20»."
    fi
fi

if [ -n "$INJECTED" ]; then
    # Точное совпадение до минуты: правило требует ЭХО, а не оценку прошедшего.
    # Длинный ход — не оправдание расхождения: инжект один на ход, эхо одно.
    if [ "$TS" != "$INJECTED" ]; then
        alert "🚨 Канарейка контекста: шапка ответа ($TS) не совпадает с инжектом ($INJECTED) — время не эхо, а оценка. Правило: время не выдумывать, брать из последнего инжекта 🕐."
    fi
else
    # Инжекта в транскрипте не нашлось — прежняя проверка: эхо старше 6 часов.
    EPOCH=$(date -j -f '%Y-%m-%d %H:%M' "$TS" +%s 2>/dev/null || date -d "$TS" +%s 2>/dev/null || true)
    if [ -n "$EPOCH" ]; then
        NOW=$(date +%s)
        AGE=$(( NOW - EPOCH ))
        if [ "$AGE" -gt 21600 ] || [ "$AGE" -lt -21600 ]; then
            alert "🚨 Канарейка контекста: таймштамп ответа ($TS) отстаёт от часов больше чем на 6 часов — эхо протухло, контекст, вероятно, уплыл. Предложить собеседнику перезапуск сессии."
        fi
    fi
fi

exit 0
