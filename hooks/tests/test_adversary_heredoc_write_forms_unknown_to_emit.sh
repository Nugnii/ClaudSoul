#!/usr/bin/env bash
# test_adversary_heredoc_write_forms_unknown_to_emit.sh
#
# АТАКА: словарь форм записи в emit() — перечень, а не правило. Три обычные формы
# оболочки в него не попали, и на каждой признак уровня deny молчит.
#
#   1) `| tee -a hooks/x.sh` — emit печатает СЛЕДУЮЩЕЕ слово после `tee`, то есть `-a`,
#      а сам путь стоит через одно и не печатается никогда.
#   2) `<<\EOF` — экранированный маркер (законная форма закавычивания, равна <<'EOF').
#      Правило открытия /<<-?[ ]*'?"?[A-Za-z_]/ обратной косой не знает, heredoc не
#      опознан вовсе.
#   3) `>| hooks/x.sh` — перекрытие noclobber. Слово `>|` проходит по ветке
#      /^>>?[^>]/, sub(/^>>?/) оставляет `|`, и целью печатается «|».
#
# Все три формы проверены настоящим bash прямо в тесте: запись происходит.
# Ожидание: rc=0 на каждой. Факт: rc=1 — страж слеп.
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
T=$(mktemp -d); mkdir -p "$T/hooks"

# $1=метка $2=скрипт для bash (проверка, что запись реальна) $3=имя файла $4=команда для предиката
check() {
    ( cd "$T" && printf '%s' "$2" > run.sh && bash run.sh >/dev/null 2>&1 )
    if [ ! -s "$T/$3" ]; then
        echo "SKIP-плечо $1: bash этой машины форму не отработал"
        return 0
    fi
    echo "--- $1 — bash записал в $3: [$(head -1 "$T/$3")] ---"
    printf '%s\n' "$4"
    ds_evaluate_node "$NODE" "Bash" "$(jq -nc --arg c "$4" '{command:$c}')" ""
    local rc=$?
    echo "предикат: rc=$rc"
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: запись в $3 состоялась, а цель не найдена — признак уровня deny молчит."
        fail=1
    fi
    : > "$T/$3"
}

check "tee -a" \
  "$(printf 'cat <<%s | tee -a hooks/a.sh >/dev/null\nstat -f %%%%z /tmp\nEOF\n' "'EOF'")" \
  "hooks/a.sh" \
  "$(printf 'cat <<%s | tee -a hooks/a.sh\nstat -f %%z /tmp\nEOF\n' "'EOF'")"

check "экранированный маркер <<\\EOF" \
  "$(printf 'cat > hooks/b.sh <<\\EOF\nstat -f %%%%z /tmp\nEOF\n')" \
  "hooks/b.sh" \
  "$(printf 'cat > hooks/b.sh <<\\EOF\nstat -f %%z /tmp\nEOF\n')"

check "перекрытие >|" \
  "$(printf 'cat <<%s >| hooks/c.sh\nstat -f %%%%z /tmp\nEOF\n' "'EOF'")" \
  "hooks/c.sh" \
  "$(printf 'cat <<%s >| hooks/c.sh\nstat -f %%z /tmp\nEOF\n' "'EOF'")"

# Положительный контроль: голый `tee` без флага цель находит — значит тест меряет флаг,
# а не «tee вообще».
ds_evaluate_node "$NODE" "Bash" \
  "$(jq -nc --arg c "$(printf 'cat <<%s | tee hooks/a.sh\nstat -f %%z /tmp\nEOF\n' "'EOF'")" '{command:$c}')" ""
CTRL=$?
echo "контроль (tee без -a): rc=$CTRL"
if [ "$CTRL" -ne 0 ]; then
    echo "FAIL: положительный контроль не сработал."
    fail=1
fi

[ "$fail" -eq 0 ] && { echo "PASS"; exit 0; }
exit 1
