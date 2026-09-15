#!/usr/bin/env bash
# test_adversary_heredoc_target_path_with_space.sh
#
# АТАКА: цель добывается разбиением по пробелам, поэтому закавыченный путь С ПРОБЕЛОМ
# теряется. Корень этого репозитория — «/Users/user/My Project/ClaudSoul», то есть
# признак слеп на собственном дереве при записи по абсолютному пути.
#
# Механизм. emit() делает split(part, w, /[[:space:]]+/) и печатает w[i+1] после `>`.
# Для `cat > "/…/My Project/ClaudSoul/hooks/x.sh" <<EOF` первым словом после `>` идёт
# `"/…/My`, а хвост `Project/ClaudSoul/hooks/x.sh"` не печатается вовсе. Кавычки
# разбору цели неизвестны — ни одна из трёх нормализаций (ds_unquoted_command,
# ds_code_only, ds_shell_only) сюда не подключена.
#
# Ожидание: rc=0 — heredoc пишет ровно в hooks/x.sh этого репозитория.
# Факт:     rc=1, отказ уровня deny молчит на настоящем нарушении.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

TARGET_RX='(hooks|scripts)/[^ ]*\.(sh|bash|py)'
NODE=$(jq -nc --arg rx "$TARGET_RX" '{heredoc_target_regex:$rx}')

# Форма проверена настоящим bash: запись действительно происходит.
T=$(mktemp -d); mkdir -p "$T/My Project/repo/hooks"
( cd "$T" && printf 'cat > "%s/My Project/repo/hooks/x.sh" <<%s\nstat -f %%%%z /tmp\nEOF\n' "$T" "'EOF'" > w.sh && bash w.sh )
echo "bash записал: [$(cat "$T/My Project/repo/hooks/x.sh" 2>/dev/null)]"
[ -s "$T/My Project/repo/hooks/x.sh" ] || { echo "SKIP: форма не отработала в этом bash"; exit 0; }

fail=0
probe() { # $1=метка $2=команда
    ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$2" '{command:$c}')" ""
    local rc=$?
    echo "--- $1 (rc=$rc) ---"; printf '%s\n' "$2"
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: цель НЕ найдена, хотя heredoc пишет в hooks/. Признак уровня deny молчит."
        fail=1
    fi
}

probe "абсолютный путь с пробелом (корень этого репозитория)" \
    "$(printf 'cat > "/Users/user/My Project/ClaudSoul/hooks/x.sh" <<%s\nstat -f %%z /tmp\nEOF\n' "'EOF'")"
probe "относительный путь с пробелом" \
    "$(printf 'cat > "my dir/hooks/x.sh" <<%s\nstat -f %%z /tmp\nEOF\n' "'EOF'")"

# Контроль: тот же путь без пробела — цель обязана находиться, иначе тест меряет не то.
ds_evaluate_node "$NODE" "Bash" \
    "$(jq -nc --arg c "$(printf 'cat > /Users/user/MyProject/ClaudSoul/hooks/x.sh <<%s\nstat -f %%z /tmp\nEOF\n' "'EOF'")" '{command:$c}')" ""
CTRL=$?
echo "контроль (тот же путь без пробела): rc=$CTRL"
if [ "$CTRL" -ne 0 ]; then
    echo "FAIL: положительный контроль не сработал — тест не различает пробел и что-то иное."
    fail=1
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
