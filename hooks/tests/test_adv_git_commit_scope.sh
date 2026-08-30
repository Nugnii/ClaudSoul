#!/usr/bin/env bash
# test_adv_git_commit_scope.sh — адверсариальные атаки на is_git_commit (command-scope-lib.sh)
# и на восемь стражей PreToolUse[Bash], которые через неё детектят `git commit`.
#
# Тесты написаны, чтобы УПАСТЬ на текущем коде. Каждый блок — отдельная атака.
# Ничего не чинит, только фиксирует расхождение «должно / есть».

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

yes_() { # $1=команда $2=имя — ДОЛЖЕН распознать коммит
    if is_git_commit "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$2]: настоящий коммит НЕ распознан"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    fi
}
no_() { # $1=команда $2=имя — ДОЛЖЕН молчать
    if is_git_commit "$1"; then FAIL=$((FAIL + 1))
        echo "FAIL [$2]: текст принят за коммит"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    else PASS=$((PASS + 1)); fi
}

# ---------------------------------------------------------------------------
# Фикстура репозитория: даёт всем восьми стражам повод сработать на коммите.
# Слеплена по образцу test_command_scope.sh (T14-T29).
# ---------------------------------------------------------------------------
CR="$TMP/repo"
mkdir -p "$CR/hooks" "$CR/skills/newone" "$CR/docs" "$CR/scripts" \
         "$CR/.claude-docs/modules" "$CR/lessons/_drafts" "$TMP/state"
git -C "$CR" init -q 2>/dev/null
git -C "$CR" config user.email "t@e"; git -C "$CR" config user.name "t"
printf '# Changelog\n' > "$CR/CHANGELOG.md"
printf '# Plan\n' > "$CR/PLAN.md"
printf '# Arch\n' > "$CR/docs/architecture.md"
{ printf '# Claude\n'; for i in $(seq 1 3000); do printf 'строка контекста номер %s, набивка до порога\n' "$i"; done; } > "$CR/CLAUDE.md"
cat > "$CR/scripts/regen-readme-skills.sh" <<'GEN'
#!/usr/bin/env bash
ROOT="${1:-.}"
F="${README_FILE:-$ROOT/README.md}"
{
    sed -n '1,/HOOKS-TABLE:START/p' "$F"
    for h in "$ROOT"/hooks/*.sh; do sed -n '2p' "$h"; done
    sed -n '/HOOKS-TABLE:END/,$p' "$F"
} > "$F.new" && mv "$F.new" "$F"
GEN
printf '# Readme v1.0.0\n\n<!-- HOOKS-TABLE:START -->\nстарое\n<!-- HOOKS-TABLE:END -->\n' > "$CR/README.md"
git -C "$CR" add -A >/dev/null 2>&1
git -C "$CR" commit -q -m seed 2>/dev/null
for i in 1 2 3 4 5 6; do
    { for l in $(seq 1 40); do printf 'echo "строка %s"\n' "$l"; done; } > "$CR/hooks/mod$i.sh"
done
printf -- '---\nname: newone\ndescription: тест\n---\n\n# Скилл\n' > "$CR/skills/newone/SKILL.md"
git -C "$CR" add -A >/dev/null 2>&1

HOOKS8="code-review-reminder changelog-reminder module-doc-check quality-gate-check
        skill-review-check claude-md-size-check docs-family-check"

_sid() { printf '%s' "$1" | tr -cd '[:alnum:]-' | head -c 48; }
_run() { # $1=хук $2=команда $3=sid
    jq -cn --arg c "$2" --arg cwd "$CR" --arg s "$3" \
        '{session_id:$s, transcript_path:"", cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" LESSONS_DIR="$CR/lessons" bash "$HOOKS_DIR/$1" 2>/dev/null
}
e2e_fires() { # $1=команда $2=метка — все восемь ДОЛЖНЫ отреагировать
    local hook out
    for hook in $HOOKS8; do
        out=$(_run "$hook.sh" "$1" "$(_sid "$2-$hook")")
        if [ -n "$out" ]; then PASS=$((PASS + 1))
        else FAIL=$((FAIL + 1)); echo "FAIL [$2 / $hook]: страж промолчал на настоящем коммите"; fi
    done
}
e2e_silent() { # $1=команда $2=метка — все восемь ДОЛЖНЫ молчать
    local hook out
    for hook in $HOOKS8; do
        out=$(_run "$hook.sh" "$1" "$(_sid "$2-$hook")")
        if [ -z "$out" ]; then PASS=$((PASS + 1))
        else FAIL=$((FAIL + 1))
            echo "FAIL [$2 / $hook]: ложное срабатывание — $(printf '%s' "$out" | tr -d '\n' | head -c 120)"; fi
    done
}

# ===========================================================================
echo "=== АТАКА 1: значение глобальной опции git в кавычках съедает подкоманду ==="
# `-C[[:space:]]+[^[:space:]]+` после вырезания кавычек цепляется за слово `commit`.
# Путь проекта содержит пробел, поэтому кавычки тут не стиль, а необходимость.
A1='git -C "$REPO" commit -m "правка"'
A1B='git -C "/Users/user/My Project/ClaudSoul" commit -m "правка"'
A1C='git --git-dir="/tmp/a b/.git" commit -m x'
A1D='git --work-tree="$WT" commit -am x'
yes_ "$A1"  "A1-a  git -C \"\$REPO\" commit"
yes_ "$A1B" "A1-b  git -C \"<путь с пробелом>\" commit"
yes_ "$A1C" "A1-c  git --git-dir=\"...\" commit"
yes_ "$A1D" "A1-d  git --work-tree=\"\$WT\" commit"
e2e_fires "$A1B" "A1-e2e"

# ===========================================================================
echo "=== АТАКА 2: here-string <<< слово опознан как открытие heredoc ==="
# Регулярка открытия heredoc матчит второй `<` из `<<<`. in_heredoc=1 ставится
# до конца строки и НИКОГДА не снимается — маркер `foo` в теле не встретится.
# Всё, что идёт дальше (включая настоящий коммит), проглатывается.
A2='grep -q needle <<< bar
git add -A
git commit -m "готово"'
A2B='read -r ans <<< yes && git commit -m x'
yes_ "$A2"  "A2-a  <<< bar в первой строке, коммит в третьей"
yes_ "$A2B" "A2-b  <<< yes && git commit"
e2e_fires "$A2" "A2-e2e"

# ===========================================================================
echo "=== АТАКА 3: <<EOF внутри кавычек глушит остаток команды ==="
# Открытие heredoc ищется ДО вырезания кавычек, поэтому упоминание внутри
# строки-аргумента включает режим heredoc и обрезает строку по `<<`.
A3='echo "пиши так: cat << EOF" && git commit -m x'
yes_ "$A3" "A3-a  << EOF в кавычках, коммит после &&"
e2e_fires "$A3" "A3-e2e"

# ===========================================================================
echo "=== АТАКА 4: кавычка, закрытая переводом строки, не вырезается ==="
# awk работает построчно, а `\"[^\"]*\"` не пересекает границу записи. Строка
# внутри многострочных кавычек считается исполняемой.
A4='echo "инструкция для новичка:
git commit -m x
конец" > doc.txt'
no_ "$A4" "A4-a  git commit внутри многострочной строки-аргумента"
e2e_silent "$A4" "A4-e2e"

# ===========================================================================
echo "=== АТАКА 5: экранированная кавычка \\\" рвёт вырезание ==="
# `\"` закрывает кусок для awk, следующий `\"` открывает новый, а текст между
# ними выходит наружу как «исполняемый».
A5='echo "совет: делай \"git commit -m\" вручную"'
A5B='node -e "console.log(\"git commit -m x\")"'
no_ "$A5"  "A5-a  echo с экранированными кавычками"
no_ "$A5B" "A5-b  node -e со вложенными экранированными кавычками"
e2e_silent "$A5" "A5-e2e"

# ===========================================================================
echo "=== АТАКА 6: комментарий # ... git commit считается командой ==="
# Комментарии не вырезаются вовсе: слева от `git` пробел — сигнатура совпала.
A6='make test  # если зелено, дальше git commit -m x'
A6B='# сначала прогнать тесты, потом git commit
bash hooks/tests/run_all.sh'
no_ "$A6"  "A6-a  хвостовой комментарий с git commit"
no_ "$A6B" "A6-b  строка-комментарий с git commit"
e2e_silent "$A6" "A6-e2e"

# ===========================================================================
echo "=== АТАКА 7: подоболочка (git commit ...) ==="
# `(` нет среди разделителей слева, а `\$\(` требует именно `\$(`.
A7='(git commit -m x)'
yes_ "$A7" "A7-a  (git commit -m x)"

# ===========================================================================
echo "=== АТАКА 8: имя команды в кавычках — граница, закреплённая намеренно ==="
# Находка верна по механике: допущение шапки («имя команды никогда не бывает внутри
# кавычек») для `-c` и `ssh` не держится — там кавычки содержат КОМАНДУ. Но исходы
# у двух случаев разные, и оба закреплены здесь как ожидаемые, а не как дефект.
#
# `ssh host "… git commit"` — коммит идёт на ДРУГОЙ машине. Локальные стражи читают
# локальный индекс, который к тому коммиту отношения не имеет: сработай они, весь их
# вывод был бы про чужой репозиторий. Молчание — верное поведение, а не пропуск.
#
# `bash -c "git commit"` — настоящий локальный коммит, и он действительно проходит
# мимо. Достижимость замерена, а не оценена: по всем расшифровкам 2730 упоминаний
# `git commit`, из них внутри `bash -c` — ноль. Разбор вложенной команды стоит
# рекурсии сканера; заводить его до первого живого случая — цена без спроса.
# Тест держит границу: когда случай появится, он и покраснеет.
A8='bash -c "git commit -m x"'
A8B='ssh build@host "cd /srv/app && git commit -m x"'
no_ "$A8"  "A8-a  bash -c: известная граница, разбор вложенной команды не заведён"
no_ "$A8B" "A8-b  ssh: коммит на другой машине — молчим намеренно"

# ===========================================================================
echo "=== АТАКА 9: перенос строки обратным слешем ==="
# Продолжение строки склеивается shell'ом, но не awk: `git` и `commit`
# оказываются в разных записях.
A9='git \
  commit -m "длинное сообщение"'
yes_ "$A9" "A9-a  git \\<перенос> commit"

# ===========================================================================
echo "=== АТАКА 10: счётчик коммитов knowledge-capture-reminder ==="
# Цена ошибки здесь выше: хук не напоминает, а СЧИТАЕТ коммиты за сессию.
# Комментарий и многострочная строка накручивают счётчик до порога.
# Вывод копится по всем итерациям: напоминание печатается на итерации, где взят
# порог (5-я), а не на последней. Присваивание вместо накопления затирало бы его
# пустотой седьмой итерации и красило бы тест зелёным независимо от поведения.
KCR_OUT=""
for _ in 1 2 3 4 5 6 7; do
    KCR_OUT="$KCR_OUT$(_run knowledge-capture-reminder.sh "$A6" "adv-kcr-comment")"
done
if [ -z "$KCR_OUT" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1))
    echo "FAIL [A10-a]: комментарий накрутил счётчик коммитов — $(printf '%s' "$KCR_OUT" | tr -d '\n' | head -c 120)"; fi

KCR_REAL=""
for _ in 1 2 3 4 5 6 7; do
    KCR_REAL="$KCR_REAL$(_run knowledge-capture-reminder.sh "$A1B" "adv-kcr-real")"
done
if [ -n "$KCR_REAL" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1))
    echo "FAIL [A10-b]: настоящие коммиты с git -C \"путь\" не сосчитаны, порог не взят"; fi

echo ""
echo "adversarial git-commit scope: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
