#!/usr/bin/env bash
# СУДИТ: hooks/git-stash-guard.sh
# test_git_stash_guard.sh — `git stash`, меняющий рабочую копию, отбивается; list/show — нет (D525).
#
# Результат: отказ на push/pop/apply/drop/clear и голый stash в любой позиции команды; молчание на
#            list/show, на упоминание в кавычках и комментарии, на не-git команды.
# Проверка результата: bash hooks/tests/test_git_stash_guard.sh даёт 0
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/git-stash-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

run() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c},session_id:"s"}' | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }
denied() { grep -q '"permissionDecision":"deny"' <<< "$1"; }
assert_silent() { if [ -z "$1" ]; then ok; else bad "$2" "отбито зря: ${1:0:200}"; fi; }   # <вывод> <метка>

# --- отказ: формы, меняющие рабочую копию -------------------------------------------------------
while IFS= read -r c; do
    [ -n "$c" ] || continue
    OUT=$(run "$c"); denied "$OUT" && ok || bad "D" "не отбито: $c"
done <<'DENY'
git stash
git stash -q
git stash push -- a.txt
git stash pop
git stash apply stash@{0}
git stash drop
git stash clear
git stash -u
npx vitest run x; git stash -q 2>/dev/null; true
git stash -- src/a.ts && npx vitest run; git stash pop
git -C /repo stash
cd /repo && git stash
git stash list; git stash pop
(git stash)
echo it\'s; git stash pop
out=$(git stash pop 2>&1)
"git" stash pop
git --no-pager stash pop
x=$(pwd); git stash pop
(cd sub && make); git stash pop
make |& git stash
echo ${#a}; git stash pop
git --icase-pathspecs stash pop
git stash list | xargs -n1 git stash drop
timeout 5 git stash pop
2>/dev/null git stash pop
git commit -m "#123"; git stash pop
echo \#; git stash pop
>>out git stash pop
2>&1 git stash pop
&>/dev/null git stash pop
<<<"x" git stash pop
git 2>/dev/null stash pop
DENY

# --- молчание: только чтение и не-предмет ------------------------------------------------------
while IFS= read -r c; do
    [ -n "$c" ] || continue
    OUT=$(run "$c"); assert_silent "$OUT" "S $c"
done <<'SILENT'
git stash list
git stash show -p stash@{0}
git -C /repo stash list
git stash list | head -3
echo "не делай git stash pop"
git commit -m "убрал git stash из скрипта"
git status  # git stash здесь не нужен
grep -rn "git stash" hooks/
git show HEAD:a.txt
git -C "/My Project/repo" stash list
git --no-pager stash list
git -P stash show -p
git stash list>/tmp/out.txt
git -c "core.pager=less -R" stash list
ls # a; git stash pop
git stash 2>/dev/null list
true;# git stash pop
SILENT

# --- текст отказа называет замену, журнал срабатываний пишется ---------------------------------
OUT=$(run "git stash pop")
grep -q 'git show HEAD:<путь>' <<< "$OUT" && grep -q 'worktree add --detach' <<< "$OUT" && ok || bad "R" "в отказе нет замены: ${OUT:0:200}"
[ -s "$TMP/state/git-stash-fired-s.jsonl" ] && ok || bad "J" "журнал срабатываний не записан"

# --- раунд 2: перенос строки `\` — команда на следующей строке; `stash \⏎ list` — чтение -------
OUT=$(run $'make && \\\n  git stash pop'); denied "$OUT" && ok || bad "D переноса" "не отбито: make && \\⏎ git stash pop"
OUT=$(run $'git stash \\\n  list'); assert_silent "$OUT" "S git stash \\⏎ list"

# --- раунд 2 (N6): прибор сломан — библиотека без git_calls — сигнал, а не тишина ---------------
B="$TMP/broken/hooks"; mkdir -p "$B/lib" && cp "$HOOK" "$B/" && printf 'def calls(c):\n    return []\n' > "$B/lib/write_targets.py"
OUT=$(jq -cn '{tool_name:"Bash",tool_input:{command:"git stash pop"},session_id:"s"}' | STATE_DIR="$TMP/state" HOME="$TMP/nohome" bash "$B/git-stash-guard.sh" 2>/dev/null)
grep -q 'прибор сломан' <<< "$OUT" && ok || bad "N6" "сломанный прибор промолчал: ${OUT:0:200}"

# --- раунд 3: комментарий с апострофом не глотает следующие строки; перенос без отступа --------
OUT=$(run $'# don\'t touch this\ngit stash pop'); denied "$OUT" && ok || bad "D комм" "апостроф в комментарии спрятал следующую строку"
OUT=$(run $'true && \\\ngit stash pop'); denied "$OUT" && ok || bad "D перенос0" "перенос без отступа спрятал команду"
OUT=$(run $'git stash \\\nlist'); assert_silent "$OUT" "S git stash \\⏎list без отступа"

# --- раунд 3: цена — 2000 строк в кавычках разбираются за секунды (было кубически: 79 с) ---------
BIG="git commit -m \"$(for i in $(seq 1 2000); do printf 'строка %s\n' "$i"; done)\"; git stash pop"
T0=$SECONDS; OUT=$(run "$BIG"); DT=$((SECONDS - T0))
denied "$OUT" && [ "$DT" -le 5 ] && ok || bad "цена" "2000 строк: $DT с, вывод ${OUT:0:80}"

echo "git stash guard: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
