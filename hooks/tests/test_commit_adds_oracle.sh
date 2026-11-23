#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh
# test_commit_adds_oracle.sh — эталон предиката «что команда сама добавит к своему коммиту» (D1087).
#
# Результат: вердикт `executable_commit_adds` (all | tracked | пусто) совпадает с тем, что вошло в коммит, когда форму
#            исполняют настоящие bash и git, — на каждой форме таблицы; ожидаемых ответов руками в таблице нет.
# Проверка результата: bash hooks/tests/test_commit_adds_oracle.sh даёт 0
#
# Почему эталон, а не примеры: предикат держали четыре хука своими выражениями, и три раунда скептика подряд
# (D1084–D1086) находили, что починка по примерам сломала форму, которую прежняя редакция знала
# (`case-2026-10-25-command-form-predicate-checked-by-examples-regressed-each-round`). Пример проверяет то, о чём
# автор подумал; исполнение — то, что сделает git.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/command-scope-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/commit-adds-oracle.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_EDITOR=false

# Мир: отслеживаемые t1, t2 и sub/f правлены («old» → «new»), u — новый неотслеживаемый, s — уже в индексе, чтобы коммит
# состоялся при любой форме. Ответ эталона — по дереву ПЕРВОГО нового коммита: t1, t2 и u в нём — all; t1 и t2 — tracked;
# иначе пусто. Коммита нет — «нет»: форма в таблице обязана коммитить, иначе она ничего не судит.
world() {   # зовётся в подстановке: счётчик в ней наружу не выходит, каталог — свой у каждого мира
    local d; d=$(mktemp -d "$TMP/w.XXXXXX") || return 1
    mkdir -p "$d/sub" && cd "$d" || return 1
    git init -q . && echo old > t1 && echo old > t2 && echo old > sub/f && git add -A && git commit -qm base \
        && echo base2 > b && git add b && git commit -qm base2 \
        && echo new > t1 && echo new > t2 && echo new > sub/f && echo new > u && echo s > s && git add s || return 1
    printf '%s' "$d"
}
oracle() {   # oracle <форма> → all | tracked | пусто | нет
    local d h0 h1 c1
    d=$(world) || { echo "мир"; return; }
    h0=$(git -C "$d" rev-parse HEAD)
    (cd "$d" && bash -c "$1") >/dev/null 2>&1 </dev/null || true  # исполнение формы — предмет: сдвиг HEAD читает строка ниже (D1262)
    h1=$(git -C "$d" rev-parse HEAD)
    [ "$h1" != "$h0" ] || { echo "нет"; return; }
    c1=$(git -C "$d" rev-list --reverse "$h0..$h1" | head -1)
    _in() { [ "$(git -C "$d" show "$c1:$1" 2>/dev/null)" = new ]; }
    if _in t1 && _in t2 && _in u; then echo all; elif _in t1 && _in t2; then echo tracked; fi
}
verdict() { local v rc; v=$(executable_commit_adds "$1"); rc=$?; [ "$rc" -eq 2 ] && echo "спросить-нечем" || echo "$v"; }
show() { printf '%s' "$1" | tr '\n' '⏎'; }

# --- таблица: формы, которые встречались в корпусе команд и у скептиков D1084–D1086 --------------------------------------
FORMS=(
    'git add -A && git commit -m x'           'git add -A; git commit -m x'          'git add -A&&git commit -m x'
    'git add -Av && git commit -m x'          'git add --all;git commit -m x'        'git add . && git commit -m x'
    'git add :/ && git commit -m x'           'git stage -A && git commit -m x'      'git -C . add -A && git commit -m x'
    'git add -A 2>/dev/null && git commit -m x'  '(git add -A) && git commit -m x'   'git add -A && git commit -am x'
    "$(printf 'git add -A && git commit -m "$(cat <<%sEOF%s\nmsg -a\nEOF\n)"' "'" "'")"
    'git add -u && git commit -m x'           'git add --update && git commit -m x'  'git add -u . && git commit -m x'
    'git commit -a -m x'                      'git commit -am x'                     'git commit -qam x'
    'git commit -m x -a'                      'git commit -qm x -a;'                 'git commit --all -m x'
    "git commit -m 'a; b' -a"                 "$(printf 'git commit \\\n  -a -m x')" 'git commit -C HEAD -a'
    'git -c user.name=z commit -a -m x'       'git commit -a --amend -m x'
    'git commit -m x'                         'git commit -m "fix -a bug"'           'git commit -m "add --all option"'
    'git commit -qm "on $(uname -a)"'         'git commit -ma'                       'git commit --amend -m x'
    "git commit --author 't <t@t>' -m y"      'git commit -a --no-all -m x'          'git commit -m x t1'
    'git add t1 && git commit -m x'           'git add ./t1 && git commit -m x'      'git add -A t1 && git commit -m x'
    'git add -An && git commit -m x'          'git add -p </dev/null; git commit -m x'  'git commit -m x && git add -A'
    "$(printf 'git commit -F - <<EOF\ngit add -A\n-a\nEOF')"              'git commit -m "$(printf "m\n-a")"'
    'echo "git add -A" && git commit -m x'    'git commit -m x # -a'                 'git commit -m x; git commit -am y'
)
SEEN=" "
for f in "${FORMS[@]}"; do
    o=$(oracle "$f"); v=$(verdict "$f")
    case "$o" in нет|мир) bad "таблица" "форма не коммитит в песочнице (${o}) — она ничего не судит: $(show "$f")"; continue ;; esac
    SEEN="$SEEN${o:-пусто} "
    [ "$v" = "$o" ] && ok || bad "сверка" "эталон «${o:-пусто}», предикат «${v:-пусто}»: $(show "$f")"
done
# Таблица различает: каждый из трёх исходов встретился у эталона.
for k in all tracked пусто; do
    case "$SEEN" in *" ${k} "*) ok ;; *) bad "охват" "у эталона ни разу не вышло «${k}» — таблица его не судит" ;; esac
done

# --- названные пределы: предикат и эталон расходятся, и это записано в `commit_adds` (write_targets.py) ---------------
# Совпали — предел снят: перенеси форму в таблицу выше и вычеркни предел из докстринга.
LIMITS=(
    'cd sub && git add . && git commit -m x'  'git add * && git commit -m x'  'false && git add -A; git commit -m x'
    'git commit -m "$(git add -A)"'
)
for f in "${LIMITS[@]}"; do
    o=$(oracle "$f"); v=$(verdict "$f")
    [ "$v" != "$o" ] && ok || bad "предел" "предел снят (эталон и предикат дают «${o:-пусто}») — перенеси в таблицу: $(show "$f")"
done

# --- нет разбора — «спросить нечем» (код 2), а не «ничего не добавит» ---------------------------------------------------
( WRITE_TARGETS_PY="$TMP/нет.py" HOME="$TMP/home"; executable_commit_adds 'git add -A && git commit -m x' >/dev/null; exit $? )
[ $? -eq 2 ] && ok || bad "нет разбора" "без файла разбора ответ не «спросить нечем»"

echo "test_commit_adds_oracle: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
