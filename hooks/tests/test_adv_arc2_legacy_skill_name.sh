#!/usr/bin/env bash
# test_adv_arc2_legacy_skill_name.sh — атака на ретро-прогон: прошлое судится НЫНЕШНИМ
# значением признака. Предмет — hooks/lib/adversary-run-lib.sh (`_arc_skill`) в связке
# с scripts/adversary-replay.sh.
#
# ЧТО ДОКАЗЫВАЕТСЯ. Библиотека берёт имя скилла из `ADVERSARY_SKILL_NAME` с умолчанием
# `adversary` и сверяет `.input.skill == $s` РАВЕНСТВОМ. Её собственная шапка при этом
# говорит: «ИМЯ СКИЛЛА И МАРКЕР ПРОМПТА — РАЗНЫЕ ФАКТЫ, и ДО ПЕРЕИМЕНОВАНИЯ 28.08.2026
# они случайно совпадали». То есть имя — величина, у которой есть история, а сверка
# ведётся одним значением, действующим СЕГОДНЯ.
#
# Ретро-прогон (`adversary-replay.sh`) по построению смотрит в прошлое: корпус
# `~/.claude/projects/<слаг>/*.jsonl` старше переименования. Каждый вызов противника,
# сделанный под прежним именем, для прибора не существует, и коммит, перед которым
# противника ЧЕСТНО прогнали, публикуется как «ушёл без прогона». Шапка ретро-прогона
# обещает обратное: «Прогон по префиксу расшифровки воспроизводит ровно то, что страж
# видел в тот момент» — страж в тот момент искал ДРУГОЕ имя.
#
# ДОСТИЖИМОСТЬ ИЗМЕРЕНА в живом корпусе 9 сентября 2026: инструмент Skill вызывался с
# `skill: "противник"` ТРИ раза — в трёх разных расшифровках, — против четырёх вызовов
# с нынешним `adversary`. То есть 3 из 7
# зарегистрированных вызовов скилла прибор не видит. В этих трёх расшифровках прогон
# опознаётся другой веткой (маркер промпта у порождённого субагента лежит десятью
# строками ниже), поэтому вердикт там пока не перевернулся; переворот наступает, когда
# коммит попадает в промежуток либо когда прогон был позван скиллом без субагента.
set -uo pipefail

REPO_REAL="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

T1=1788820132;  TS_CALL="2026-09-07T22:28:52.000Z"
TS_RUN="2026-09-07T22:20:00.000Z"      # прогон — задолго ДО вызова коммита
C_TS=1788820142                        # коммит через 10 с после вызова
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
bash_call()  { jq -cn --arg t "$1" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Bash", input:{command:"git commit -m x"}}]}}'; }
skill_call() { jq -cn --arg t "$1" --arg s "$2" '{timestamp:$t, message:{content:[
        {type:"tool_use", name:"Skill", input:{skill:$s}}]}}'; }
replay() {
    ( env CLAUDSOUL_REPO="$1" ADVERSARY_REPLAY_CORPUS="$2" ADVERSARY_REPLAY_CASES="$TMP/cases.txt" \
        bash "$REPO_REAL/scripts/adversary-replay.sh" run 2>&1 )
}

# ==================== плечо 1: нынешнее имя — контроль ====================
R1="$TMP/repo1"; C1="$TMP/corpus1"; mkdir -p "$C1"
make_repo "$R1"; commit_big "$R1" "$C_TS" a
{ skill_call "$TS_RUN" "adversary"; bash_call "$TS_CALL"; } > "$C1/sess-1.jsonl"
OUT1=$(replay "$R1" "$C1")
case "$OUT1" in
    *"с прогоном: 1"*) ok ;;
    *) bad "T0" "kontrol provalen: vyzov skilla pod NYNESHNIM imenem ne zaschitan progonom: $OUT1" ;;
esac

# ==================== плечо 2: прежнее имя скилла ====================
# Та же сессия слово в слово, отличается ровно значение `.input.skill`.
R2="$TMP/repo2"; C2="$TMP/corpus2"; mkdir -p "$C2"
make_repo "$R2"; commit_big "$R2" "$C_TS" b
{ skill_call "$TS_RUN" "противник"; bash_call "$TS_CALL"; } > "$C2/sess-2.jsonl"
OUT2=$(replay "$R2" "$C2")

# --- T1: прогон БЫЛ и лежит в расшифровке до коммита ---
case "$OUT2" in
    *"с прогоном: 1"*) ok ;;
    *) bad "T1" "progon protivnika pod prezhnim imenem skilla nevidim: retro-progon sudit proshloe nyneshnim znacheniem priznaka: $OUT2" ;;
esac

# --- T2: и коммит не смеет попасть в числитель «без прогона» ---
case "$OUT2" in
    *"без адверсариального прогона: 0"*) ok ;;
    *) bad "T2" "kommit s chestnym progonom opublikovan kak <ushel bez progona>: $OUT2" ;;
esac

echo ""
echo "adv-arc2 legacy-skill-name tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
