#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh hooks/lib/adversary-run-lib.sh hooks/portable-lib.sh scripts/adversary-replay.sh
# test_adv_arc2_empty_cases_shell_error.sh — атака на хвост вывода ретро-прогона,
# scripts/adversary-replay.sh:258-259.
#
# ЧТО ДОКАЗЫВАЕТСЯ.
#
#     TOTAL_CASES=$(grep -c . "$CASES" 2>/dev/null || echo 0)
#     [ "$TOTAL_CASES" -gt 40 ] && echo "  … показаны 40 из $TOTAL_CASES …"
#
# `grep -c` на ПУСТОМ файле печатает `0` И возвращает код 1 (ничего не найдено).
# Код 1 запускает `|| echo 0`, и подстановка склеивает ДВА значения: `TOTAL_CASES`
# становится строкой «0\n0». Следующая же строка сравнивает её как число и падает:
#     adversary-replay.sh: line 259: [: 0
#     0: integer expression expected
#
# Ветка достижима ровно тогда, когда прибор говорит ХОРОШЕЕ: `CASES` пуст, когда ни один
# крупный коммит не ушёл без прогона (`NORUN = 0`). То есть в выводе замера, публикуемого
# как основание лестницы ADR-015, диагностика оболочки появляется на самом благополучном
# из исходов и ни на каком другом — а читатель, увидев ошибку интерпретатора посреди
# чисел, не может отличить «прибор досчитал» от «прибор упал на полпути».
#
# Достижимость: воспроизводится в этом дереве на любом наборе, где `NORUN=0` и `BIG>0`;
# та же строка ошибки печатается в прогоне соседнего теста
# hooks/tests/test_adv_arc2_join_takes_call_after_commit.sh.
set -uo pipefail

REPO_REAL="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TS_RUN="2026-09-07T22:20:00.000Z"
TS_CALL="2026-09-07T22:28:52.000Z"
C_TS=1788820142
SEED_EPOCH=1788700000

R="$TMP/repo"; CORP="$TMP/corpus"; mkdir -p "$CORP" "$R/hooks/lib" "$R/scripts"
cp "$REPO_REAL/hooks/lib/adversary-run-lib.sh" "$R/hooks/lib/"
cp "$REPO_REAL/hooks/portable-lib.sh"          "$R/hooks/"
cp "$REPO_REAL/hooks/command-scope-lib.sh"     "$R/hooks/"
git -C "$R" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_empty_cases_shell_error.sh:$LINENO" >&2; exit 1; }
git -C "$R" config user.email t@e; git -C "$R" config user.name t
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_empty_cases_shell_error.sh:$LINENO" >&2; exit 1; }
GIT_AUTHOR_DATE="@$SEED_EPOCH +0000" GIT_COMMITTER_DATE="@$SEED_EPOCH +0000" \
    git -C "$R" commit -q -m seed 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_empty_cases_shell_error.sh:$LINENO" >&2; exit 1; }
for i in 1 2 3 4 5 6; do seq 1 30 > "$R/a$i.py"; done
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_empty_cases_shell_error.sh:$LINENO" >&2; exit 1; }
GIT_AUTHOR_DATE="@$C_TS +0000" GIT_COMMITTER_DATE="@$C_TS +0000" \
    git -C "$R" commit -q -m big 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_empty_cases_shell_error.sh:$LINENO" >&2; exit 1; }

# Прогон был ДО вызова коммита → NORUN=0 → файл случаев пуст.
{ jq -cn --arg t "$TS_RUN"  '{timestamp:$t, message:{content:[{type:"tool_use",name:"Skill",input:{skill:"adversary"}}]}}'
  jq -cn --arg t "$TS_CALL" '{timestamp:$t, message:{content:[{type:"tool_use",name:"Bash",input:{command:"git commit -m x"}}]}}'
} > "$CORP/sess-1.jsonl"

OUT=$( env CLAUDSOUL_REPO="$R" ADVERSARY_REPLAY_CORPUS="$CORP" ADVERSARY_REPLAY_CASES="$TMP/cases.txt" \
       bash "$REPO_REAL/scripts/adversary-replay.sh" run 2>&1 )

# --- T0: контроль — ветка достигнута, случаев «без прогона» нет ---
case "$OUT" in
    *"без адверсариального прогона: 0"*) ok ;;
    *) bad "T0" "kontrol provalen: vetka pustogo spiska sluchaev ne dostignuta: $OUT" ;;
esac

# --- T1: вывод прибора не содержит диагностики оболочки ---
case "$OUT" in
    *"integer expression expected"*)
        bad "T1" "pribor pechataet oshibku interpretatora v svoem vyvode: grep -c na pustom fajle vozvrashchaet 1, i '|| true' skleivaet TOTAL_CASES v '0\\n0': $OUT" ;;
    *) ok ;;
esac

echo ""
echo "adv-arc2 empty-cases tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
