#!/usr/bin/env bash
# code-review-outcome.sh — PostToolUse[Bash] на `git commit`: подтверждает, что коммит СОСТОЯЛСЯ, и только тогда переводит запись стража в знаменатель замера.
# en: PostToolUse[Bash] on `git commit`: confirms the commit actually happened before the guard's record enters the measurement denominator.
#
# Зачем (D372, второй раунд противника 9 сентября 2026). `code-review-reminder` стоит на
# PreToolUse и пишет знаменатель ДО исполнения. Если вызов отменён — собеседник услышал
# напоминание и передумал, другой страж отбил команду, коммитить оказалось нечего, — в мире
# коммита нет, а прибор уже записал «крупный дифф ушёл в коммит без прогона» и объявил по
# нему первый порог лестницы ADR-015. Число для состоявшегося и для отменённого коммита
# получалось ПОБАЙТОВО одинаковым.
#
# Цена измерена: из 896 вызовов живого корпуса, прошедших `is_git_commit`, 63 (7%) не
# породили ни одного коммита. Ретро-прогон считает по `git log` и этих 7% не видит — два
# прибора одного предмета расходились на величину, которую ни один не называл.
#
# ПОЧЕМУ ИМЕННО PostToolUse, а не проверка HEAD внутри PreToolUse. На упавшей Bash-команде
# PostToolUse НЕ СРАБАТЫВАЕТ — это измерено и записано в шапке `error-tracker.sh` (D41,
# зонд из четырёх команд: события породили только успешные). Значит сам факт срабатывания
# здесь и есть признак того, что команда прошла; отдельного кода возврата в payload нет, и
# искать его не нужно. Отменённый на PreToolUse вызов до этого хука не доходит вовсе.
#
# НАЗВАННЫЙ ПРЕДЕЛ: «команда прошла» не равно «коммит создан». `git commit`, вернувший
# ненулевой код при живой оболочке (например, пустой индекс в составной команде через `&&`),
# сюда не дойдёт — на упавшей команде события нет. А `git commit || true` дойдёт, и запись
# будет засчитана. Форма редкая, в корпусе не встретилась; условие снятия — появится
# наблюдаемый случай, сверять придётся по сдвигу HEAD.
#
# Input  (stdin): {tool_name, tool_input, session_id, cwd} (PostToolUse JSON)
# Output (stdout): пусто — механизм молчит наружу, он только переводит запись
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
# Библиотеки нет — молчим и выходим: признак коммита, написанный здесь заново, разошёлся бы
# со стражем (род K), а расхождение двух половин одного механизма хуже отсутствия второй.
[ -f "$SCOPE_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$SCOPE_LIB"

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
is_git_commit "$COMMAND" || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
PENDING="$STATE_DIR/crr-pending-${SID}.jsonl"
[ -s "$PENDING" ] || exit 0

_RC_LIB="${RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/root-cause-lib.sh}"
[ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
[ -f "$_RC_LIB" ] && . "$_RC_LIB"
command -v rc_note_detection >/dev/null 2>&1 || exit 0

# Опустошение переименованием: между чтением и записью может прийти второй коммит той же
# сессии, и без атомарного снятия его запись потерялась бы. Приём взят у `drain_file`
# (`hooks/state-lock-lib.sh`) — здесь он нужен целиком, а не только по имени.
DRAIN="${PENDING}.drain.$$"
mv "$PENDING" "$DRAIN" 2>/dev/null || exit 0

# Чистка перед разбором — та же обязательная идиома, что у остальных потребителей журналов.
jq -cRn 'inputs | fromjson? // empty' "$DRAIN" 2>/dev/null | while IFS= read -r _line; do
    _act=$(printf '%s' "$_line" | jq -r '.act // ""' 2>/dev/null)
    _key=$(printf '%s' "$_line" | jq -r '.key // ""' 2>/dev/null)
    [ -n "$_act" ] || continue
    rc_note_detection "$STATE_DIR" "$SID" "code-review-reminder" "$_act" "$_key"
done

rm -f "$DRAIN" 2>/dev/null
exit 0
