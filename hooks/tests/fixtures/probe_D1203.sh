#!/usr/bin/env bash
# СУДИТ: hooks/tests/run_all.sh
# probe_D1203 — правка реестра `.tsv`, который называет тест, выбирает этот тест в выборочном прогоне
# (`run_all.sh --changed`). Выбор по изменённым файлам разбирает только `*.sh|*.py` (`hooks/tests/run_all.sh`, функция
# `_changed_tests`), и правка реестра — понятий читателей, замеров, чисел документов — не выбирала ни одного своего
# теста сверх списка «всегда»: 31 октября 2026 так 7 реестров из 7 (найдено при D1149). Состав выборки спрашивается
# режимом `--list` (ничего не исполняет). Учёт `.claude-docs/dep-index.tsv` в счёт не идёт: он выход прибора, а не
# реестр, его правка — следствие правки кода, выбравшей свои тесты (решение при починке, 4 ноября 2026; 6 реестров).
# Красная (1), пока правка хоть одного такого реестра выбирает только список «всегда»; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
RA="$R/hooks/tests/run_all.sh"
[ -f "$RA" ] || exit 2
command -v git >/dev/null 2>&1 || exit 2
always=$(CHANGED_FILES="none-$$.txt" bash "$RA" --list 2>/dev/null | grep -v '^выборочный' | sort) || exit 2
[ -n "$always" ] || exit 2
lost=""; n=0
for f in $(git -C "$R" ls-files '*.tsv'); do
    [ "$f" = .claude-docs/dep-index.tsv ] && continue
    b=$(basename "$f")
    grep -qlF "$b" "$R"/hooks/tests/test_*.sh 2>/dev/null || continue
    n=$((n + 1))
    sel=$(CHANGED_FILES="$f" bash "$RA" --list 2>/dev/null | grep -v '^выборочный' | sort)
    [ "$sel" = "$always" ] && lost="$lost $f"
done
[ "$n" -gt 0 ] || exit 2
[ -z "$lost" ] || { echo "правка реестра не выбирает его тестов (из $n):$lost"; exit 1; }
echo "правка каждого из $n реестров выбирает его тесты"
exit 0
