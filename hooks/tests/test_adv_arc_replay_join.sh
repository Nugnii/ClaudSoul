#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh hooks/lib/adversary-run-lib.sh hooks/portable-lib.sh scripts/adversary-replay.sh
# test_adv_arc_replay_join.sh — атака на сцепку «вызов -> коммит» в scripts/adversary-replay.sh:175.
#
# ЧТО ДОКАЗЫВАЕТСЯ. Комментарий обещает «ближайший коммит в окне». Код выбирает не
# ближайший, а САМЫЙ РАННИЙ:
#
#     awk -v lo="$(( T - WIN_BEFORE ))" '... { d=$2-lo; if (best=="" || d<bd) ... }'
#
# `d` меряется от НИЖНЕЙ границы окна, поэтому минимум `d` — это минимальное время
# коммита, а не минимальное расстояние до момента вызова. Плюс дедуп SEEN (строка 186)
# закрепляет коммит за ПЕРВЫМ вызовом, дотянувшимся до него: все последующие вызовы
# уходят по continue, не попадая ни в BIG, ни в UNJOINED.
#
# Два следствия, каждое своей ногой:
#
#  T1-T2. Вердикт о прогоне снимается с ПРЕФИКСА первого вызова. Если противник отработал
#         МЕЖДУ двумя вызовами коммита (ровно тот сценарий, ради которого страж и
#         существует: напомнил, прогнали, закоммитили), прибор публикует коммит как
#         «ушёл без прогона», хотя прогон лежит в расшифровке РАНЬШЕ коммита.
#         Число правдоподобно и неверно, и именно оно идёт в решение по ADR-015.
#
#  T3.    Коммит, случившийся за секунды ДО вызова, перехватывает сцепку у коммита,
#         который вызов на самом деле сделал. Если перехватчик мелкий, крупный коммит
#         выпадает из выборки целиком, и прибор говорит «мерить нечего».
#
# Достижимость механизма замерена на живом корпусе 9 сентября 2026: из 741 коммита,
# к которым сцепились вызовы, 96 (13%) получили вердикт от НЕ последнего вызова; в 8
# случаях «самый ранний в окне» отличался от «ближайшего к моменту вызова».
set -uo pipefail

REPO_REAL="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Метки времени и эпохи согласованы вручную: 1788820132 = 2026-09-07T22:28:52Z.
T1=1788820132;  TS1="2026-09-07T22:28:52.000Z"
TS2="2026-09-07T22:32:52.000Z"                    # T1 + 240 c
C_LATE=1788820382                                 # T1 + 250 c, внутри окна ОБОИХ вызовов
SEED_EPOCH=1788700000

# Подставной репозиторий: ретро-прогон читает свои библиотеки из $CLAUDSOUL_REPO/hooks.
make_repo() {   # $1 = каталог
    local r="$1"
    mkdir -p "$r/hooks/lib" "$r/scripts"
    cp "$REPO_REAL/hooks/lib/adversary-run-lib.sh" "$r/hooks/lib/"
    cp "$REPO_REAL/hooks/portable-lib.sh"          "$r/hooks/"
    cp "$REPO_REAL/hooks/command-scope-lib.sh"     "$r/hooks/"
    git -C "$r" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    git -C "$r" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
    GIT_AUTHOR_DATE="@$SEED_EPOCH +0000" GIT_COMMITTER_DATE="@$SEED_EPOCH +0000" \
        git -C "$r" commit -q -m seed 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
}
commit_big() {  # $1 = каталог, $2 = эпоха, $3 = префикс имён
    local r="$1" e="$2" p="$3" i
    for i in 1 2 3 4 5 6; do seq 1 30 > "$r/$p$i.py"; done
    git -C "$r" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
    GIT_AUTHOR_DATE="@$e +0000" GIT_COMMITTER_DATE="@$e +0000" \
        git -C "$r" commit -q -m "big $p" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
}
commit_small() {  # $1 = каталог, $2 = эпоха, $3 = имя
    local r="$1" e="$2" n="$3"
    printf 'x = 1\n' > "$r/$n.py"
    git -C "$r" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
    GIT_AUTHOR_DATE="@$e +0000" GIT_COMMITTER_DATE="@$e +0000" \
        git -C "$r" commit -q -m "small $n" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_replay_join.sh:$LINENO" >&2; exit 1; }
}
bash_call() {   # $1 = метка ISO
    jq -cn --arg t "$1" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Bash", input:{command:"git commit -m x"}}]}}'
}
skill_call() {
    jq -cn '{timestamp:"2026-09-07T22:30:00.000Z", message:{content:[
        {type:"tool_use", name:"Skill", input:{skill:"adversary"}}]}}'
}
replay() {      # $1 = репозиторий, $2 = каталог корпуса
    ( env CLAUDSOUL_REPO="$1" ADVERSARY_REPLAY_CORPUS="$2" ADVERSARY_REPLAY_CASES="$TMP/cases.txt" \
        bash "$REPO_REAL/scripts/adversary-replay.sh" run 2>&1 )
}

# ==================== плечо 1: прогон между двумя вызовами ====================
#
# Расшифровка: вызов коммита, ПРОГОН ПРОТИВНИКА, вызов коммита. Единственный коммит
# репозитория лежит ПОСЛЕ обоих вызовов, то есть его сделал второй, а прогон был раньше.
R1="$TMP/repo1"; C1="$TMP/corpus1"; mkdir -p "$C1"
make_repo "$R1"
commit_big "$R1" "$C_LATE" a
{ bash_call "$TS1"; skill_call; bash_call "$TS2"; } > "$C1/sess-1.jsonl"

OUT1=$(replay "$R1" "$C1")

# --- T0: положительный контроль — крупный коммит вообще попал в выборку ---
case "$OUT1" in
    *"крупных кодовых коммитов: 1"*) ok ;;
    *) bad "T0" "kontrol provalen: krupnyj kommit ne popal v vyborku vovse: $OUT1" ;;
esac

# --- T1: прогон был ДО коммита, значит коммит обязан лечь в «с прогоном» ---
case "$OUT1" in
    *"с прогоном: 1"*) ok ;;
    *) bad "T1" "progon protivnika lezhit v rasshifrovke mezhdu vyzovami, a kommit ne zaschitan kak <s progonom>: $OUT1" ;;
esac

# --- T2: и не смеет попасть в числитель «без прогона» ---
case "$OUT1" in
    *"без адверсариального прогона: 0"*) ok ;;
    *) bad "T2" "kommit opublikovan kak <ushel bez progona>: verdikt snyat s prefiksa PERVOGO vyzova: $OUT1" ;;
esac

# ==================== плечо 2: перехват сцепки более ранним коммитом ==========
#
# Один вызов коммита. В репозитории мелкий коммит за 3 секунды ДО вызова (сделать его
# вызов не мог) и крупный через 2 секунды ПОСЛЕ (его вызов и сделал). Оба в окне
# [T-5; T+300], и «самый ранний» отдаёт сцепку мелкому.
R2="$TMP/repo2"; C2="$TMP/corpus2"; mkdir -p "$C2"
make_repo "$R2"
commit_small "$R2" "$(( T1 - 3 ))" tiny
commit_big   "$R2" "$(( T1 + 2 ))" b
bash_call "$TS1" > "$C2/sess-2.jsonl"

OUT2=$(replay "$R2" "$C2")

# --- T3: крупный коммит обязан попасть в выборку ---
case "$OUT2" in
    *"крупных кодовых коммитов: 1"*) ok ;;
    *"мерить нечего"*) bad "T3" "scepku perehvatil melkij kommit za 3 sekundy DO vyzova, krupnyj vypal iz vyborki: $OUT2" ;;
    *) bad "T3" "krupnyj kommit ne poschitan: $OUT2" ;;
esac

echo ""
echo "adv-arc replay-join tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
