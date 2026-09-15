#!/usr/bin/env bash
# test_adversary_heredoc_quoted_mention_is_target.sh
#
# АТАКА: разбор цели heredoc читает команду КАК НАПИСАНА — кавычки не снимаются.
# Значит перенаправление, стоящее ВНУТРИ строки-аргумента, считается настоящей целью.
#
# Механизм. В ds_evaluate_node ветка heredoc_target_regex подаёт в awk сырое
# `.command` (никакого ds_unquoted_command, никакого ds_code_only — сравни с
# command_uses/shell_regex, где вид команды выбирается под утверждение). Правило
# `/<<-?[ ]*'?"?[A-Za-z_]/` находит `<<EOF` внутри текста сообщения коммита,
# а emit(same_command(префикс)) видит в том же тексте `> hooks/x.sh` и печатает его
# как цель.
#
# Вход — сообщение коммита, ОПИСЫВАЮЩЕЕ форму записи в хук. Ровно то, что пишут в
# этом репозитории: шапки хуков и CHANGELOG полны таких примеров.
#
# Ожидание: rc=1. Команда `git commit` не пишет в hooks/x.sh — она пишет в git.
# Факт:     rc=0, а сквозной прогон даёт сигнал уровня deny.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

TARGET_RX='(hooks|scripts)/[^ ]*\.(sh|bash|py)'
NODE=$(jq -nc --arg rx "$TARGET_RX" '{heredoc_target_regex:$rx}')

CMD=$(printf 'git commit -m "док: cat > hooks/x.sh <<EOF\nпример из шапки: stat -f %%z\nEOF"\n')

echo "--- команда ---"
printf '%s\n' "$CMD"
echo "---------------"

ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" ""
RC=$?
echo "предикат heredoc_target_regex: rc=$RC (0 = признал целью)"

fail=0
if [ "$RC" -eq 0 ]; then
    echo 'FAIL: цель опознана внутри строки-аргумента. git commit -m "…" не создаёт'
    echo "      hooks/x.sh — путь стоит в ТЕКСТЕ сообщения. Предикат берёт сырую команду,"
    echo "      поэтому упоминание неотличимо от перенаправления."
    echo "      Соседний тест test_heredoc_target_scope.sh:50 (T4) закрывает упоминание в ТЕЛЕ"
    echo "      heredoc; здесь упоминание стоит на самой строке маркера, и учёта нет."
    fail=1
fi

# Достижимость: сквозной прогон по живому знанию, если оно на месте.
P="$HOME/.claude/global-lessons/pattern-shell-portability.md"
if [ -f "$P" ] && [ "$(uname -s)" = "Darwin" ]; then
    SIG=$(ds_evaluate "$P" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" "")
    E2E=$?
    echo "сквозной прогон по pattern-shell-portability: rc=$E2E signal=[$SIG]"
    if [ "$E2E" -eq 0 ]; then
        ENF=$(awk '/^detection_signals:[[:space:]]*\|/{f=1;next} f&&/^[^[:space:]]/{exit} f{print substr($0,3)}' "$P" \
              | jq -r --arg n "$SIG" '.[]? | select(.name==$n) | .enforcement // "hint"' 2>/dev/null)
        echo "enforcement сигнала: $ENF"
        if [ "$ENF" = "deny" ]; then
            echo "FAIL: сигнал уровня deny — blocker-tier-check вернёт permissionDecision:deny."
            echo "      Собеседник получит отказ на коммит, описывающий форму записи в хук."
            fail=1
        fi
    fi
else
    echo "достижимость: сквозной прогон пропущен (нет $P либо не Darwin)"
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
