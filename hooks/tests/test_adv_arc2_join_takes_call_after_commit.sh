#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh hooks/lib/adversary-run-lib.sh hooks/portable-lib.sh scripts/adversary-replay.sh
# test_adv_arc2_join_takes_call_after_commit.sh — атака на НОВУЮ сцепку
# scripts/adversary-replay.sh:184-195 (переписана 9 сентября 2026, класс C).
#
# ЧТО ДОКАЗЫВАЕТСЯ. Правило объявлено словами: «коммит породил ПОСЛЕДНИЙ вызов,
# случившийся ДО него… берётся вызов с наименьшим НЕОТРИЦАТЕЛЬНЫМ зазором; небольшое
# окно "до" оставлено на расхождение часов». Код правила не исполняет:
#
#     best=""; bestgap=-1
#     ...
#     if (gap >= -wb && gap <= wa) { if (bestgap < 0 || gap < bestgap) {...} }
#
# `-1` служит признаком «ещё ничего не выбрано» И одновременно является ЗАКОННЫМ
# значением зазора: окно `wb=5` пускает зазоры -1..-5, то есть вызовы, случившиеся
# ПОЗЖЕ коммита. Как только такой кандидат попал в `bestgap`, условие `bestgap < 0`
# остаётся истинным навсегда, и дальше берётся любой следующий кандидат подряд.
# Вызовы идут в хронологическом порядке (номер строки расшифровки), поэтому зазор
# УБЫВАЕТ с ростом j — и отрицательный кандидат приходит ПОСЛЕДНИМ и всегда побеждает
# верный, положительный.
#
# Итог: вердикт снимается с вызова, который случился ПОСЛЕ коммита, а его префикс
# расшифровки длиннее — в него попадает прогон противника, которого в момент коммита
# ещё не было. Число «с прогоном» завышено, «без прогона» занижено. Это та же беда,
# ради которой сцепку переписывали (класс C), вошедшая через другую дверь: не через
# выбор «самого раннего», а через столкновение сентинела с законным значением.
#
# ДОСТИЖИМОСТЬ ИЗМЕРЕНА на живом корпусе 9 сентября 2026 (55 расшифровок, 1071 коммит):
# из 769 сцепок «коммит ↔ расшифровка» в 4 выбран вызов, случившийся ПОЗЖЕ коммита,
# вместо последнего вызова до него:
#     191b30c4 9d6611af взят 2026-09-09T00:58:18.746Z, надо 2026-09-09T00:57:22.154Z
#     983c43c4 193019af взят 2026-09-07T22:16:03.623Z, надо 2026-09-07T22:15:59.151Z
#     983c43c4 a4cb47be взят 2026-09-07T22:09:21.893Z, надо 2026-09-07T22:09:17.681Z
#     c1d9c42d 14342528 взят 2026-09-05T17:44:48.596Z, надо 2026-09-05T17:44:43.069Z
# В этих четырёх прогон между вызовами не лежал, поэтому вердикт не перевернулся;
# перевороту достаточно, чтобы прогон оказался в промежутке — что и строит тест.
set -uo pipefail

REPO_REAL="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# 1788820132 = 2026-09-07T22:28:52Z (сверено с iso_epoch того же дерева).
T1=1788820132;      TS1="2026-09-07T22:28:52.000Z"   # вызов 1 — ОН сделал коммит
C_TS=1788820133                                       # коммит на секунду позже вызова 1
TS_RUN="2026-09-07T22:28:54.000Z"                     # прогон противника — ПОСЛЕ коммита
TS2="2026-09-07T22:28:56.000Z"                        # вызов 2 — на 3 с ПОЗЖЕ коммита
SEED_EPOCH=1788700000

make_repo() {
    local r="$1"
    mkdir -p "$r/hooks/lib" "$r/scripts"
    cp "$REPO_REAL/hooks/lib/adversary-run-lib.sh" "$r/hooks/lib/"
    cp "$REPO_REAL/hooks/portable-lib.sh"          "$r/hooks/"
    cp "$REPO_REAL/hooks/command-scope-lib.sh"     "$r/hooks/"
    git -C "$r" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_join_takes_call_after_commit.sh:$LINENO" >&2; exit 1; }
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    git -C "$r" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_join_takes_call_after_commit.sh:$LINENO" >&2; exit 1; }
    GIT_AUTHOR_DATE="@$SEED_EPOCH +0000" GIT_COMMITTER_DATE="@$SEED_EPOCH +0000" \
        git -C "$r" commit -q -m seed 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_join_takes_call_after_commit.sh:$LINENO" >&2; exit 1; }
}
commit_big() {
    local r="$1" e="$2" p="$3" i
    for i in 1 2 3 4 5 6; do seq 1 30 > "$r/$p$i.py"; done
    git -C "$r" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_join_takes_call_after_commit.sh:$LINENO" >&2; exit 1; }
    GIT_AUTHOR_DATE="@$e +0000" GIT_COMMITTER_DATE="@$e +0000" \
        git -C "$r" commit -q -m "big $p" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc2_join_takes_call_after_commit.sh:$LINENO" >&2; exit 1; }
}
bash_call() { jq -cn --arg t "$1" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Bash", input:{command:"git commit -m x"}}]}}'; }
skill_call() { jq -cn --arg t "$1" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Skill", input:{skill:"adversary"}}]}}'; }
replay() {
    ( env CLAUDSOUL_REPO="$1" ADVERSARY_REPLAY_CORPUS="$2" ADVERSARY_REPLAY_CASES="$TMP/cases.txt" \
        bash "$REPO_REAL/scripts/adversary-replay.sh" run 2>&1 )
}

# Расшифровка: вызов коммита (строка 1) → КОММИТ → прогон противника (строка 2) →
# второй вызов коммита (строка 3, через 3 секунды после коммита).
# Коммит сделал ПЕРВЫЙ вызов: он единственный, кто случился ДО коммита.
R="$TMP/repo"; CORP="$TMP/corpus"; mkdir -p "$CORP"
make_repo "$R"
commit_big "$R" "$C_TS" a
{ bash_call "$TS1"; skill_call "$TS_RUN"; bash_call "$TS2"; } > "$CORP/sess-1.jsonl"

OUT=$(replay "$R" "$CORP")

# --- T0: положительный контроль — крупный коммит вообще попал в выборку ---
case "$OUT" in
    *"крупных кодовых коммитов: 1"*) ok ;;
    *) bad "T0" "kontrol provalen, krupnyj kommit ne popal v vyborku: $OUT" ;;
esac

# --- T1: в момент коммита прогона НЕ БЫЛО, значит он обязан лечь в «без прогона» ---
case "$OUT" in
    *"без адверсариального прогона: 1"*) ok ;;
    *) bad "T1" "progon protivnika sluchilsya POSLE kommita, a kommit zaschitan kak proverennyj: verdikt snyat s vyzova, kotoryj byl POZZHE kommita: $OUT" ;;
esac

# --- T2: и не смеет попасть в «с прогоном» ---
case "$OUT" in
    *"с прогоном: 0"*) ok ;;
    *) bad "T2" "chislo <s progonom> zavysheno: sentinel bestgap=-1 otdal scepku vyzovu posle kommita: $OUT" ;;
esac

echo ""
echo "adv-arc2 join-after-commit tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
