#!/usr/bin/env bash
set -u
# СУДИТ: domains/shell-scripting.md
# probe_D1269 — расхождение отбора хука знаний рабочего дерева с коммитом починки D488 (199039cb) в контексте `commit`
#   сведено к одному коммиту: ed128ead (D507, «граф доменов раскрывает каждого родителя» — смена отбора объявлена в нём
#   намеренной). Ревизии зафиксированы, поэтому законные правки отбора после разбора пробу не красят: (1) код хуков между
#   199039cb и родителем ed128ead не менялся; (2) 199039cb против ed128ead расходится в `commit` и `edit` (положительный
#   контроль; держится на живом `domains/shell-scripting.md` с двумя родителями — оттого он в строке СУДИТ); (3) ed128ead
#   против ревизии разбора 53d7a871 совпадает — других смен до разбора нет. Сверка — машиной пробы D488 на ЗАФИКСИРОВАННОЙ
#   ревизии 87a2dd6c (снимки базы знаний и реестра сессий): правка пробы D488 эту не задевает (скептик opus, L3).
#   0 — так; 1 — нет; 2 — рамка не собралась (нет истории, нет якорей пробы D488).
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for r in 199039cb ed128ead 53d7a871 87a2dd6c; do git cat-file -e "$r^{commit}" 2>/dev/null || exit 2; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/probe_D488.sh"; git show 87a2dd6c:hooks/tests/fixtures/probe_D488.sh > "$P" 2>/dev/null || exit 2
mk() {  # <старая> <новая> <файл>: копия пробы D488 с подставленными ревизиями и контекстами `commit` и `edit`
    sed -e "s/^OLD_REV=0508b711\$/OLD_REV=$1/" -e "s/^FIX_REV=199039cb\$/FIX_REV=$2/" "$P" \
        | awk '/^CTX=\$\(cat <<EOF$/ { print; c = 1; next } c && /^EOF$/ { c = 0 } c && !/^(commit|edit)\t/ { next } { print }' > "$3"
    grep -q "^OLD_REV=$1\$" "$3" && grep -q "^FIX_REV=$2\$" "$3" && [ "$(grep -cE '^(commit|edit)	' "$3")" = 2 ]
}
mk 199039cb ed128ead "$W/a.sh" && mk ed128ead 53d7a871 "$W/b.sh" || { echo "якоря пробы D488 не найдены"; exit 2; }
bad=0
git diff --quiet 199039cb ed128ead~1 -- hooks ':!hooks/tests' || { echo "между 199039cb и ed128ead код хуков менялся"; bad=1; }
( CLAUDSOUL_REPO="$PWD" bash "$W/a.sh" > "$W/a.out" 2>&1; echo $? > "$W/a.rc" ) &
( CLAUDSOUL_REPO="$PWD" bash "$W/b.sh" > "$W/b.out" 2>&1; echo $? > "$W/b.rc" ) &
wait
# Копия пробы D488 не собрала рамку (нет реестра сессий, базы знаний, jq) — «не измерено», а не вердикт (скептик opus, M1).
grep -qx 2 "$W/a.rc" "$W/b.rc" && { echo "проба D488 не собрала рамку — сверка не исполнена"; exit 2; }
[ "$(cat "$W/a.rc")" = 1 ] && grep -q '^  commit: РАСХОЖДЕНИЕ' "$W/a.out" && grep -q '^  edit: РАСХОЖДЕНИЕ' "$W/a.out" \
    || { echo "199039cb против ed128ead не расходится (код $(cat "$W/a.rc")) — смена отбора не там"; bad=1; }
[ "$(cat "$W/b.rc")" = 0 ] || { echo "ed128ead против 53d7a871 расходится (код $(cat "$W/b.rc")) — смена не одна"; grep -A3 'РАСХОЖДЕНИЕ' "$W/b.out" | head -4; bad=1; }
exit "$bad"
