#!/usr/bin/env bash
# test_adversary_heredoc_command_absent_comment_unmasks_quote.sh
#
# АТАКА: ds_code_only заменяет строку комментария на ОДИНОЧНУЮ двойную кавычку, и это
# ломает парность кавычек для следующего шага. ds_unquoted_command снимает пары
# /"[^"]*"/, поэтому впрыснутая кавычка находит себе пару НЕ ТАМ: она съедает кусок
# настоящего кода, а закавыченный текст, который снять полагалось, остаётся голым.
#
# Механизм (detection-signals-lib.sh):
#     ds_code_only:        sub(/(^|")[[:space:]]*#.*$/, "\"", s)   ← кладёт кавычку
#     ds_unquoted_command: gsub(/"[^"]*"/, " ", s)                 ← парует со сдвигом
#     command_absent:      ds_unquoted_command(ds_code_only(ds_shell_only(cmd)))
#
# Вход — команда из комментария и печати строки. Ни одного вызова timeout в ней нет:
# слово стоит внутри двойных кавычек, то есть ровно в том положении, которое КОНТРПРИМЕР
# признака объявляет неловимым («имя из строки-аргумента не ловится»).
#
# Ожидание: rc=1.
# Факт:     rc=0, а сигнал absent_on_this_machine несёт enforcement:deny — собеседник
#           получает permissionDecision:deny на команду, которая ничего не запускает.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

# Имя — отсутствующее ПО ПОСТРОЕНИЮ, а не по случаю (D1295, 15 ноября 2026): здесь стояло `timeout`, и macOS 27.2.1
# поставила /usr/bin/timeout — свидетель стал печатать SKIP на обоих прогонах, прибор не выносил ему вердикта.
# Атака судит якорь и кавычки, а не конкретную команду: имени достаточно не существовать.
BIN=cs_absent_probe_tool
if command -v "$BIN" >/dev/null 2>&1; then
    echo "SKIP: $BIN есть на этой машине — признак молчит по построению, атака непроверяема"
    exit 0
fi
NODE=$(jq -nc --arg b "$BIN" '{command_absent:$b}')

fail=0
probe() { # $1=метка $2=команда
    echo "--- $1 ---"; printf '%s\n' "$2"
    echo "  вид, по которому идёт сопоставление: [$(ds_unquoted_command "$(ds_code_only "$(ds_shell_only "$2")")" | tr '\n' '~')]"
    ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$2" '{command:$c}')" ""
    local rc=$?
    echo "  предикат command_absent: rc=$rc"
    if [ "$rc" -eq 0 ]; then
        echo "  FAIL: признан вызовом. В команде нет ни одного исполнения $BIN — слово стоит"
        echo "        внутри двойных кавычек. Кавычку впрыснул ds_code_only из комментария."
        fail=1
    fi
}

probe "комментарий + печать строки" \
    "$(printf '# памятка\nprintf %s %s\n' "'%s\\n'" "\"$BIN не установлен\"")"
probe "комментарий + echo с точкой с запятой в строке" \
    "$(printf '# заметка\necho %s\n' "\"нет; $BIN недоступен\"")"

# Контроль 1: та же строка БЕЗ комментария — кавычки парны, признак обязан молчать.
CTRL_CMD=$(printf 'echo %s\n' "\"нет; $BIN недоступен\"")
ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$CTRL_CMD" '{command:$c}')" ""
C1=$?
echo "контроль 1 (без комментария): rc=$C1 — ожидается 1"
[ "$C1" -eq 0 ] && { echo "FAIL: контроль сломан, тест меряет не комментарий"; fail=1; }

# Контроль 2: настоящий вызов — признак обязан сработать, иначе тест ничего не различает.
ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "ls && $BIN 5 ls" '{command:$c}')" ""
C2=$?
echo "контроль 2 (настоящий вызов): rc=$C2 — ожидается 0"
[ "$C2" -ne 0 ] && { echo "FAIL: положительный контроль не сработал"; fail=1; }

# Достижимость: сквозной прогон и уровень enforcement.
P="$HOME/.claude/global-lessons/pattern-shell-portability.md"
CMD=$(printf '# памятка\nprintf %s %s\n' "'%s\\n'" '"timeout не установлен"')
if [ -f "$P" ]; then
    SIG=$(ds_evaluate "$P" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" "")
    E2E=$?
    echo "сквозной прогон: rc=$E2E signal=[$SIG]"
    if [ "$E2E" -eq 0 ]; then
        ENF=$(awk '/^detection_signals:[[:space:]]*\|/{f=1;next} f&&/^[^[:space:]]/{exit} f{print substr($0,3)}' "$P" \
              | jq -r --arg n "$SIG" '.[]? | select(.name==$n) | .enforcement // "hint"' 2>/dev/null)
        echo "enforcement: $ENF"
        [ "$ENF" = "deny" ] && { echo "FAIL: permissionDecision:deny на команду без вызова."; fail=1; }
    fi
else
    echo "достижимость: сквозной прогон пропущен (нет $P)"
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
