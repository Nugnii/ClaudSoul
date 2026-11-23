#!/usr/bin/env bash
# wakeup-author-mark.sh — PreToolUse[ScheduleWakeup]: запоминает сумму текста хода побудки, чтобы подача узнала его служебным.
# en: PreToolUse[ScheduleWakeup]: records the checksum of the scheduled wakeup prompt so the submit-side filter treats that turn as not the owner's.
#
# Зачем (D1247, 8 ноября 2026). Ход побудки приходит хукам подачи реплики как обычная реплика: вход хука автора не несёт
# (замер зондом — 8 полей, `isMeta`/`origin` нет), текущей реплики в расшифровке на подаче ещё нет, а формы у текста нет —
# его пишет сама модель. Автор хода известен в одном месте — в вызове `ScheduleWakeup`: текст `prompt` там виден целиком,
# и ход побудки приходит с ним побайтно (корпус: 3 из 3). Сумма текста ложится в `state/wakeup-prompts.tsv`, и
# `is_non_user_turn` (`hooks/hook-input-lib.sh`) узнаёт по ней ход на подаче.
# НАЗВАННЫЙ ПРЕДЕЛ: реплика владельца, побайтно равная запланированной побудке, будет принята за побудку; сторожевое
# `<<autonomous-loop-dynamic>>` харнесс подменяет инструкциями — такой ход суммой не узнаётся. Файл общий для сессий и
# растёт на строку за побудку (около 20 байт) — только дописывается, без чтения и перезаписи.
# Условие снятия: харнесс начнёт передавать хуку подачи реплики автора хода (поле вроде `isMeta`/`origin`) — тогда признак
# берётся из входа, а этот хук и файл снимаются.
#
# Input  (stdin): {tool_name, tool_input:{prompt,…}, session_id} (PreToolUse JSON)
# Output: пусто. Exit: всегда 0.
set -uo pipefail
STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = ScheduleWakeup ] || exit 0
P=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
[ -n "$P" ] || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
printf '%s\t%s\n' "$(printf '%s' "$P" | cksum | cut -d' ' -f1)" "$(date +%s)" >> "$STATE_DIR/wakeup-prompts.tsv" 2>/dev/null
exit 0
