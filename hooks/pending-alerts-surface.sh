#!/usr/bin/env bash
# pending-alerts-surface.sh — UserPromptSubmit: поднимает отложенное видимым каналом.
#
# Зачем: Stop→systemMessage не отображается в части UI (VS Code) — алерты
# session-collector (ошибки→/learn, висячие записи опровержения, долг тишины, нудж
# /compile) уходили в пустоту. Канал UserPromptSubmit→additionalContext виден
# надёжно (как knowledge-activator, intrusiveness). См. case-2026-06-14.
#
# Поднимаются два источника:
#   1) `pending-alerts.txt` — общая очередь от session-collector (межсессионная);
#   2) `startup-signals-<sid>.txt` — сигналы старта текущей сессии (посессионные).
#
# --- Почему сигналы старта попали сюда (D49, 2026-07-31) --------------------------
#
# У них был ЕДИНСТВЕННЫЙ канал доставки: `knowledge-activator.sh` на первом
# PreToolUse[Bash|Edit|Write]. Сессия, в которой не случилось ни одного такого вызова,
# сигналов не видела никогда, а файл оставался лежать навсегда. Замер на момент починки:
# **99 файлов, все непустые**, старейший от 24 апреля. Внутри — «в корне проекта нет
# CLAUDE.md», «база знаний обновилась», заявка на эскалацию, обратный дрейф установки.
#
# Второй канал именно здесь, а не в новом хуке: этот уже про «показать отложенное»,
# уже на UserPromptSubmit и уже гасит показанное. Сессия без единого инструмента, но с
# репликой собеседника, теперь сигналы получит. Кто первым дошёл — тот и показал:
# оба потребителя удаляют файл после чтения.
#
# Контракт:
#   stdin  = UserPromptSubmit payload
#   stdout = jq hookSpecificOutput.additionalContext (или пусто)
# Показ ровно один раз: источник очищается сразу после чтения.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
: "${INPUT:=}"

STATE_DIR="${CLAUDSOUL_STATE_DIR:-${STATE_DIR:-$HOME/.claude/hooks/state}}"
QUEUE="$STATE_DIR/pending-alerts.txt"

command -v jq >/dev/null 2>&1 || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
SIGNALS=""
if [ -n "$SID" ]; then
    SIGNALS_FILE="$STATE_DIR/startup-signals-${SID}.txt"
    if [ -s "$SIGNALS_FILE" ]; then
        SIGNALS=$(cat "$SIGNALS_FILE" 2>/dev/null || true)
        rm -f "$SIGNALS_FILE" 2>/dev/null || true
    fi
fi

ALERTS=""
if [ -s "$QUEUE" ]; then
    ALERTS=$(cat "$QUEUE" 2>/dev/null || true)
    : > "$QUEUE" 2>/dev/null || true
fi

# Уборка недоставленных сигналов от сессий, которые уже не вернутся. Без неё файлы
# копятся годами: до этой правки их накопилось 99, старейшему было три месяца.
find "$STATE_DIR" -maxdepth 1 -name 'startup-signals-*.txt' \
    -mtime "+${STARTUP_SIGNALS_TTL_DAYS:-14}" -delete 2>/dev/null || true

[ -n "$SIGNALS" ] || [ -n "$ALERTS" ] || exit 0

BODY=""
[ -n "$SIGNALS" ] && BODY="📣 Сигналы старта сессии:
${SIGNALS}"
if [ -n "$ALERTS" ]; then
    [ -n "$BODY" ] && BODY="${BODY}

"
    BODY="${BODY}🔔 Отложенные уведомления системы (с прошлых сессий — канал session-collector):
${ALERTS}"
fi

printf '%s' "$BODY" | jq -Rs '{
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: .
      }
    }'
exit 0
