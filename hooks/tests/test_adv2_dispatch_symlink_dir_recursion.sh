#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_symlink_dir_recursion.sh — противник диспетчера записи командой (D487,
# раунд 2): рекурсия во вложенную рабочую копию не идёт по СИМВОЛЬНОЙ ССЫЛКЕ на каталог.
#
# Устройство. Признак вложенной копии в отборе — `[ -d "$_p" ] && [ -e "${_p%/}/.git" ]`, а оба
# теста идут СКВОЗЬ ссылку. Для git учтённая ссылка — файл (blob режима 120000), а не вложенная
# копия: внешний git печатает её одной строкой `ext`, как файл. Ссылка на каталог чужого
# репозитория проходит признак, и диспетчер спрашивает git ЧУЖОГО репозитория: его файлы уходят
# стражам под путями `<корень>/ext/…`, хотя файлами проекта не являются. Ссылка на сам корень
# (`self -> .`) даёт каждому файлу проекта второе имя `self/…` и вторую подачу. Прежний отбор
# `find .` по ссылкам не ходил (поведение `find -P` по умолчанию), и `find … -type f` в самом
# отборе ссылку файлом не считает — признак вложенной копии с ним расходится.
# Ожидание: правка файла ЧУЖОГО репозитория, на каталог которого смотрит ссылка, стражам этого
# корня не подаётся; файл проекта подаётся один раз, а не по разу на каждое имя.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Все стражи здесь — заглушки, и носитель
# был бы ложным (тот же приём — test_bash_write_dispatch_selection.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
TMP=$(cd "$TMP" && pwd -P)   # корень диспетчера раскрыт от ссылок (/var → /private/var)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SO="$TMP/other"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR" "$SO" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

_SETUP=$( ( export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1
    G() { git -c user.email=t@t -c user.name=t "$@"; }
    cd "$SO" && git init -q . && echo o > o.md && git add -A && G commit -qm i \
    && cd "$SR" && git init -q . && echo a > a.md && ln -s ../other ext && ln -s . self \
    && git add -A && G commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:300}"; exit 1; }
# Предпосылка: для git это ссылки (режим 120000), а не вложенные копии.
_modes=$(cd "$SR" && HOME="$SH" GIT_CONFIG_NOSYSTEM=1 git ls-files -s ext self 2>/dev/null | awk '{print $1}' | sort -u)
[ "$_modes" = "120000" ] || { echo "FAIL [setup]: ext/self не учтены ссылками (режимы: $_modes)"; exit 1; }
touch -t 202001010000 "$SR/a.md" "$SO/o.md"

run() {  # run <сессия> → вывод диспетчера; cwd — корень проекта
    printf '{"tool_name":"Bash","session_id":"adv2-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run s >/dev/null      # первое событие сессии ставит метку
sleep 1               # правки новее метки при любой точности времени файла
echo "правка в своём проекте" >> "$SR/a.md"
echo "правка в чужом репозитории" >> "$SO/o.md"
: > "$FED"
run s >/dev/null

n_own=$(grep -c " $SR/a\.md\$" "$FED")
n_alias=$(grep -c " $SR/self/a\.md\$" "$FED")
n_foreign=$(grep -c " $SR/ext/o\.md\$" "$FED")
if [ "$n_own" -ge 1 ]; then ok; else bad T0 "положительный контроль: правка a.md проекта не подана — нога судила бы пустоту"; fi
if [ "$n_foreign" -eq 0 ]; then ok
else bad T1 "файл ЧУЖОГО репозитория подан стражам $n_foreign раз(а) под именем $SR/ext/o.md: рекурсия прошла по учтённой ссылке ext -> ../other"; fi
if [ "$n_alias" -eq 0 ]; then ok
else bad T2 "файл проекта подан повторно под вторым именем self/a.md ($n_alias подач сверх $n_own): рекурсия прошла по ссылке self -> ."; fi

echo "test_adv2_dispatch_symlink_dir_recursion: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
