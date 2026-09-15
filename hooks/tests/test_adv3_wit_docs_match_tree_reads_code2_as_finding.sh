#!/usr/bin/env bash
# test_adv3_wit_docs_match_tree_reads_code2_as_finding.sh — после починки K6 потребитель test_docs_match_tree.sh читает код 2 инструментов документации («нечем проверить») как «нашёл расхождение» и краснеет без python3, где прежде был зелен.
#
# Результат: scripts/docs-inventory.sh и scripts/docs-duplicates.sh без python3 отвечают 2 (K6,
#            «сломался — говорить»), а hooks/tests/test_docs_match_tree.sh:22-29 знает два исхода —
#            0 и «не 0 = нашёл расхождение» — и не имеет гейта «SKIP: нет python3», который стоит у
#            обоих свидетелей. До K6 те же инструменты отвечали 0, и потребитель был зелен; теперь
#            он красен с ложным ярлыком «нашёл расхождение», то есть два смысла кода снова легли на
#            один провод — у читателя. Ожидание: в среде без python3 потребитель либо SKIP (0), либо
#            называет отказ инструмента отказом, а не находкой.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3 — среда без него и так живая"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CONSUMER="$REPO/hooks/tests/test_docs_match_tree.sh"
[ -f "$CONSUMER" ] || { echo "FAIL: нет $CONSUMER"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# PATH без python3: всё прочее — симлинками, чтобы среда отличалась ровно одним.
SB=$(mktemp -d)
B="$SB/bin"; mkdir -p "$B"
printf '%s\n' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        n=${f##*/}
        case "$n" in python|python3*) continue ;; esac
        [ -x "$f" ] && [ ! -e "$B/$n" ] && ln -s "$f" "$B/$n"
    done
done
PATH="$B" command -v python3 >/dev/null 2>&1 && { echo "FAIL: python3 остался в урезанном PATH"; exit 1; }

# --- T1: инструмент без python3 отвечает 2 и говорит об этом (починка K6 на месте) ----------------
OUT=$(cd "$REPO" && PATH="$B" bash scripts/docs-duplicates.sh 2>&1); RC=$?
{ [ "$RC" -eq 2 ] && grep -Fq 'нужен python3' <<< "$OUT"; } && ok || bad T1 "docs-duplicates без python3: rc=$RC — «${OUT}»"

# --- T2: потребитель в той же среде не краснеет ложной находкой ----------------------------------
OUT=$(cd "$REPO" && PATH="$B" bash "$CONSUMER" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T2 "test_docs_match_tree.sh без python3 красен: rc=$RC — $(grep -F 'FAIL' <<< "$OUT" | head -2 | tr '\n' ' ')"
grep -Fq 'нашёл расхождение' <<< "$OUT" && bad T2 "код 2 инструмента назван находкой: «нашёл расхождение»" || ok

echo ""
echo "adv3 docs-match-tree code-2 consumer tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
