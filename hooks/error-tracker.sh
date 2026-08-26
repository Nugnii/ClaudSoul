#!/usr/bin/env bash
# error-tracker.sh — PreToolUse[Bash]: при 2+ упавших командах в окне последних 6 говорит «стой» ПЕРЕД следующей попыткой, а не после упавшей.
# en: PreToolUse[Bash]: warns before a retry when 2+ of the last 6 tool calls failed.
#
# --- Почему хук переписан (D41, 2026-07-31) --------------------------------------
#
# Он стоял на PostToolUse[Bash] и читал `.tool_result.exit_code`. Замер по живому событию
# (зонд на установленной копии, четыре команды подряд) дал два независимых факта:
#
#   1. Поля `tool_result` в payload НЕТ. Настоящее имя — `tool_response`, и внутри
#      `stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected`. Кода возврата
#      среди них нет вовсе.
#   2. Важнее: **на упавшей Bash-команде PostToolUse не срабатывает.** Из четырёх команд
#      (`exit 7`, `grep` по несуществующему файлу, `echo`, разбор) события породили только
#      успешные. То есть счётчик провалов не мог заполниться НИ ПРИ КАКОМ имени поля.
#
# Отсюда наблюдаемая картина: все файлы `error_count_*` на диске содержали 0, а за
# 3,5 месяца в 732 расшифровках нет ни одного настоящего срабатывания. Тест при этом был
# зелёный, потому что кормил хук той же формой payload, которую хук предполагал, —
# `pattern-detector-wired-to-failure` в чистом виде.
#
# Где провалы ВИДНЫ: в расшифровке, блоком `tool_result` с `is_error: true` и телом
# «Exit code N». Поэтому счёт идёт оттуда.
#
# --- Почему счёт по окну, а не по серии подряд (2026-08-21) ----------------------
#
# Первая починка считала ХВОСТОВУЮ серию: идём от свежих записей к старым и стоим на
# первом успехе. Замер на живой сессии (25 вызовов Bash, 4 провала) дал хвост вида
# `false,true,false,true,false…` и серию длиной 0 — ни одного срабатывания.
#
# Причина в том, как харнесс велит звать инструменты: независимые вызовы идут ОДНИМ
# блоком, параллельно. Одна команда падает, соседняя в том же блоке проходит — и серия
# рвётся успехом, которого в осмысленном «застрял» нет. Порог «2 подряд» при батчинге
# практически недостижим: за две недели хук сказал что-то 15 раз.
#
# Поэтому считается доля провалов в ОКНЕ последних вызовов, а не непрерывность.
#
# Почему PreToolUse, а не Stop: сообщение хука — «остановись, не повторяй тот же подход».
# Оно полезно ровно перед следующей попыткой. На Stop оно опоздало бы на всю серию.
#
# Вход: JSON на stdin (PreToolUse). Выход: JSON, либо ничего.
#
# Текст идёт ДВУМЯ каналами сразу. `systemMessage` — владельцу, `additionalContext` —
# в контекст хода. Замер по всей истории расшифровок: 15 срабатываний прежней версии
# ушли в один только `systemMessage`, и ни на одно из них ход не отреагировал —
# записи `hook_system_message` в поток сообщений не попадают. Детектор, чей вывод
# никем не читается, неотличим от выключенного.

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; fi
DRAFT_DIR="${ERROR_TRACKER_DRAFT_DIR:-$LESSONS_DIR/_drafts}"

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

: "${SESSION_ID:=unknown}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
STRUGGLE_FILE="$STATE_DIR/had_struggle_${SESSION_ID}"
FIRED_FILE="$STATE_DIR/error_streak_fired_${SESSION_ID}"

# Число провалов среди последних RECENT исходов вызовов инструментов. Непрерывность не
# требуется: при батчинге вызовов успешная соседка в том же блоке разорвала бы серию,
# не отменив того, что мы буксуем.
#
# Окно чтения ограничено: расшифровка растёт до тысяч записей, а буксование свежее.
WINDOW="${ERROR_TRACKER_WINDOW:-80}"
RECENT="${ERROR_TRACKER_RECENT:-6}"
FAILS=$(tail -n "$WINDOW" "$TRANSCRIPT" 2>/dev/null | jq -rs --argjson recent "$RECENT" '
  [ .[]
    | (.message.content? // [])
    | if type == "array" then .[] else empty end
    | select(type == "object" and .type == "tool_result")
    | (.is_error // false)
  ]
  | .[-$recent:]
  | map(select(. == true))
  | length
' 2>/dev/null)

case "${FAILS:-}" in ''|*[!0-9]*) FAILS=0 ;; esac

THRESHOLD="${ERROR_TRACKER_THRESHOLD:-2}"

if [ "$FAILS" -ge "$THRESHOLD" ]; then
    printf '1' > "$STRUGGLE_FILE" 2>/dev/null || true
    # Не повторяем сообщение для той же длины серии: PreToolUse срабатывает перед каждой
    # командой, и без этого текст шёл бы дважды на одну и ту же неудачу.
    LAST_FIRED=""
    [ -f "$FIRED_FILE" ] && LAST_FIRED=$(cat "$FIRED_FILE" 2>/dev/null)
    if [ "$LAST_FIRED" != "$FAILS" ]; then
        printf '%s' "$FAILS" > "$FIRED_FILE" 2>/dev/null || true
        jq -n --arg n "$FAILS" --arg w "$RECENT" '
          ("⚠️ Из последних " + $w + " команд упало " + $n + ".\n\n1. СТОП — не повторяй тот же подход\n2. Перечитай ВЕСЬ вывод ошибок заново\n3. Назови 2-3 версии причины\n4. Пробуй другой подход\n5. После починки — /learn, чтобы записать урок") as $msg
          | {
              systemMessage: $msg,
              hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $msg}
            }'
    fi
    exit 0
fi

# Серия кончилась. Если она была длинной — предложить записать и положить скелет разбора.
if [ -f "$FIRED_FILE" ]; then
    ATTEMPTS=$(cat "$FIRED_FILE" 2>/dev/null)
    case "${ATTEMPTS:-}" in ''|*[!0-9]*) ATTEMPTS=0 ;; esac
    rm -f "$FIRED_FILE" 2>/dev/null || true
    if [ "$ATTEMPTS" -ge "$THRESHOLD" ]; then
        DRAFT_NOTE=""
        TODAY=$(date +%Y-%m-%d)
        DRAFT_FILE="$DRAFT_DIR/case-${TODAY}-auto-draft.md"
        mkdir -p "$DRAFT_DIR" 2>/dev/null || true
        if [ ! -f "$DRAFT_FILE" ] && [ -w "$DRAFT_DIR" ]; then
            cat > "$DRAFT_FILE" <<DRAFT
---
date: ${TODAY}
type: case
status: draft
attempts: ${ATTEMPTS}
source: error-tracker auto-draft
---

# Case ${TODAY} — auto-draft

> Скелет создан после того, как полоса из ${ATTEMPTS} упавших команд закончилась успехом.
> Заполни через \`/retro\` или удали, если случай тривиален.

## Что произошло

(что пытался сделать, что падало)

## Последовательность попыток

(${ATTEMPTS} попытки — восстанови по недавним командам и их выводу)

## Что сработало

(финальная правка)

## Корневая причина vs симптом

(если разные — укажи оба)

## Урок / правило

(одно предложение, actionable)

## Якоря

- domain:
- trigger:
- stakes:
DRAFT
            # $'...' — иначе в текст уходит литеральное «\n»: в двойных кавычках bash
            # его не разворачивает, а jq --arg передаёт строку как есть. Прежде это
            # пряталось в systemMessage, которого ход не видел.
            DRAFT_NOTE=$'\n'"📝 Скелет черновика: ${DRAFT_FILE/#$HOME/~}"
        fi
        jq -n --arg msg "💡 Полоса из ${ATTEMPTS} упавших команд закончилась успехом — стоит /learn?${DRAFT_NOTE}" \
            '{
               systemMessage: $msg,
               hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $msg}
             }'
    fi
fi

exit 0
