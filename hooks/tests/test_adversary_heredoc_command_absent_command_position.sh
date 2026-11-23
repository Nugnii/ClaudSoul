#!/usr/bin/env bash
# test_adversary_heredoc_command_absent_command_position.sh
#
# АТАКА: якорь «позиция команды» перечисляет символы `^ ; & | (` и не знает ключевых
# слов оболочки. После `do`, `then`, `else` и внутри группы `{ … }` стоит РОВНО та же
# позиция команды, и вызов оттуда падает кодом 127 точно так же.
#
# Механизм:
#   grep -qE "(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*NAME([[:space:]]|$)"
# Между `;` и именем стоит `do ` / `then ` — не разделитель и не присваивание, значит
# группа `(…=…)*` его не покрывает, и совпадения нет. Признак несёт enforcement:deny,
# и его молчание неотличимо от «нарушений нет» — ровно та цена, ради которой
# 8 сентября 2026 в якорь и добавляли присваивания.
#
# Второе плечо того же корня: ds_code_only режет строку от ЛЮБОЙ двойной кавычки перед
# `#` (sub(/(^|")[[:space:]]*#.*$/)). Обычное `grep -c "#" f` съедает весь остаток
# строки — вместе с настоящим вызовом, стоящим следом.
#
# Ожидание: rc=0 на каждом плече — вызов реален.
# Факт:     rc=1, признак уровня deny молчит.
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
    echo "--- $1 ---"; printf '  %s\n' "$2"
    # Доказательство, что вызов реален: этот же текст исполняется и падает 127.
    bash -c "$2" >/dev/null 2>&1
    local shrc=$?
    echo "  bash: код $shrc (127 = исполняемого нет, то есть $BIN действительно вызывался)"
    ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$2" '{command:$c}')" ""
    local rc=$?
    echo "  предикат command_absent: rc=$rc"
    if [ "$shrc" -eq 127 ] && [ "$rc" -ne 0 ]; then
        echo "  FAIL: вызов реален (оболочка вернула 127), признак уровня deny молчит."
        fail=1
    fi
}

probe "после do"            "for f in a; do $BIN 5 true; done"
probe "после then"          "if true; then $BIN 5 true; fi"
probe "внутри группы { }"   "{ $BIN 5 true; }"
probe "после кавычки с #"   "grep -c \"#\" /etc/hosts >/dev/null ; $BIN 5 true"

# Положительный контроль: та же лексема после `&&` — признак обязан сработать.
ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "true && $BIN 5 true" '{command:$c}')" ""
CTRL=$?
echo "контроль (после &&): rc=$CTRL — ожидается 0"
if [ "$CTRL" -ne 0 ]; then
    echo "FAIL: положительный контроль не сработал — тест меряет не позицию команды."
    fail=1
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
