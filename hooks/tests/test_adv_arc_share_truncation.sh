#!/usr/bin/env bash
# СУДИТ: scripts/adversary-before-commit.sh
# test_adv_arc_share_truncation.sh — атака на арифметику доли в
# scripts/adversary-before-commit.sh:97,111.
#
# ЧТО ДОКАЗЫВАЕТСЯ. Доля считается целочисленно и сравнивается со строгим порогом:
#
#     SHARE=$(( NORUN * 100 / TOTAL ))
#     if [ "$SHARE" -gt 50 ]; then  ... находка ...
#     echo "  — правило исполняется в большинстве случаев"
#
# Деление в оболочке усекает. 101 из 200 — это большинство (50,5%), а `101*100/200`
# даёт ровно 50, порог `-gt 50` не срабатывает, и замер печатает противоположный вывод:
# «правило исполняется в большинстве случаев» с кодом 0. Между тем большинство случаев
# ушло в коммит БЕЗ прогона.
#
# Это не косметика: код возврата 1 — единственный способ, которым этот замер сообщает
# находку бегуну (`scripts/measurement-due.sh`), и порог «выше половины» — первый из трёх
# порогов ADR-015 на подъём уровня принуждения. Полоса, в которой вывод обратный истине,
# начинается с TOTAL = 101 и с ростом знаменателя не исчезает.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

MCMD=$(awk -F'\t' '$1=="adversary-before-commit"{print $3}' "$REPO/scripts/measurements.tsv")
[ -n "$MCMD" ] || { echo "SKIP: stroki adversary-before-commit net v scripts/measurements.tsv"; exit 0; }

run() { ( cd "$REPO" && env STATE_DIR="$TMP/$1" ADVERSARY_COMMIT_MIN_N=20 bash -c "$MCMD" 2>&1 ); }
rc()  { ( cd "$REPO" && env STATE_DIR="$TMP/$1" ADVERSARY_COMMIT_MIN_N=20 bash -c "$MCMD" >/dev/null 2>&1 ); echo $?; }

# $1 = каталог, $2 = сколько said (без прогона), $3 = сколько satisfied (с прогоном)
fill() {
    local d="$TMP/$1"; mkdir -p "$d"; local f="$d/detection-sid-1.jsonl"; : > "$f"
    local i=0
    while [ "$i" -lt "$2" ]; do
        printf '{"ts":"2026-09-09T00:00:00Z","guard":"code-review-reminder","act":"said","sig":"n%s"}\n' "$i" >> "$f"
        i=$(( i + 1 ))
    done
    i=0
    while [ "$i" -lt "$3" ]; do
        printf '{"ts":"2026-09-09T00:00:00Z","guard":"code-review-reminder","act":"satisfied","sig":"y%s"}\n' "$i" >> "$f"
        i=$(( i + 1 ))
    done
}

# 101 из 200 ушли без прогона — большинство.
fill half 101 99
OUT=$(run half); RC=$(rc half)

# --- T0: контроль — знаменатель собран верно ---
case "$OUT" in
    *"всего: 200"*"без адверсариального прогона: 101"*) ok ;;
    *) bad "T0" "kontrol provalen, znamenatel sobran ne tak: $OUT" ;;
esac

# --- T1: большинство ушло без прогона — вывод «правило исполняется» недопустим ---
case "$OUT" in
    *"правило исполняется в большинстве случаев"*)
        bad "T1" "101 iz 200 ushli bez progona, a zamer pechataet <pravilo ispolnyaetsya v bolshinstve sluchaev>" ;;
    *) ok ;;
esac

# --- T2: находка обязана сообщаться КОДОМ возврата (тот же контракт, что у T2 штатного теста) ---
if [ "$RC" = "1" ]; then ok
else bad "T2" "dolya vyshe poloviny, a kod vozvrata $RC: begun otmetit zamer chistym"; fi

# --- T3: отрицательный контроль — на 102 из 200 порог всё же срабатывает ---
# Без него T1/T2 неотличимы от «замер вообще не умеет находить».
fill over 102 98
if [ "$(rc over)" = "1" ]; then ok
else bad "T3" "kontrol provalen: dazhe 102 iz 200 ne dayut nahodki, test merit ne to"; fi

echo ""
echo "adv-arc share-truncation tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
