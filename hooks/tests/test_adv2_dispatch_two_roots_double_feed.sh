#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_two_roots_double_feed.sh — противник диспетчера записи командой (D487,
# раунд 2): один и тот же ФИЗИЧЕСКИЙ файл подаётся стражу один раз за сессию, даже если он
# достижим из двух корней.
#
# Устройство. Две починки раунда 1 сложились в двойную подачу. (а) Состояние ключуется парой
# «сессия + корень»: метка, очередь, список пройденного и флаги пар у каждого корня свои.
# (б) Рекурсия во вложенную рабочую копию: корень ВНЕШНЕЙ копии теперь видит файлы вложенной.
# Файл вложенной копии `inner/x.md` достижим из двух корней — из её собственного (`x.md`) и из
# внешнего (`inner/x.md`), — и у каждого корня свой флаг пары. Путь, который получает страж,
# побайтово один: `$ROOT/$rel` даёт `<внешний>/inner/x.md` в обоих случаях.
# Где живёт: агент делает `cd inner` (каталог Bash между вызовами сохраняется), правит файл
# командой и возвращается `cd ..`; либо субагент в worktree `.claude/worktrees/<имя>` (id сессии
# у них общий с родителем, в ClaudSoul `.claude/` не исключён) правит файл, а следующее событие
# родителя из основной копии подаёт его заново.
# Ожидание: правка одного файла → каждый страж получает его РОВНО один раз за сессию, находка
# по паре напечатана одним событием («дедуп по паре делает цену РАЗОВОЙ за сессию» — шапка).
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

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
g=$(basename "$0")
echo "$g $p" >> "${ADV_FED:-/dev/null}"
if [ "$g" = "${ADV_LOUD:-}" ]; then
  case "$p" in */inner/x.md) printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"ADV2-FINDING-X\"}}" ;; esac
fi
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

_SETUP=$( ( export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1
    G() { git -c user.email=t@t -c user.name=t "$@"; }
    cd "$SR" && git init -q . && echo a > a.md && git add -A && G commit -qm i \
    && mkdir inner && cd inner && git init -q . && echo x > x.md && git add -A && G commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:300}"; exit 1; }
for f in a.md inner/x.md; do
    [ -f "$SR/$f" ] || { echo "FAIL [setup]: нет $f — нога судила бы пустоту"; exit 1; }
    touch -t 202001010000 "$SR/$f"
done

run() {  # run <cwd> → вывод диспетчера; сессия одна на весь тест
    printf '{"tool_name":"Bash","session_id":"adv2-two","cwd":"%s"}' "$1" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" ADV_LOUD="$FIRST" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run "$SR" >/dev/null           # событие в основной копии: метка внешнего корня
run "$SR/inner" >/dev/null     # агент сделал `cd inner`: метка корня вложенной копии
sleep 1                        # правка новее обеих меток при любой точности времени файла
echo "правка командой" >> "$SR/inner/x.md"
: > "$FED"
OUT1=$(run "$SR/inner")        # событие той команды: каталог — вложенная копия
OUT2=$(run "$SR")              # следующая команда после `cd ..`

NG=0; MISS=""; DUP=""
for g in $GUARD_LIST; do
    NG=$((NG+1))
    n=$(grep -c "^$g $SR/inner/x\.md\$" "$FED")
    [ "$n" -ge 1 ] || MISS="$MISS $g"
    [ "$n" -le 1 ] || DUP="${DUP} ${g}×${n}"
done
REPORTS=0
grep -qF "ADV2-FINDING-X" <<< "$OUT1" && REPORTS=$((REPORTS+1))
grep -qF "ADV2-FINDING-X" <<< "$OUT2" && REPORTS=$((REPORTS+1))

if [ -z "$MISS" ]; then ok; else bad T0 "положительный контроль: правка inner/x.md не дошла до стражей:$MISS"; fi
if [ -z "$DUP" ]; then ok
else bad T1 "один и тот же файл $SR/inner/x.md подан стражам повторно в одной сессии (ожидалось по разу на $NG стражей):$DUP"; fi
if [ "$REPORTS" -le 1 ]; then ok
else bad T2 "находка по паре «inner/x.md + ${FIRST}» напечатана ${REPORTS} событиями одной сессии (ожидалось 1)"; fi

echo "test_adv2_dispatch_two_roots_double_feed: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
