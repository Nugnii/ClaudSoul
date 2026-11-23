#!/usr/bin/env bash
# СУДИТ: дерево
# (D1222: проба зовёт только тест дерева `test_multibyte_var_boundary.sh`, а он судит отрицательное свойство всех файлов —
#  выхолащивание стража карты гарантий делает его вернее, и прежний предмет `hooks/guarantee-map-guard.sh` числил пробу
#  ложно-зелёной.)
# probe_D1177 — комментарии стража карты гарантий, показывающие форму переменной («$README», «$x»), помечены `mb-ok`,
# и тест дерева на подстановку вплотную к не-ASCII зелёный. Красная (1), пока тест красный; 2 — теста нет.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="$R/hooks/tests/test_multibyte_var_boundary.sh"
[ -f "$T" ] || exit 2
bash "$T" >/dev/null 2>&1 || { echo "test_multibyte_var_boundary красный"; exit 1; }
exit 0
