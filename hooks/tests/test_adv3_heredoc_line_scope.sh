#!/usr/bin/env bash
# test_adv3_heredoc_line_scope.sh — адверсариальный раунд 3: разбор heredoc в
# `command-scope-lib.sh` теряет и придумывает команды.
#
# Раунды 1-2 закрыли «heredoc искался до вырезания кавычек» и «here-string принимался
# за heredoc». Осталась целая строка ОТКРЫТИЯ heredoc и всё, что за ней:
#
#   A1  `… <<'MSG' && git push …`  — при открытии heredoc сканер делает `i = n`,
#       то есть выбрасывает ОСТАТОК СВОЕЙ строки. Но тело heredoc начинается со
#       СЛЕДУЮЩЕЙ строки: всё после `<<MARKER` — обычные команды, они исполняются.
#   A2  два heredoc в одной строке — запомнен только первый маркер; после его
#       терминатора тело ВТОРОГО попадает в «исполняемую часть» как команды.
#   A3  терминатор сверяется после `sub(/^[[:space:]]+/)` и `sub(/[[:space:]]+$/)`.
#       Простой `<<` требует маркер строго с начала строки и без хвоста: отступной
#       `  EOF` внутри тела закрывает heredoc досрочно, и остаток тела «исполняется».
#   A4  `<<\EOF` — законная запись (равна `<<'EOF'`), но регулярка маркера не
#       допускает обратный слеш: heredoc не опознан, всё тело «исполняется».
#
# Тесты написаны, чтобы УПАСТЬ на текущем коде. Ничего не чинят.
#
# Достижимость замерена по 18 579 реальным вызовам Bash из ~/.claude/projects
# (самозагрязнение прошлыми адверсариальными прогонами отфильтровано):
#   A1 — 25 команд, из них 9 с `git push`/`git tag` после открытия heredoc;
#        семь штук — рабочая форма `git commit -q -F - <<'MSG' && git push -q origin main`;
#   A2 — 1 команда (двойной коммит с двумя сообщениями через heredoc);
#   A3 — 0; A4 — 0.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
source "$HOOKS_DIR/command-scope-lib.sh"

_show() { printf '%s' "$1" | tr '\n' '~'; }

yes_() { # $1=команда $2=имя — is_git_commit ДОЛЖЕН распознать
    if is_git_commit "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$2]: настоящий коммит НЕ распознан"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    fi
}
exec_has() { # $1=команда $2=подстрока $3=имя — исполняемая часть ДОЛЖНА её содержать
    local e; e=$(executable_part "$1")
    if grep -qF -- "$2" <<< "$e"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$3]: исполняемая часть потеряла «$2»"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$e")]"
    fi
}
exec_lacks() { # $1=команда $2=подстрока $3=имя — исполняемой части НЕ должно её содержать
    local e; e=$(executable_part "$1")
    if grep -qF -- "$2" <<< "$e"; then FAIL=$((FAIL + 1))
        echo "FAIL [$3]: текст «$2» попал в исполняемую часть"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$e")]"
    else PASS=$((PASS + 1)); fi
}

# ---------------------------------------------------------------------------
# Фикстура: репозиторий, где у стражей есть повод сработать.
# ---------------------------------------------------------------------------
CR="$TMP/repo"
mkdir -p "$CR/hooks" "$CR/scripts" "$CR/docs" "$CR/.claude-docs/modules" \
         "$CR/lessons/_drafts" "$TMP/state"
git -C "$CR" init -q 2>/dev/null
git -C "$CR" config user.email "t@e"; git -C "$CR" config user.name "t"
printf '# Changelog\n' > "$CR/CHANGELOG.md"
printf '#!/usr/bin/env bash\necho ci\n' > "$CR/scripts/ci-status.sh"
git -C "$CR" add -A >/dev/null 2>&1
git -C "$CR" commit -q -m seed 2>/dev/null
for i in 1 2 3 4 5 6; do
    { for l in $(seq 1 40); do printf 'echo "строка %s"\n' "$l"; done; } > "$CR/hooks/mod$i.sh"
done
git -C "$CR" add -A >/dev/null 2>&1

_sid() { printf '%s' "$1" | tr -cd '[:alnum:]-' | head -c 48; }
_run() { # $1=хук $2=команда $3=sid
    jq -cn --arg c "$2" --arg cwd "$CR" --arg s "$3" \
        '{session_id:$s, transcript_path:"", cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" LESSONS_DIR="$CR/lessons" bash "$HOOKS_DIR/$1" 2>/dev/null
}
hook_fires() { # $1=хук $2=команда $3=имя
    if [ -n "$(_run "$1" "$2" "$(_sid "$3")")" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: $1 промолчал на настоящем действии"
        echo "       executable_part: [$(_show "$(executable_part "$2")")]"; fi
}
hook_silent() { # $1=хук $2=команда $3=имя
    local out; out=$(_run "$1" "$2" "$(_sid "$3")")
    if [ -z "$out" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$3]: $1 сработал на тексте — $(printf '%s' "$out" | tr -d '\n' | head -c 150)"
        echo "       executable_part: [$(_show "$(executable_part "$2")")]"; fi
}

# ===========================================================================
echo "=== АТАКА 1: открытие heredoc выбрасывает ОСТАТОК своей строки ==="
# Тело heredoc начинается со СЛЕДУЮЩЕЙ строки. Всё, что стоит после `<<MARKER`
# на строке открытия, — обычные команды, и они исполняются.
A1_COMMIT='cat > /tmp/adv3-note.md <<'"'"'EOF'"'"' && git commit -m "правка"
заметка
EOF'
yes_ "$A1_COMMIT" "A1-a  git commit после открытия heredoc"
exec_has "$A1_COMMIT" 'git commit' "A1-b  исполняемая часть сохранила git commit"

# Настоящая форма из истории (ProjectA_NEW, семь вызовов): сообщение коммита
# приходит heredoc'ом, а следом в той же строке идёт push.
A1_PUSH='cd /repo && git add -A && git commit -q -F - <<'"'"'MSG'"'"' && git push -q origin main 2>&1 | tail -2
fix(web): правка
MSG'
exec_has "$A1_PUSH" 'git push' "A1-c  исполняемая часть сохранила git push"
hook_fires ci-check-reminder.sh "$A1_PUSH" "A1-d  ci-check-reminder видит push после heredoc"

# Разрушительная команда в той же строке — та же потеря, цена другая.
A1_RM='cat > /tmp/adv3-x.txt <<'"'"'EOF'"'"' ; rm -rf /tmp/adv3-old
данные
EOF'
exec_has "$A1_RM" 'rm -rf' "A1-e  исполняемая часть сохранила rm -rf"
hook_fires trust-guard.sh "$A1_RM" "A1-f  trust-guard видит rm -rf после открытия heredoc"

# ===========================================================================
echo "=== АТАКА 2: второй heredoc в одной строке — его тело «исполняется» ==="
# Форма взята из истории этого репозитория: два коммита подряд, у каждого своё
# сообщение через heredoc. Маркер запоминается только первый; после его
# терминатора тело второго сообщения читается как команды. Сообщений коммитов
# ClaudSoul с текстом `rm -rf` / `git push --force` / `reset --hard` — пять.
A2='cd /repo && git add hooks/ && git commit -q -F - <<'"'"'MSG'"'"' && git add CHANGELOG.md && git commit -q -F - <<'"'"'MSG2'"'"' && git log --oneline -2
fix(hooks): страж перестал видеть кавычки
MSG
docs(backlog): D50 закрыт
Проверено вручную: rm -rf /tmp/claudsoul-verify отработал как надо.
MSG2'
exec_lacks "$A2" 'rm -rf' "A2-a  текст второго сообщения не должен быть исполняемым"
hook_silent trust-guard.sh "$A2" "A2-b  trust-guard молчит на тексте сообщения коммита"

# ===========================================================================
echo "=== АТАКА 3: отступной терминатор закрывает heredoc досрочно ==="
# Простой `<<` (без `-`) требует маркер строго с начала строки. `  EOF` внутри
# тела — обычный текст. Сканер же сперва срезает пробелы и считает это концом.
A3='cat > /tmp/adv3-doc.md <<'"'"'EOF'"'"'
Пример записи файла:
  cat > f <<TXT
  EOF
  rm -rf /tmp/adv3-old
EOF'
exec_lacks "$A3" 'rm -rf' "A3-a  тело после отступного EOF не должно быть исполняемым"
hook_silent trust-guard.sh "$A3" "A3-b  trust-guard молчит на теле heredoc с отступным EOF"

# Хвостовой пробел на терминаторе — та же ошибка с другой стороны. Строка `EOF `
# (с пробелом на конце) heredoc НЕ закрывает; собирается printf, чтобы пробел не
# потерялся при правке файла.
A3B=$(printf 'cat > /tmp/adv3-doc2.md <<%sEOF%s\nпример терминатора:\nEOF \ngit commit -m x\nEOF\n' "'" "'")
exec_lacks "$A3B" 'git commit' "A3-c  терминатор с хвостовым пробелом не закрывает heredoc"

# ===========================================================================
echo "=== АТАКА 4: <<\\EOF — маркер, экранированный обратным слешем ==="
# `<<\EOF` равнозначно `<<'EOF'` (подстановки в теле выключены). Регулярка
# маркера допускает `'` и `\"`, но не `\`, поэтому heredoc не опознаётся вовсе.
A4='cat > /tmp/adv3-note2.md <<\EOF
как чинили: git commit -m x, потом rm -rf /tmp/adv3-old
EOF'
exec_lacks "$A4" 'git commit' "A4-a  тело <<\\EOF не должно быть исполняемым"
exec_lacks "$A4" 'rm -rf'     "A4-b  то же для разрушительной подписи"
hook_silent trust-guard.sh "$A4" "A4-c  trust-guard молчит на теле <<\\EOF"

echo ""
echo "adv3 heredoc line scope: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
