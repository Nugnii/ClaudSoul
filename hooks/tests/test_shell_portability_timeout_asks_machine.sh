#!/usr/bin/env bash
# СУДИТ: knowledge/pattern-shell-portability.md hooks/detection-signals-lib.sh
# test_shell_portability_timeout_asks_machine.sh — отказ «команды нет на этой машине» на `timeout <число>` спрашивает
# машину, а не тип системы (D1302, корень R5).
#
# Повод: обновление macOS 27.2.1 (15 ноября 2026) поставило /usr/bin/timeout, а признак `fails_on_this_machine` знания
# `pattern-shell-portability` держал форму `timeout <число>` под предикатом `os_is: bsd` и отбивал вызов, который
# исполнился бы. Факт «команды здесь нет» спрашивают у машины `absent_on_this_machine` (`command_absent`) и хук
# `hooks/absent-tool-guard.sh` — у факта три владельца, и третий машину не спрашивал.
#
# T1 — на машине, где `timeout` есть, ни одна позиция снятой формы (начало, `$(`, обратные кавычки, `;`, `&&`, `|`,
#      `(`) и ни один ключ отказа не получают;
# T2 — с PATH без `timeout` те же команды получают отказ `absent_on_this_machine` (отказ прежний — положительный контроль);
# T3 — на BSD формы, которые здесь правда падают (`head -n -1`), отказ `fails_on_this_machine` получают по-прежнему.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/detection-signals-lib.sh"; K="$ROOT/knowledge/pattern-shell-portability.md"
[ -f "$LIB" ] && [ -f "$K" ] || { echo "FAIL: нет $LIB или $K"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
sig() { # <PATH> <команда> → имя сработавшего признака либо пусто
    PATH="$1" bash -c '. "$0"; ds_evaluate "$1" Bash "$(jq -nc --arg c "$2" "{command:\$c}")" ""' "$LIB" "$K" "$2" 2>/dev/null
}
# Каталог команд без `timeout` — общий владелец построения (`hooks/tests/path-without.sh`), не своя копия цикла.
. "$ROOT/hooks/tests/path-without.sh"
FARM="$T/bin"; path_without "$FARM" timeout gtimeout || { echo "FAIL: подготовка — каталог без timeout"; exit 1; }

if command -v timeout >/dev/null 2>&1; then
    # Все позиции, которые покрывала снятая форма (`^ ; & | ( $( \``), и ключи: частичный возврат формы под
    # `os_is: bsd` тоже ловится (скептик opus по 8e25f5b2, M1 — мутанты «только обратные кавычки», «после ; & |»,
    # «с ключом» проходили на двух образцах).
    for c in "timeout 5 true" 'x=$(timeout 5 true)' 'x=`timeout 5 true`' "cd /tmp && timeout 5 true" "true; timeout 5 true" \
             "true | timeout 5 cat" "(timeout 5 true)" "timeout -s KILL 5 true" "timeout --foreground 5 true"; do
        s=$(sig "$PATH" "$c"); [ -z "$s" ] && ok || bad T1 "«${c}» при /usr/bin/timeout получил отказ: $s"
    done
    # Дефект стоял под предикатом «система BSD»: на GNU нога T1 зелена и на прежнем знании (скептик, L4).
    [ "$(uname -s)" = Darwin ] || echo "  T1 различает только на BSD: дефект D1302 стоял под os_is: bsd"
else
    echo "  T1 не судится: на этой машине timeout нет"
fi
for c in "timeout 5 true" 'x=$(timeout 5 true)' "cd /tmp && timeout 5 true" "true; timeout 5 true"; do
    s=$(sig "$FARM" "$c"); [ "$s" = absent_on_this_machine ] && ok || bad T2 "«${c}» без timeout: ждали absent_on_this_machine, получено «${s}»"
done
if [ "$(uname -s)" = Darwin ]; then
    s=$(sig "$PATH" "printf 'a\nb\n' | head -n -1"); [ "$s" = fails_on_this_machine ] && ok \
        || bad T3 "«head -n -1» на BSD: ждали fails_on_this_machine, получено «${s}»"
else
    echo "  T3 не судится: не BSD"
fi
echo "shell portability timeout: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
