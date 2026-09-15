#!/usr/bin/env bash
# test_adv_arc2_attempt_counted_as_commit.sh — атака на предмет живого замера
# scripts/adversary-before-commit.sh (числитель) и hooks/code-review-reminder.sh (писатель).
#
# ЧТО ДОКАЗЫВАЕТСЯ. Замер объявляет результат словами: «сколько РАЗНЫХ крупных кодовых
# диффов ПОШЛО В КОММИТ и в скольких из них адверсариального прогона в сессии не было»,
# и печатает шапкой «Крупные кодовые диффы, УШЕДШИЕ В КОММИТ». Считает он не это.
#
# Единственный источник его чисел — журнал `detection-<SID>.jsonl`, а пишется журнал
# хуком PreToolUse, то есть ДО исполнения команды. Записал `said` — и вышел с кодом 0;
# случился ли коммит, страж не узнаёт никогда и узнать не может: PostToolUse-половины
# у механизма нет. Поэтому в числитель попадает КАЖДЫЙ вызов `git commit`, а не каждый
# коммит: отклонённый собеседником, отменённый, упавший на pre-commit, упавший на
# пустом сообщении.
#
# Хуже того, отклонение — это ЗАПЛАНИРОВАННЫЙ исход стража: его текст поручает «СКАЖИ
# собеседнику… перед коммитом стоит прогнать /adversary. Решение за ним». Собеседник
# отвечает «сначала прогони» и отменяет вызов — и ровно этот успех правила уходит в
# числитель как «крупный дифф ушёл в коммит без прогона». Прибор считает собственные
# срабатывания нарушениями, и это число — первый порог лестницы ADR-015.
#
# ДОСТИЖИМОСТЬ ИЗМЕРЕНА на живом корпусе 9 сентября 2026: из 896 вызовов, прошедших
# `is_git_commit`, 63 (7%) не породили НИ ОДНОГО коммита в окне [-5; +300] секунд —
# то есть каждый четырнадцатый вызов был попыткой, а не событием мира. Ретро-прогон
# (`adversary-replay.sh`) считает по `git log`, поэтому те же 7% в нём отсутствуют:
# два прибора одного предмета расходятся на величину, которую ни один из них не называет.
set -uo pipefail

REPO_REAL="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_REAL/hooks/code-review-reminder.sh"
MEASURE="$REPO_REAL/scripts/adversary-before-commit.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }
[ -f "$HOOK" ] && [ -f "$MEASURE" ] || { echo "SKIP: predmeta net v dereve"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Репозиторий с КРУПНЫМ кодовым диффом в индексе (180 строк / 6 файлов > порогов 80/4).
make_repo() {
    local r="$1" i
    mkdir -p "$r"
    git -C "$r" init -q 2>/dev/null
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    echo seed > "$r/seed.txt"; git -C "$r" add -A >/dev/null 2>&1
    git -C "$r" commit -q -m seed 2>/dev/null
    for i in 1 2 3 4 5 6; do seq 1 30 > "$r/f$i.py"; done
    git -C "$r" add -A >/dev/null 2>&1
}
# Расшифровка без единого прогона противника — но ЧИТАЕМАЯ (иначе ветка `unread`).
plain_transcript() { jq -cn '{message:{content:[{type:"text",text:"privet"}]}}' > "$1"; }

fire_hook() {   # $1 = state, $2 = repo, $3 = sid, $4 = transcript
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"%s","transcript_path":"%s","cwd":"%s"}' \
        "$3" "$4" "$2" | STATE_DIR="$1" bash "$HOOK" >/dev/null 2>&1
}
# Вторая половина механизма: PostToolUse срабатывает ТОЛЬКО на успешной команде (измерено,
# шапка error-tracker.sh). Фикстура обязана моделировать это, иначе она изображает полмира:
# у состоявшегося коммита событие есть, у отменённого вызова его не бывает.
OUTCOME="$REPO_REAL/hooks/code-review-outcome.sh"
fire_outcome() {  # $1 = state, $2 = repo, $3 = sid
    [ -f "$OUTCOME" ] || return 0
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"%s","cwd":"%s"}' \
        "$3" "$2" | STATE_DIR="$1" bash "$OUTCOME" >/dev/null 2>&1
}
measure() {     # $1 = state
    ( env STATE_DIR="$1" ADVERSARY_COMMIT_MIN_N=1 bash "$MEASURE" 2>&1 )
}

# ==================== плечо 1: положительный контроль ====================
# Вызов состоялся И стал коммитом. Прибор обязан насчитать одно событие — иначе
# красное плечо ниже ничего не доказывает.
S1="$TMP/state1"; R1="$TMP/repo1"; mkdir -p "$S1"
make_repo "$R1"; plain_transcript "$TMP/tr1.jsonl"
fire_hook "$S1" "$R1" "SESSA" "$TMP/tr1.jsonl"
git -C "$R1" commit -q -m "big" 2>/dev/null           # коммит СОСТОЯЛСЯ
fire_outcome "$S1" "$R1" "SESSA"                     # …и потому PostToolUse сработал
OUT1=$(measure "$S1")
case "$OUT1" in
    *"всего: 1"*) ok ;;
    *) bad "T0" "kontrol provalen: sostoyavshijsya kommit ne poschitan: $OUT1" ;;
esac

# ==================== плечо 2: вызов отклонён, коммита НЕТ ====================
# Тот же крупный дифф, тот же вызов — но собеседник, услышав напоминание стража,
# коммит отменил. В репозитории по-прежнему один-единственный коммит `seed`.
S2="$TMP/state2"; R2="$TMP/repo2"; mkdir -p "$S2"
make_repo "$R2"; plain_transcript "$TMP/tr2.jsonl"
fire_hook "$S2" "$R2" "SESSB" "$TMP/tr2.jsonl"
# коммита НЕ делаем — вызов отклонён собеседником
NCOMMITS=$(git -C "$R2" log --oneline 2>/dev/null | grep -c . )
OUT2=$(measure "$S2")

# --- T1: контроль мира — коммита действительно нет ---
[ "${NCOMMITS:-0}" = "1" ] && ok || bad "T1" "kontrol mira provalen: kommitov v repozitorii $NCOMMITS, ozhidalsya tol'ko seed"

# --- T2: дифф, не ставший коммитом, не может быть «ушедшим в коммит» ---
case "$OUT2" in
    *"записей стража code-review-reminder нет"*) ok ;;
    # Третья формулировка ТОГО ЖЕ исхода «ничего не посчитано»: после починки отменённый
    # вызов не создаёт журнала признаков вовсе (запись ждёт подтверждения в pending), и
    # замер сообщает об этом своей давней веткой «журналов нет». Ветка добавлена 9 сентября
    # 2026 при закрытии атаки; САМА атака ниже не тронута — «всего: 1» по-прежнему провал.
    *"журналов признаков нет"*) ok ;;
    *"всего: 0"*) ok ;;
    *"всего: 1"*) bad "T2" "otklonennyj vyzov opublikovan kak <krupnyj diff, ushedshij v kommit>: v mire kommita net, a pribor pechataet ego v chislitel: $OUT2" ;;
    *) bad "T2" "neozhidannyj vyvod zamera: $OUT2" ;;
esac

# --- T3: и не смеет объявлять находку ADR-015 на несостоявшемся событии ---
case "$OUT2" in
    *"больше половины крупных диффов уходит в коммит без прогона"*)
        bad "T3" "zamer ob'yavil pervyj porog lestnicy ADR-015 na sobytii, kotorogo ne bylo: $OUT2" ;;
    *) ok ;;
esac

echo ""
echo "adv-arc2 attempt-as-commit tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
