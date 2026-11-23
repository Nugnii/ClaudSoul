#!/usr/bin/env bash
set -u
# СУДИТ: scripts/project-graph.py .claude-docs/modules/project-graph.md hooks/command-scope-lib.sh
# probe_D1252 — утверждение карты о чужой функции `executable_part` совпадает с её поведением: подстановка `$(…)` в
#   двойных кавычках остаётся кодом (`x="$(fn "$arg")"` → `fn` на месте), а литерал программы после `-c` вырезается
#   (`bash -c "fn arg"` → `fn` нет). Носители — комментарий `scripts/project-graph.py` и описание модуля: оба не
#   называют прежнее «вырезает вместе с `$(…)`» поведением функции и оба называют литерал после `-c`.
#   0 — поведение функции то, что названо, и оба носителя называют его; 1 — расходятся; 2 — нет функции или носителей.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
L=hooks/command-scope-lib.sh; P=scripts/project-graph.py; M=.claude-docs/modules/project-graph.md
for f in "$L" "$P" "$M"; do [ -f "$f" ] || exit 2; done
sub=$(bash -c '. "$1"; executable_part "x=\"\$(fn \"\$arg\")\""' _ "$L" 2>/dev/null) || exit 2
prog=$(bash -c '. "$1"; executable_part "bash -c \"fn arg\""' _ "$L" 2>/dev/null) || exit 2
bad=0
grep -qw fn <<< "$sub" || { echo "функция вырезала \$(…) в кавычках: «${sub}» — описание должно это назвать"; bad=1; }
grep -qw fn <<< "$prog" && { echo "функция не вырезала литерал после -c: «${prog}»"; bad=1; }
for f in "$P" "$M"; do
    grep -q 'executable_part.*вырезает кавычки ЦЕЛИКОМ, вместе с\|`executable_part` вырезает кавычки вместе с `\$(…)`' "$f" \
        && { echo "$f: снова называет поведением функции «вырезает вместе с \$(…)»"; bad=1; }
    grep -q 'после `-c`' "$f" || { echo "$f: не называет литерал программы после -c"; bad=1; }
done
exit "$bad"
