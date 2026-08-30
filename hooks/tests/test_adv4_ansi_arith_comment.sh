#!/usr/bin/env bash
# test_adv4_ansi_arith_comment.sh — адверсариальный раунд 4: три места, где сканер
# читает символ не так, как его читает bash.
#
#   A4  `$'…'` (ANSI-C). Внутри такой строки `\'` НЕ закрывает её — это литеральный
#       апостроф. Сканер входит в `in_s` по открывающей кавычке и там же объявлено:
#       «внутри одинарных кавычек ничего не экранируется». Для обычных `'…'` это
#       верно, для `$'…'` — нет. Состояние инвертируется: сканер считает строку
#       закрытой там, где bash её продолжает, и открытой там, где bash закрыл, —
#       остаток команды съедается как «содержимое кавычек».
#   A5  `$(( a << b ))`. Арифметический сдвиг принимается за открытие heredoc:
#       регулярка маркера видит `<<` и идентификатор справа. Heredoc открывается
#       навсегда (терминатора с таким именем в команде нет), и ВСЕ последующие
#       строки уходят в «тело» — настоящие команды идут мимо стражей.
#   A6  Комментарий после `;`, `|`, `&` без пробела. Bash считает `#` началом
#       комментария после любого разделителя слов; сканер требует пробел слева или
#       начало строки, поэтому остаток комментария остаётся «командой».
#
# Тесты написаны, чтобы УПАСТЬ на текущем коде. Ничего не чинят.
#
# Достижимость замерена по 20 224 реальным вызовам Bash из ~/.claude/projects
# (записи собственных адверсариальных прогонов отфильтрованы):
#   A4 — 218 живых команд используют `$'…'`; форма с `\'` внутри — 1 живая;
#   A5 — 0 живых (2 попадания — записи этого же прогона);
#   A6 — 61 живое совпадение `[;|&)]#`, но все просмотренные лежат ВНУТРИ кавычек
#        (шаблоны grep/regex), то есть комментариями не являются: настоящих 0.
#   Оба хвостовых случая — дефекты разбора без замеренного живого входа; правятся
#   вместе с A1-A3 из соседнего файла, потому что механизм тот же (состояние).

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

yes_() {
    if is_git_commit "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$2]: настоящий коммит НЕ распознан"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    fi
}
no_() {
    if is_git_commit "$1"; then FAIL=$((FAIL + 1))
        echo "FAIL [$2]: коммитом сочтён текст"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    else PASS=$((PASS + 1)); fi
}
exec_has() {
    local e; e=$(executable_part "$1")
    if grep -qF -- "$2" <<< "$e"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$3]: исполняемая часть потеряла «$2»"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$e")]"
    fi
}
exec_lacks() {
    local e; e=$(executable_part "$1")
    if grep -qF -- "$2" <<< "$e"; then FAIL=$((FAIL + 1))
        echo "FAIL [$3]: текст «$2» попал в исполняемую часть"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$e")]"
    else PASS=$((PASS + 1)); fi
}

CR="$TMP/repo"
mkdir -p "$CR/lessons/_drafts" "$TMP/state"
git -C "$CR" init -q 2>/dev/null
git -C "$CR" config user.email "t@e"; git -C "$CR" config user.name "t"
printf '# Changelog\n' > "$CR/CHANGELOG.md"
git -C "$CR" add -A >/dev/null 2>&1
git -C "$CR" commit -q -m seed 2>/dev/null

_sid() { printf '%s' "$1" | tr -cd '[:alnum:]-' | head -c 48; }
_run() {
    jq -cn --arg c "$2" --arg cwd "$CR" --arg s "$3" \
        '{session_id:$s, transcript_path:"", cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" LESSONS_DIR="$CR/lessons" bash "$HOOKS_DIR/$1" 2>/dev/null
}
hook_fires() {
    if [ -n "$(_run "$1" "$2" "$(_sid "$3")")" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: $1 промолчал на настоящем действии"
        echo "       executable_part: [$(_show "$(executable_part "$2")")]"; fi
}
hook_silent() {
    local out; out=$(_run "$1" "$2" "$(_sid "$3")")
    if [ -z "$out" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$3]: $1 сработал на тексте — $(printf '%s' "$out" | tr -d '\n' | head -c 150)"
        echo "       executable_part: [$(_show "$(executable_part "$2")")]"; fi
}

# ===========================================================================
echo "=== АТАКА 4: \$'…' — обратный слеш перед апострофом её не закрывает ==="
# bash: `$'don\'t'` — одно слово `don't`, дальше идёт разделитель и команда.
# Сканер: закрывает строку на `\'`, потом снова открывает на завершающей `'`
# и глотает всё до конца команды.
A4_RM="echo \$'don\\'t' ; rm -rf /tmp/adv4-old"
exec_has "$A4_RM" 'rm -rf' "A4-a  команда после \$'…' не съедена"
hook_fires trust-guard.sh "$A4_RM" "A4-b  trust-guard видит rm -rf после \$'…'"

A4_GC="echo \$'don\\'t' && git commit -m fix"
yes_ "$A4_GC" "A4-c  коммит после \$'…' распознан"
exec_has "$A4_GC" 'git commit' "A4-d  исполняемая часть сохранила коммит"

# ===========================================================================
echo "=== АТАКА 5: \$(( a << b )) принимается за открытие heredoc ==="
A5_RM=$(cat <<'CMD'
MASK=$((1 << bits))
rm -rf /tmp/adv4-build
CMD
)
exec_has "$A5_RM" 'rm -rf' "A5-a  строка после арифметического сдвига не тело heredoc"
hook_fires trust-guard.sh "$A5_RM" "A5-b  trust-guard видит rm -rf после \$((1 << bits))"

A5_GC=$(cat <<'CMD'
SHIFT=$(( flags << n ))
git commit -m "правка"
CMD
)
yes_ "$A5_GC" "A5-c  коммит после арифметического сдвига распознан"
exec_has "$A5_GC" 'git commit' "A5-d  исполняемая часть сохранила коммит"

# ===========================================================================
echo "=== АТАКА 6: комментарий сразу после ; | & не вырезается ==="
A6_GC='ls ;# git commit -m "не выполняется"'
no_ "$A6_GC" "A6-a  комментарий после ; — не коммит"
exec_lacks "$A6_GC" 'git commit' "A6-b  комментарий не должен быть исполняемой частью"

# `|#` в bash — синтаксическая ошибка (конвейер без правой части), поэтому взяты
# две другие законные формы: фоновый `&` и закрывающая скобка группы.
A6_AMP='ls &# git commit -m "не выполняется"'
no_ "$A6_AMP" "A6-c  комментарий после & — не коммит"

A6_PAREN='(ls)# git commit -m "не выполняется"'
no_ "$A6_PAREN" "A6-f  комментарий после ) — не коммит"

A6_RM='ls ;# rm -rf /tmp/adv4-build'
exec_lacks "$A6_RM" 'rm -rf' "A6-d  разрушительная подпись в комментарии не исполняется"
hook_silent trust-guard.sh "$A6_RM" "A6-e  trust-guard молчит на комментарии"

echo ""
echo "adv4 ansi/arith/comment: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
