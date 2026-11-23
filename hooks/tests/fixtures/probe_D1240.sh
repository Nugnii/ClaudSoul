#!/usr/bin/env bash
set -u
# СУДИТ: scripts/named-limits.py hooks/tests/test_named_limit_has_exit.sh hooks/tests/test_assert_no_sigpipe.sh hooks/tests/test_derived_counts_inventory.sh
# probe_D1240 — сканеры правила «каждый файл …» видят и новый НЕОТСЛЕЖИВАЕМЫЙ (не игнорируемый) файл, как его увидит CI
#   после коммита. Рамка настоящая: копия `named-limits.py` в песочном git-дереве; учтённый файл с пределом и условием
#   снятия, новый неотслеживаемый — с пределом без условия, игнорируемый — тоже без условия. Сканер обязан назвать
#   новый и не назвать игнорируемый. Свидетели реестра «всегда» берут универсум той же формой (`--others`).
#   0 — новый назван, игнорируемый нет, свидетели берут ту же форму; 1 — иначе; 2 — нет прибора, рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
N=scripts/named-limits.py
for f in "$N" hooks/tests/test_named_limit_has_exit.sh hooks/tests/test_assert_no_sigpipe.sh hooks/tests/test_derived_counts_inventory.sh; do
    [ -f "$f" ] || exit 2
done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
R="$W/r"; mkdir -p "$R/scripts" || exit 2
cp "$N" "$R/scripts/" || exit 2
git -C "$R" init -q 2>/dev/null || exit 2
printf '#!/usr/bin/env bash\n# НАЗВАННЫЙ ПРЕДЕЛ: проба учтённого. Условие снятия: никогда.\n' > "$R/scripts/old.sh"
printf 'ignored.sh\n' > "$R/.gitignore"
git -C "$R" add scripts/old.sh .gitignore 2>/dev/null || exit 2
printf '#!/usr/bin/env bash\n# НАЗВАННЫЙ ПРЕДЕЛ: новый файл без выхода.\n' > "$R/scripts/fresh.sh"
printf '#!/usr/bin/env bash\n# НАЗВАННЫЙ ПРЕДЕЛ: игнорируемый файл без выхода.\n' > "$R/ignored.sh"
out=$(cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/named-limits.py --no-exit 2>&1)
bad=0
grep -q 'fresh.sh' <<< "$out" || { echo "сканер не видит нового неотслеживаемого файла: ${out}"; bad=1; }
grep -q 'ignored.sh' <<< "$out" && { echo "сканер судит игнорируемый файл"; bad=1; }
grep -q 'old.sh' <<< "$out" && { echo "сканер назвал учтённый файл с условием снятия"; bad=1; }
# Владелец универсума стражей (`hooks/lib/universe-lib.sh`; его берут test_instrument_contract, test_md_trailing_newline,
# test_signal_has_counterexample — скептик opus по 52bd33e3, H1): новый неотслеживаемый инструмент в универсуме есть.
L="$PWD/hooks/lib/universe-lib.sh"
[ -f "$L" ] || exit 2
printf '#!/usr/bin/env bash\n' > "$R/scripts/brandnew.sh"
u=$(UNIVERSE_ROOT="$R" bash -c '. "$1"; universe_instruments_sh' _ "$L" 2>/dev/null)
grep -qx 'scripts/brandnew.sh' <<< "$u" || { echo "universe-lib: новый неотслеживаемый инструмент вне универсума: ${u}"; bad=1; }
grep -qx 'scripts/old.sh' <<< "$u" || { echo "контроль universe-lib: учтённый инструмент вне универсума"; bad=1; }
for t in hooks/tests/test_named_limit_has_exit.sh hooks/tests/test_assert_no_sigpipe.sh hooks/tests/test_derived_counts_inventory.sh; do
    grep -q 'ls-files --cached --others --exclude-standard\|"ls-files", "--cached", "--others", "--exclude-standard"' "$t" \
        || { echo "$t: универсум — голый git ls-files"; bad=1; }
done
exit "$bad"
