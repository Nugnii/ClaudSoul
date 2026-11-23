#!/usr/bin/env bash
# СУДИТ: hooks/denied-branch-commit-guard.sh
# test_denied_branch_commit_guard.sh — коммит после отклонённого `git switch -c X`, когда HEAD не X,
# отбивается один раз на ветку за сессию (D526).
#
# Результат: отказ называет X и текущую ветку; на ветке X, без отказа, без создания ветки, не на
#            коммите и при повторе — молчание.
# Проверка результата: bash hooks/tests/test_denied_branch_commit_guard.sh даёт 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

HOOK="$(cd "$(dirname "$0")/.." && pwd)/denied-branch-commit-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

R="$TMP/repo"; mkdir -p "$R" && git -C "$R" init -q -b main && printf 'a\n' > "$R/a" \
    && git -C "$R" add a && git -C "$R" -c user.email=t@t -c user.name=t commit -qm init || { echo "FAIL [рамка]: репозиторий"; exit 1; }
DENY='PreToolUse:Bash hook error: ⛔ ОТКАЗ (вызов не выполнен). Правка не пройдёт, пока не осмотрены места.'

tr_add() {   # tr_add <файл> <id> <команда> <текст результата> <ошибка> [cwd] — дописать пару вызов/результат
    jq -cn --arg i "$2" --arg c "$3" --arg d "${6:-$R}" '{type:"assistant",cwd:$d,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Bash",input:{command:$c}}]}}' >> "$1"
    jq -cn --arg i "$2" --arg t "$4" --argjson e "$5" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,is_error:$e,content:$t}]}}' >> "$1"
}
tr_file() {   # tr_file <имя> <команда> <текст результата> <ошибка true|false> → путь расшифровки
    local f="$TMP/$1.jsonl"
    jq -cn --arg c "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:$c}}]}}' > "$f"
    jq -cn --arg t "$3" --argjson e "$4" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",is_error:$e,content:$t}]}}' >> "$f"
    printf '%s' "$f"
}
run() {   # run <расшифровка> <команда> [сессия] [cwd] → вывод стража
    jq -cn --arg c "$2" --arg t "$1" --arg s "${3:-s1}" --arg d "${4:-$R}" \
        '{tool_name:"Bash",tool_input:{command:$c},session_id:$s,transcript_path:$t,cwd:$d}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
denied() { grep -q '"permissionDecision":"deny"' <<< "$1"; }
assert_silent() { if [ -z "$1" ]; then ok; else bad "$2" "отбито зря: ${1:0:200}"; fi; }   # <вывод> <метка>

T=$(tr_file denied "git switch -c fix/x && git add a" "$DENY" true)

# --- T1 (ГЛАВНАЯ): отказ с `git switch -c fix/x`, HEAD — main, коммит → отказ с обоими именами -----
OUT=$(run "$T" "git commit -m 'правка'" s1)
if denied "$OUT" && grep -q 'fix/x' <<< "$OUT" && grep -q 'main' <<< "$OUT"; then ok; else bad T1 "коммит в main после отклонённой ветки не отбит: ${OUT:0:300}"; fi

# --- T2: повтор той же команды в той же сессии — проходит (один отказ на ветку) -----------------
OUT=$(run "$T" "git commit -m 'правка'" s1)
assert_silent "$OUT" "T2 повтор отбит снова"

# --- T3: HEAD на ветке fix/x — молчание ---------------------------------------------------------
git -C "$R" switch -q -c fix/x
OUT=$(run "$T" "git commit -m x" s3)
assert_silent "$OUT" "T3 коммит на нужной ветке отбит"
git -C "$R" switch -q main && git -C "$R" branch -q -D fix/x   # ветка, оставшаяся после ноги, — Л2 глушил бы следующие

# --- T4: создание ветки НЕ было отклонено (успешный вызов) — молчание ---------------------------
T4=$(tr_file ok "git switch -c fix/y" "Switched to a new branch 'fix/y'" false)
OUT=$(run "$T4" "git commit -m x" s4)
assert_silent "$OUT" "T4 успешное создание ветки принято за отклонённое"

# --- T5: отклонён вызов без создания ветки — молчание -------------------------------------------
T5=$(tr_file nobr "git add a && git commit -m x" "$DENY" true)
OUT=$(run "$T5" "git commit -m x" s5)
assert_silent "$OUT" "T5 отказ без ветки дал отказ коммиту"

# --- T6: не коммит — молчание -------------------------------------------------------------------
OUT=$(run "$T" "git status" s6)
assert_silent "$OUT" "T6 не коммит отбит"

# --- T7: формы создания ветки — checkout -b, switch --create, git -C <каталог> switch -c ----------
for _f in "git checkout -b fix/x" "git switch --create fix/x" "git -C $R switch -c fix/x"; do
    T7=$(tr_file f7 "$_f && echo" "$DENY" true)
    OUT=$(run "$T7" "git commit -m x" "s7-$RANDOM")
    denied "$OUT" && grep -q 'fix/x' <<< "$OUT" && ok || bad T7 "форма «${_f}» не узнана: ${OUT:0:200}"
done

# --- T8: ветка в кавычках сообщения (не исполняемая часть) — молчание ---------------------------
T8=$(tr_file f8 "git commit -m 'потом git switch -c fix/q'" "$DENY" true)
OUT=$(run "$T8" "git commit -m x" s8)
assert_silent "$OUT" "T8 упоминание в кавычках принято за создание ветки"

# --- T9: отказ в старой (голой) форме без префикса харнесса — тоже отказ -------------------------
T9=$(tr_file f9 "git switch -c fix/x" "⛔ ОТКАЗ (вызов не выполнен)." true)
OUT=$(run "$T9" "git commit -m x" s9)
denied "$OUT" && ok || bad T9 "голая форма отказа не узнана: ${OUT:0:200}"

# --- T10: обычная ошибка вызова (не отказ стража) — молчание: ветку не создал git, а не страж ----
T10=$(tr_file f10 "git switch -c fix/x" "fatal: a branch named 'fix/x' already exists" true)
OUT=$(run "$T10" "git commit -m x" s10)
assert_silent "$OUT" "T10 ошибка git принята за отказ стража"

# --- T11: коммит через `git -C <каталог>` — ветка сверяется в том каталоге -----------------------
git -C "$R" switch -q -c fix/x || { echo "FAIL [рамка]: T11 не создал ветку"; exit 1; }
OUT=$(run "$T" "git -C $R commit -m x" s11 "$TMP")
assert_silent "$OUT" "T11 git -C в репозиторий на ветке fix/x отбит по cwd"
git -C "$R" switch -q main && git -C "$R" branch -q -D fix/x

# --- T12 (скептик, повод D526): флаг между `switch` и `-c` — как в живой расшифровке ProjectA ------
T12=$(tr_file f12 "cd $R && git switch -q -c fix/x && cd web" "$DENY" true)
OUT=$(run "$T12" "git commit -m x" s12)
denied "$OUT" && grep -q 'fix/x' <<< "$OUT" && ok || bad T12 "повод D526 (git switch -q -c) не узнан: ${OUT:0:200}"

# --- T13 (скептик, Л1): команда коммита сама создаёт X — повтор отклонённой цепочки молчит ------
OUT=$(run "$T" "git switch -c fix/x && git add a && git commit -m x" s13)
assert_silent "$OUT" "T13 коммит, который сам создаёт ветку, отбит"

# --- T14 (Л2): ветка X существует (создана позже), HEAD — main → молчание ----------------------
git -C "$R" branch -q fix/x
OUT=$(run "$T" "git commit -m x" s14)
# Раунд 3 (Н2): «X существует» не значит «HEAD был на X» — `git branch X` без переключения.
denied "$OUT" && ! grep -q 'нет' <<< "$OUT" && ok || bad T14 "ветка есть, HEAD на main — нужен отказ без «ветки нет»: ${OUT:0:200}"
git -C "$R" branch -q -D fix/x

# --- T15 (Л3): отклонён вызов в ДРУГОМ репозитории — коммит здесь молчит ----------------------
R2="$TMP/repo2"; mkdir -p "$R2" && git -C "$R2" init -q -b main && printf 'a\n' > "$R2/a" \
    && git -C "$R2" add a && git -C "$R2" -c user.email=t@t -c user.name=t commit -qm i || { echo "FAIL [рамка]: repo2"; exit 1; }
T15=$(tr_file f15 "git -C $R2 switch -c fix/x && echo" "$DENY" true)
OUT=$(run "$T15" "git commit -m x" s15)
assert_silent "$OUT" "T15 отказ в другом репозитории отбил коммит здесь"

# --- T16 (Л4): путь `-C` в кавычках с пробелом — и в создании ветки, и в коммите -----------------
RS="$TMP/my repo"; mkdir -p "$RS" && git -C "$RS" init -q -b main && printf 'a\n' > "$RS/a" \
    && git -C "$RS" add a && git -C "$RS" -c user.email=t@t -c user.name=t commit -qm i || { echo "FAIL [рамка]: my repo"; exit 1; }
T16=$(tr_file f16 "git -C \"$RS\" switch -q -c fix/w && echo" "$DENY" true)
OUT=$(run "$T16" "git -C \"$RS\" commit -m x" s16 "$TMP")
denied "$OUT" && grep -q 'fix/w' <<< "$OUT" && ok || bad T16 "путь -C в кавычках не разобран: ${OUT:0:200}"

# --- T17 (Л5): перенаправление вплотную к имени ветки — имя без него ---------------------------
T17=$(tr_file f17 'git switch -c fix/r>/dev/null && echo' "$DENY" true)
OUT=$(run "$T17" "git commit -m x" s17)
denied "$OUT" && grep -q '«fix/r»' <<< "$OUT" && ok || bad T17 "имя ветки взято с мусором: ${OUT:0:200}"

# --- T18: гонка дедупа — 8 параллельных коммитов одной сессии дают ровно один отказ ------------
for _k in 1 2 3 4 5 6 7 8; do run "$T12" "git commit -m x" s18 > "$TMP/race.$_k" & done; wait
[ "$(cat "$TMP"/race.* | grep -c '"permissionDecision":"deny"')" = 1 ] && ok || bad T18 "отказов при гонке: $(cat "$TMP"/race.* | grep -c deny)"

# Ноги T19-T25 — раунд 2 противника.
# --- T19 (Н1): отказ отработан (коммит на X), X слита и удалена — следующий коммит в main молчит --
git -C "$R" switch -q -c fix/x
OUT=$(run "$T" "git commit -m x" s19)
assert_silent "$OUT" "T19a коммит на X отбит"
git -C "$R" switch -q main && git -C "$R" branch -q -D fix/x
OUT=$(run "$T" "git commit -m y" s19)
assert_silent "$OUT" "T19b отработанный отказ вернулся после удаления ветки"

# --- T20 (Н2): каталог отклонённого вызова не установлен (нет такого) — молчание ---------------
T20=$(tr_file f20 "cd $TMP/gone && git switch -c fix/x" "$DENY" true)
OUT=$(run "$T20" "git commit -m x" s20)
assert_silent "$OUT" "T20 неустановленный каталог отказа принят за тот же репозиторий"

# --- T21 (Н4): коммит под `if` — узнан ---------------------------------------------------------
OUT=$(run "$T" "if git commit -m x; then :; fi" s21)
denied "$OUT" && ok || bad T21 "коммит под if не узнан: ${OUT:0:200}"

# --- T22 (Н5): `git worktree add -b X` и склеенное `-bfix/x` — узнаны ------------------------
for _f in "git worktree add -b fix/x ../wt" "git checkout -bfix/x"; do
    T22=$(tr_file f22 "cd $R && $_f && echo" "$DENY" true)
    OUT=$(run "$T22" "git commit -m x" "s22-$RANDOM")
    denied "$OUT" && grep -q '«fix/x»' <<< "$OUT" && ok || bad T22 "форма «${_f}» не узнана: ${OUT:0:200}"
done

# --- T23 (Н7): `git checkout -- <файл>` ветку не переключает — отказ остаётся --------------------
OUT=$(run "$T" "git checkout -- a && git commit -am x" s23)
denied "$OUT" && ok || bad T23 "checkout файла принят за переключение ветки: ${OUT:0:200}"

# --- T24 (Н8): прибор сломан (выражение отказа не разбирается) — сигнал, а не тишина ------------
OUT=$(jq -cn --arg c "git commit -m x" --arg t "$T" --arg d "$R" '{tool_name:"Bash",tool_input:{command:$c},session_id:"s24",transcript_path:$t,cwd:$d}' \
      | DENY_MARK_RE='(' STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
grep -q 'прибор сломан' <<< "$OUT" && ok || bad T24 "сломанный прибор промолчал: ${OUT:0:200}"

# Ноги T25-T28 — раунд 3 противника.
# --- T25 (Н1): повтор отклонённой цепочки отклонён снова — после него коммит в main отбит --------
F="$TMP/f25.jsonl"; : > "$F"
tr_add "$F" a1 "git switch -q -c fix/a && git commit -am x" "$DENY" true
OUT=$(run "$F" "git switch -q -c fix/a && git commit -am x" s25)
assert_silent "$OUT" "T25a повтор цепочки с переключением отбит"
tr_add "$F" a2 "git switch -q -c fix/a && git commit -am x" "$DENY" true
OUT=$(run "$F" "git commit -am x" s25)
denied "$OUT" && grep -q 'fix/a' <<< "$OUT" && ok || bad T25 "после второго отказа коммит в main прошёл: ${OUT:0:200}"

# --- T26 (Н3): коммит в ДРУГОМ репозитории не глушит отказ для этого -------------------------
git -C "$R2" branch -q develop && git -C "$R2" switch -q develop
F="$TMP/f26.jsonl"; : > "$F"; tr_add "$F" b1 "git switch -c develop && echo" "$DENY" true "$R"
OUT=$(run "$F" "git commit -m x" s26 "$R2"); assert_silent "$OUT" "T26a коммит в другом репозитории отбит"
OUT=$(run "$F" "git commit -m x" s26 "$R")
denied "$OUT" && ok || bad T26 "коммит в другом репозитории погасил отказ для этого: ${OUT:0:200}"
git -C "$R2" switch -q main

# --- T27 (Н4): создание ветки ПОСЛЕ коммита в отклонённой цепочке — не предмет -------------------
F="$TMP/f27.jsonl"; : > "$F"; tr_add "$F" c1 "git add -A && git commit -m release && git switch -c next" "$DENY" true
OUT=$(run "$F" "git add a && git commit -m release" s27)
assert_silent "$OUT" "T27 создание ветки после коммита приняло коммит в main за чужой"

# --- T28 (Н4б): собственный отказ стража не подменяет ветку — повтор проходит -----------------
F="$TMP/f28.jsonl"; : > "$F"; tr_add "$F" d1 "git switch -q -c fix/a && echo" "$DENY" true
OUT=$(run "$F" "git commit -am wip && git switch -c fix/b" s28)
denied "$OUT" && grep -q 'fix/a' <<< "$OUT" && ok || bad T28a "первый коммит не отбит: ${OUT:0:200}"
tr_add "$F" d2 "git commit -am wip && git switch -c fix/b" "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$OUT")" true
OUT=$(run "$F" "git commit -am wip && git switch -c fix/b" s28)
assert_silent "$OUT" "T28 повтор после нашего отказа отбит снова"

# --- T29 (раунд 3 D525, общий разбор): `#` в кавычках не прячет создание ветки -----------------
F="$TMP/f29.jsonl"; : > "$F"; tr_add "$F" e1 'echo "#x"; git switch -q -c fix/q && echo' "$DENY" true
OUT=$(run "$F" "git commit -m x" s29)
denied "$OUT" && grep -q 'fix/q' <<< "$OUT" && ok || bad T29 "создание ветки после \"#x\" не узнано: ${OUT:0:200}"

echo "denied branch commit guard: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
