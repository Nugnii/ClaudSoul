#!/usr/bin/env bash
# test_adversary_heredoc_unclosed_marker_poisons_rest.sh
#
# АТАКА: состояние `inside` в awk не сбрасывается никогда, кроме точного совпадения
# строки с маркером. Форма `<<-MARK` разрешает закрывать тело маркером С ОТСТУПОМ ИЗ
# ТАБУЛЯЦИЙ — bash его принимает, awk нет. `inside` остаётся 1 до конца команды, и ВСЕ
# следующие heredoc в той же команде становятся невидимы.
#
# Механизм. Правило `inside && $0 == mark { inside = 0; next }` сравнивает строку целиком,
# а `<<-` отступ снимает только bash. Дальше `inside { next }` глотает остаток команды,
# включая `cat > hooks/x.sh <<ZZ`. Это не «форма редкая»: у ослепления цена ровно того
# рода, что уже измерен в шапке предиката (1 найденная цель на 1357 команд).
#
# Ожидание: rc=0 — вторая часть команды пишет в hooks/x.sh.
# Факт:     rc=1, признак уровня deny молчит на настоящей записи в хук.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

TARGET_RX='(hooks|scripts)/[^ ]*\.(sh|bash|py)'
NODE=$(jq -nc --arg rx "$TARGET_RX" '{heredoc_target_regex:$rx}')

# «-» перед EOF означает: bash снимет табуляции и с тела, и с терминатора.
CMD=$(printf 'cat <<-EOF > /tmp/note.txt\n\tзаметка\n\tEOF\ncat > hooks/x.sh <<%s\nstat -f %%z /tmp\nZZ\n' "'ZZ'")

echo "--- команда (терминатор первого heredoc с табуляцией) ---"
printf '%s\n' "$CMD" | cat -A 2>/dev/null | sed 's/\$$//' || printf '%s\n' "$CMD"
echo "---------------------------------------------------------"

# Проверка формы настоящим bash: обе записи обязаны состояться.
T=$(mktemp -d); mkdir -p "$T/hooks"
( cd "$T" && printf 'cat <<-EOF > note.txt\n\tзаметка\n\tEOF\ncat > hooks/x.sh <<%s\nstat -f %%%%z /tmp\nZZ\n' "'ZZ'" > r.sh && bash r.sh )
echo "bash: note.txt=[$(cat "$T/note.txt" 2>/dev/null)] hooks/x.sh=[$(cat "$T/hooks/x.sh" 2>/dev/null)]"
[ -s "$T/hooks/x.sh" ] || { echo "SKIP: форма <<- не отработала в этом bash"; exit 0; }

ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$CMD" '{command:$c}')" ""
RC=$?
echo "предикат heredoc_target_regex: rc=$RC (0 = нашёл цель)"

fail=0
if [ "$RC" -ne 0 ]; then
    echo "FAIL: цель hooks/x.sh не найдена. Терминатор '\\tEOF' не равен 'EOF', inside остался 1,"
    echo "      и вторая половина команды пропущена целиком."
    fail=1
fi

# Второе плечо того же корня: тело первого heredoc вообще без терминатора.
CMD2=$(printf 'cat <<%s > /tmp/note.txt\nзаметка\ncat > hooks/x.sh <<%s\nstat -f %%z /tmp\nZZ\n' "'NEVERCLOSED'" "'ZZ'")
ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$CMD2" '{command:$c}')" ""
RC2=$?
echo "плечо 2 (маркер не закрыт вовсе): rc=$RC2 — здесь молчание ЗАКОННО, bash тоже не закроет"

# Положительный контроль: два heredoc подряд с обычным терминатором — цель обязана найтись.
CMD3=$(printf 'cat <<%s > /tmp/note.txt\nзаметка\nEOF\ncat > hooks/x.sh <<%s\nstat -f %%z /tmp\nZZ\n' "'EOF'" "'ZZ'")
ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$CMD3" '{command:$c}')" ""
CTRL=$?
echo "контроль (терминатор без отступа): rc=$CTRL"
if [ "$CTRL" -ne 0 ]; then
    echo "FAIL: положительный контроль не сработал — тест меряет не отступ терминатора."
    fail=1
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
