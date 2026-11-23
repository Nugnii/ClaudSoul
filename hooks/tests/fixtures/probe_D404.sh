#!/usr/bin/env bash
# СУДИТ: scripts/measure-linux-parity.sh hooks/module-context-inject.sh
# probe_D404.sh — починка расхождений образа контейнера с раннером держится: рецепт замера ставит
# procps, python3-yaml, perl, ведёт набор от непривилегированного пользователя в C.UTF-8, а хук
# module-context-inject.sh ищет кириллический заголовок альтернацией (побайтовый mawk), а не скобкой.
# Судит РЕЦЕПТ и ХУК в своём дереве; последний прогон набора в контейнере
# (`state/measurement-runs/suite-linux.out`) мерит строка реестра `suite-linux`, контейнер здесь
# не запускается.
# Коды: 0 — держится; 1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
R="$REPO/scripts/measure-linux-parity.sh"; H="$REPO/hooks/module-context-inject.sh"
T="$REPO/hooks/tests/test_case_folding_portable.sh"
[ -f "$R" ] && [ -f "$H" ] && [ -f "$T" ] || exit 2
inst=$(grep -E 'apt-get install' "$R") || { echo "рецепт не ставит пакеты"; exit 1; }
for p in python3-yaml perl procps; do
    case " $inst " in *" $p "*) ;; *) echo "рецепт не ставит $p"; exit 1 ;; esac
done
grep -q 'su tester -c' "$R" || { echo "набор идёт не от непривилегированного пользователя"; exit 1; }
grep -q 'LANG=C.UTF-8 bash run_all.sh' "$R" || { echo "набор идёт не в C.UTF-8"; exit 1; }
# хук: заголовок раздела с кириллицей читается альтернацией, не скобочным классом
grep -qE '\(Б\|б\)изнес-правила' "$H" || { echo "заголовок раздела не альтернацией"; exit 1; }
! grep -qE '\[Бб\]изнес' "$H" || { echo "скобочный класс Бб вернулся"; exit 1; }
# поведение: сторож свёртки регистра (sed/grep/awk, побайтовый разбор) зелен
out=$(bash "$T" 2>&1) || { echo "сторож свёртки регистра красен"; exit 1; }
exit 0
