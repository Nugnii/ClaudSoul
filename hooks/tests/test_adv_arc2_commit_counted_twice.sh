#!/usr/bin/env bash
# test_adv_arc2_commit_counted_twice.sh — атака на единицу счёта ретро-прогона
# scripts/adversary-replay.sh:170-243.
#
# ЧТО ДОКАЗЫВАЕТСЯ. Комментарий сцепки объявляет: «Один коммит — один вызов по
# построению, и отдельный дедуп больше не нужен: ЕДИНИЦА СЧЁТА ЕСТЬ КОММИТ».
# Утверждение верно ВНУТРИ одной расшифровки и неверно снаружи: цикл идёт
# `for TR in "$CORPUS"/*.jsonl`, а `$COMMITS` — ВСЯ история репозитория, одна и та же
# для каждой итерации. Ни один счётчик (`BIG`, `RUN`, `NORUN`) между итерациями не
# помнит, какие sha уже посчитаны; переменная `SEEN=""` (строка 172) объявлена и не
# используется ни разу — это след снятого дедупа.
#
# Значит, если ДВЕ расшифровки имеют вызов `git commit` в окне [-5; +300] одного и того
# же коммита (параллельные сессии одного проекта — обычное дело), этот единственный
# коммит попадает в выборку ДВАЖДЫ, и вердикт ему выносится ДВА РАЗА, по префиксам
# разных сессий. Одно событие мира даёт «крупных коммитов: 2, без прогона: 1 (50%)».
# Число правдоподобно и неверно, и оно — первый порог лестницы ADR-015.
#
# ДОСТИЖИМОСТЬ ИЗМЕРЕНА на живом корпусе 9 сентября 2026 (55 расшифровок, 1071 коммит,
# 896 настоящих вызовов): из 767 коммитов, сцепившихся хотя бы с одной расшифровкой,
# 2 сцепились с ДВУМЯ разными — то есть выборка уже сегодня содержит 2 лишних учёта.
# Реестр сессий той же машины показывал 7 параллельных сессий, поэтому величина
# ограничена не механизмом, а привычкой работать по одной сессии за раз.
set -uo pipefail

REPO_REAL="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

T1=1788820132;  TS_A="2026-09-07T22:28:52.000Z"      # вызов сессии A
TS_B="2026-09-07T22:28:57.000Z"                       # вызов сессии B, +5 c
TS_RUN="2026-09-07T22:28:50.000Z"                     # прогон противника — только в B
C_TS=1788820142                                       # коммит, +10 c: в окне ОБОИХ вызовов
SEED_EPOCH=1788700000

make_repo() {
    local r="$1"
    mkdir -p "$r/hooks/lib" "$r/scripts"
    cp "$REPO_REAL/hooks/lib/adversary-run-lib.sh" "$r/hooks/lib/"
    cp "$REPO_REAL/hooks/portable-lib.sh"          "$r/hooks/"
    cp "$REPO_REAL/hooks/command-scope-lib.sh"     "$r/hooks/"
    git -C "$r" init -q 2>/dev/null
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    git -C "$r" add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE="@$SEED_EPOCH +0000" GIT_COMMITTER_DATE="@$SEED_EPOCH +0000" \
        git -C "$r" commit -q -m seed 2>/dev/null
}
commit_big() {
    local r="$1" e="$2" p="$3" i
    for i in 1 2 3 4 5 6; do seq 1 30 > "$r/$p$i.py"; done
    git -C "$r" add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE="@$e +0000" GIT_COMMITTER_DATE="@$e +0000" \
        git -C "$r" commit -q -m "big $p" 2>/dev/null
}
bash_call() { jq -cn --arg t "$1" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Bash", input:{command:"git commit -m x"}}]}}'; }
skill_call() { jq -cn --arg t "$1" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Skill", input:{skill:"adversary"}}]}}'; }
replay() {
    ( env CLAUDSOUL_REPO="$1" ADVERSARY_REPLAY_CORPUS="$2" ADVERSARY_REPLAY_CASES="$TMP/cases.txt" \
        bash "$REPO_REAL/scripts/adversary-replay.sh" run 2>&1 )
}

# Один коммит. Две параллельные сессии, у каждой свой вызов `git commit` в его окне.
# В сессии B прогон противника был, в сессии A — нет.
R="$TMP/repo"; CORP="$TMP/corpus"; mkdir -p "$CORP"
make_repo "$R"
commit_big "$R" "$C_TS" a
bash_call "$TS_A"                    >  "$CORP/sess-a.jsonl"
{ skill_call "$TS_RUN"; bash_call "$TS_B"; } > "$CORP/sess-b.jsonl"

OUT=$(replay "$R" "$CORP")

# --- T0: положительный контроль — прибор вообще нашёл предмет ---
case "$OUT" in
    *"мерить нечего"*) bad "T0" "kontrol provalen: krupnyj kommit ne popal v vyborku vovse: $OUT" ;;
    *) ok ;;
esac

# --- T1: коммит ОДИН, значит и событий ровно одно ---
case "$OUT" in
    *"крупных кодовых коммитов: 1"*) ok ;;
    *"крупных кодовых коммитов: 2"*) bad "T1" "odin kommit poschitan DVAZHDY: schetchiki ne pomnyat sha mezhdu rasshifrovkami (SEEN ob'yavlena i ne ispol'zuetsya): $OUT" ;;
    *) bad "T1" "neozhidannoe chislo kommitov: $OUT" ;;
esac

# --- T2: один и тот же коммит не может быть одновременно «с прогоном» и «без» ---
case "$OUT" in
    *"без адверсариального прогона: 1"*)
        case "$OUT" in
            *"с прогоном: 1"*) bad "T2" "odin kommit lezhit srazu v chislitele i v znamenatele: dolya 50% poluchena na ODNOM sobytii mira: $OUT" ;;
            *) ok ;;
        esac ;;
    *) ok ;;
esac

echo ""
echo "adv-arc2 commit-counted-twice tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
