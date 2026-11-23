#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_adversary_heredoc_suffix_belongs_to_next_command.sh
#
# АТАКА: отсечение по разделителю команд стоит ТОЛЬКО слева от маркера.
#
# Механизм. В awk ветки heredoc_target_regex две строки:
#     emit(same_command(substr($0, 1, _ms - 1)))   # префикс — отсекается по разделителю
#     emit(substr($0, _ms + _ml))                  # суффикс — отдаётся ЦЕЛИКОМ
# Довод, записанный в шапке предиката («что левее разделителя — другая команда»), верен
# и справа: в `cat <<EOF | pbcopy ; date > scripts/stamp.sh` тело heredoc уходит в pbcopy,
# а `scripts/stamp.sh` создаёт date. Соседний тест test_heredoc_target_scope.sh:45,63
# (T3, T7) закрывает ровно эту форму слева и не проверяет её справа.
#
# Ожидание: rc=1 — heredoc не пишет в scripts/stamp.sh.
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

fail=0
probe() { # $1=метка $2=команда
    ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$2" '{command:$c}')" ""
    local rc=$?
    echo "--- $1 (rc=$rc) ---"
    printf '%s\n' "$2"
    if [ "$rc" -eq 0 ]; then
        echo "FAIL: цель взята из команды, стоящей ПОСЛЕ разделителя. Тело heredoc туда не идёт."
        fail=1
    fi
}

probe "суффикс за ';'"  "$(printf 'cat <<%s | pbcopy ; date > scripts/stamp.sh\nstat -f %%z /tmp\nEOF\n' "'EOF'")"
probe "суффикс за '&&'" "$(printf 'cat <<%s | pbcopy && date > hooks/stamp.sh\nstat -f %%z /tmp\nEOF\n' "'EOF'")"
probe "суффикс за '||'" "$(printf 'cat <<%s | pbcopy || date > scripts/fallback.py\nstat -f %%z /tmp\nEOF\n' "'EOF'")"

# Достижимость: сквозной прогон по живому знанию.
P="$HOME/.claude/global-lessons/pattern-shell-portability.md"
CMD=$(printf 'cat <<%s | pbcopy ; date > scripts/stamp.sh\nstat -f %%z /tmp\nEOF\n' "'EOF'")
if [ -f "$P" ]; then
    SIG=$(ds_evaluate "$P" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" "")
    E2E=$?
    echo "сквозной прогон: rc=$E2E signal=[$SIG]"
    if [ "$E2E" -eq 0 ]; then
        echo "FAIL: сигнал [$SIG] сработал — blocker-tier-check вернёт отказ на команду,"
        echo "      которая ничего в hooks/ и scripts/ не пишет."
        fail=1
    fi
else
    echo "достижимость: сквозной прогон пропущен (нет $P)"
fi

# КОНТРОЛЬ РАБОТЫ (21 сентября 2026, D342): вердикт снят с ОТСУТСТВИЯ («сигнал не
# сработал»), а отрицание верно и на мёртвом предмете — выхолощенная библиотека не
# объявляет ни одной функции, вызовы молча падают, и тест зеленеет. Предмет обязан
# объявить ds_evaluate_node: это наблюдаемый след того, что судить БЫЛО чем.
command -v ds_evaluate_node >/dev/null 2>&1 \
    || { echo "FAIL: предмет не объявил ds_evaluate_node — судить нечего"; exit 1; }
[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
