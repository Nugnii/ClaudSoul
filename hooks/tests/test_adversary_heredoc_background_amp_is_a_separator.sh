#!/usr/bin/env bash
# test_adversary_heredoc_background_amp_is_a_separator.sh
#
# АТАКА: словарь разделителей команд неполон — фонового `&` в нём нет.
#
# Механизм. same_command() режет префикс по /(&&|\|\||;|\|)/. Одиночный `&` — тоже
# разделитель по POSIX (запуск в фоне), но под `&&` он не подходит и под `|` не подходит.
# Значит в `date > hooks/stamp.sh & cat <<EOF | pbcopy` префикс не отсекается, и
# перенаправление ПРЕДЫДУЩЕЙ команды становится целью heredoc.
#
# Это тот же класс, что чинили 29 августа для `&&` (шапка предиката, форма
# `git show … > /tmp/x.sh && python3 - <<PY`): починили перечислением форм, а не правилом,
# и форма, не попавшая в перечень, осталась.
#
# Ожидание: rc=1 — heredoc уходит в pbcopy, hooks/stamp.sh пишет date.
# Факт:     rc=0, сквозной прогон даёт сигнал уровня deny.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

TARGET_RX='(hooks|scripts)/[^ ]*\.(sh|bash|py)'
NODE=$(jq -nc --arg rx "$TARGET_RX" '{heredoc_target_regex:$rx}')
CMD=$(printf 'date > hooks/stamp.sh & cat <<%s | pbcopy\nstat -f %%z /tmp\nEOF\n' "'EOF'")

echo "--- команда ---"; printf '%s\n' "$CMD"; echo "---------------"
echo "проверка формы настоящим bash (кто на самом деле пишет hooks/stamp.sh):"
T=$(mktemp -d); mkdir -p "$T/hooks"
( cd "$T" && printf 'date > hooks/stamp.sh & cat <<%s | cat >/dev/null\nstat -f %%z /tmp\nEOF\nwait\n' "'EOF'" > r.sh && bash r.sh >/dev/null 2>&1 )
echo "  hooks/stamp.sh = [$(head -c 40 "$T/hooks/stamp.sh" 2>/dev/null)] — тела heredoc там нет"

ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" ""
RC=$?
echo "предикат heredoc_target_regex: rc=$RC (0 = признал целью)"

fail=0
if [ "$RC" -eq 0 ]; then
    echo "FAIL: одиночный '&' не отсечён — цель взята у команды, запущенной в фоне."
    echo "      same_command() перечисляет && || ; | и не знает '&'."
    fail=1
fi

P="$HOME/.claude/global-lessons/pattern-shell-portability.md"
if [ -f "$P" ]; then
    SIG=$(ds_evaluate "$P" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" "")
    E2E=$?
    echo "сквозной прогон: rc=$E2E signal=[$SIG]"
    if [ "$E2E" -eq 0 ]; then
        echo "FAIL: сигнал [$SIG] сработал — отказ на команду, которая в hooks/ ничего не пишет."
        fail=1
    fi
else
    echo "достижимость: сквозной прогон пропущен (нет $P)"
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
