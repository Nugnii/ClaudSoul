#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/write_targets.py hooks/git-add-sweep-guard.sh
# probe_D1216 — `prefix_env` (режим `--prefix-env`) берёт границы команд у общего лексера: слово в кавычках
#   (`grep -E 'a|B=1 git|c' f`) присваиванием не становится, `X=1 git add .` по-прежнему даёт `X=1<таб>git`, а
#   подстановка без кавычек в значении (`A=1 X=$(pwd) git`, вложенная, с приклеенным хвостом) не отрывает `A=1` от
#   `git`; `{`/`}` в аргументе, массив `arr=(…)`, хвост `D=$(pwd)/git`, тело heredoc `cat` и комментарий присваиваний
#   перед `git` не дают (скептик opus по 1abe8aa3).
#   Сквозь стража `git-add-sweep-guard`: ключ обхода внутри шаблона `grep` вопроса о `git add docs` не снимает.
#   0 — границы верны; 1 — присваивание из кавычек либо потеряно настоящее; 2 — нет разбора, jq или git.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
W="$PWD/hooks/lib/write_targets.py"; H="$PWD/hooks/git-add-sweep-guard.sh"
[ -f "$W" ] && [ -f "$H" ] && command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 2
T=$'\t'
pe() { printf '%s' "$1" | python3 "$W" --prefix-env 2>/dev/null | tr '\n' ' '; }
[ "$(pe 'X=1 git add .')" = "X=1${T}git " ] || { echo "рамка: X=1 git add . — не X=1<таб>git: [$(pe 'X=1 git add .')]"; exit 2; }
bad=0
# Ответ — ровно то, что стоит в позиции команды; пустая строка — «присваиваний нет». «¦» в команде — «|».
while IFS='|' read -r want cmd; do
    cmd=${cmd//¦/|}; got=$(pe "$cmd")
    [ "$got" = "${want//<T>/$T}" ] || { echo "у [$cmd] ответ [${got//$T/<T>}], а не [$want]"; bad=1; }
done <<'CASES'
|grep -E 'a¦B=1 git¦c' f
|grep -oE 'PASS=[0-9]+¦FAIL=[0-9]+¦SKIP=[0-9]+' log
|echo "$(grep -oE 'PASS=[0-9]+¦x' f)"
|echo 'x; X=1 git' y
X=a;b<T>git |X='a;b' git add .
A=1<T>git B=2<T>git C=3<T>ls |A=1 B=2 git commit -m x; C=3 ls
X=1<T>git |echo a && X=1 git add .
X=1<T>git |echo a | X=1 git add .
X=1<T>git |X=1 2>/dev/null git add .
A=1<T>git X=$<T>git |A=1 X=$(pwd) git add .
A=1<T> X=$<T> |A=1 X=$(pwd); git add .
Y=$<T>cmd B=2<T>cmd X=$<T>git A=1<T>git |X=$(Y=$(pwd) B=2 cmd) A=1 git
|echo a '{' B=1 git; git add docs
|echo { B=1 git }
arr=<T> |arr=(B=1 git status)
B=1<T> D=$<T> |B=1 D=$(pwd)/git; git add docs
B=1<T>git G=$<T>git |B=1 G=$(pwd)/.git git add docs
B=1<T>git X=$<T>git |B=1 X=$(dirname $(pwd)) git
X=1<T>git Y=2<T>git |if X=1 git add .; then Y=2 git; fi
|git status # ; X=1 git
CASES
# Тело heredoc не оболочки — данные, а не команды; перевод строки — граница команды.
[ -z "$(pe $'cat > n.md <<\'EOF\'\nX=1 git add .\nEOF')" ] || { echo "тело heredoc cat дало присваивание"; bad=1; }
[ "$(pe $'echo a\nX=1 git add .')" = "X=1${T}git " ] || { echo "перевод строки не отделил X=1 git"; bad=1; }
[ "$bad" -eq 0 ] || exit 1
# Сквозь стража: неотслеживаемый файл под `docs`, ключ обхода — в кавычках чужого аргумента.
R=$(mktemp -d) || exit 2
trap 'rm -rf "$R"' EXIT
{ git -C "$R" init -q && mkdir "$R/docs" && echo a > "$R/docs/t.md" && git -C "$R" add docs/t.md \
    && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base && echo b > "$R/docs/new.md"; } >/dev/null 2>&1 || exit 2
dec() { jq -cn --arg c "$1" --arg d "$R" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' | bash "$H" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }
[ "$(dec 'git add docs')" = ask ] || { echo "рамка: страж не спросил о git add docs"; exit 2; }
[ "$(dec "grep -E 'a|CLAUDSOUL_ALLOW_ADD_SWEEP=1 git|c' f; git add docs")" = ask ] \
    || { echo "страж снял вопрос ключом из кавычек шаблона grep"; exit 1; }
echo "границы присваиваний — у лексера: кавычки не дают присваиваний, страж спрашивает"
exit 0
