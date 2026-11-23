#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/write_targets.py hooks/git-add-sweep-guard.sh
# probe_D1260 — общий лексер разбора команд читает данные как данные в четырёх формах повода (скептик opus D1216, H4):
#   (а) строка `$'…\'…'` — одно слово, `\'` внутри неё кавычку не закрывает;
#   (б) `\;` — литерал, а не граница команды;
#   (в) heredoc `<<\EOF` и с меткой `a-b` — тело данных;
#   (г) `<<` внутри кавычек (`echo "a <<true"`) heredoc не открывает — следующая строка остаётся командой;
#   (д) `<<` внутри `"$(…)"` heredoc открывает: тело сообщения коммита с апострофом — данные (регрессия первой
#       редакции, пойманная сравнением по корпусу);
#   (е) кавычка, открытая строкой выше, переносится: `<<` во второй строке `echo "a` / `b <<X c"` heredoc не открывает;
#   (ж) перенос и после строки-заголовка heredoc: `X="$(cat <<'EOF'` … `)"` закрывает свою подстановку, следующий
#       heredoc — тело данных;
#   (з) `\'` внутри `$'…'` не рвёт слово: `echo $'it\'s' && git commit` — коммит виден (скептик opus D1260, M1).
#   Сквозь стража `git-add-sweep-guard`: ключ обхода в данных (а)–(в) вопроса о `git add docs` не снимает, `--prefix-env`
#   ключа перед `git` не даёт; после (г) цель записи `touch new.txt` видна разбору (страж спрашивает по другому пути).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
W="$PWD/hooks/lib/write_targets.py"; H="$PWD/hooks/git-add-sweep-guard.sh"
[ -f "$W" ] && [ -f "$H" ] && command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 2
R=$(mktemp -d) || exit 2
trap 'rm -rf "$R"' EXIT
{ git -C "$R" init -q && mkdir "$R/docs" && echo a > "$R/docs/t.md" && git -C "$R" add docs/t.md \
    && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base && echo b > "$R/docs/new.md"; } >/dev/null 2>&1 || exit 2
dec() { jq -cn --arg c "$1" --arg d "$R" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' | bash "$H" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }
pe() { printf '%s' "$1" | python3 "$W" --prefix-env 2>/dev/null | grep -c 'CLAUDSOUL_ALLOW_ADD_SWEEP'; }
[ "$(dec 'git add docs')" = ask ] || { echo "рамка: страж не спросил о git add docs" >&2; exit 2; }
[ "$(dec 'CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add docs')" = "" ] || { echo "рамка: ключ обхода перед git не снял вопрос" >&2; exit 2; }
IFS= read -r -d '' A <<'C' || true
echo $'a\'; CLAUDSOUL_ALLOW_ADD_SWEEP=1 git status; ' # '
git add docs
C
IFS= read -r -d '' B <<'C' || true
echo a \; CLAUDSOUL_ALLOW_ADD_SWEEP=1 git status; git add docs
C
IFS= read -r -d '' V1 <<'C' || true
cat <<\EOF
CLAUDSOUL_ALLOW_ADD_SWEEP=1 git status
EOF
git add docs
C
IFS= read -r -d '' V2 <<'C' || true
cat <<'a-b'
CLAUDSOUL_ALLOW_ADD_SWEEP=1 git status
a-b
git add docs
C
IFS= read -r -d '' G <<'C' || true
echo "a <<true"
touch new.txt
true
C
IFS= read -r -d '' D <<'C' || true
git commit -m "$(cat <<'EOF'
fix: it's done
EOF
)" && git push && touch ok.txt
C
IFS= read -r -d '' E <<'C' || true
echo "a
b <<X c"
touch new.txt
C
IFS= read -r -d '' F <<'C' || true
X="$(cat <<'EOF'
body
EOF
)"
cat > f.txt <<'Y'
touch evil.txt
Y
touch ok.txt
C
IFS= read -r -d '' Z <<'C' || true
echo $'it\'s' && git commit -m x
C
bad=""
for f in A B V1 V2; do
    c=${!f}
    [ "$(dec "$c")" = ask ] || bad="$bad $f (страж не спросил);"
    [ "$(pe "$c")" = 0 ] || bad="$bad $f (--prefix-env дал ключ);"
done
printf '%s' "$G" | python3 "$W" 2>/dev/null | grep -qx 'new.txt' || bad="$bad G (команда после << в кавычках не видна);"
[ "$(printf '%s' "$D" | python3 "$W" 2>/dev/null)" = ok.txt ] || bad="$bad D (heredoc в \"\$(…)\" не открыт);"
printf '%s' "$E" | python3 "$W" 2>/dev/null | grep -qx 'new.txt' || bad="$bad E (кавычка строки выше не перенесена);"
printf '%s' "$F" | python3 "$W" 2>/dev/null | grep -qx 'evil.txt' && bad="$bad F (тело второго heredoc прочитано командой);"
[ -n "$(printf '%s' "$Z" | python3 "$W" --commit-dirs 2>/dev/null)" ] || bad="$bad Z (коммит после \$'…\\'…' не виден);"
[ -z "$bad" ] && { echo "восемь форм разобраны как у bash: данные не стали командами, страж спрашивает"; exit 0; }
echo "лексер читает данные как команды:$bad"
exit 1
