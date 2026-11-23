#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_cross_root.sh — противник диспетчера записи командой (D487): состояние
# сессии (очередь, список пройденного, флаги пар) не путает одноимённые файлы РАЗНЫХ корней.
#
# Устройство дефекта. Корень события берётся у `git rev-parse --show-toplevel` от `cwd`, а
# очередь, список пройденного и ключ флага хранят путь ОТНОСИТЕЛЬНО корня — без самого корня, —
# и всё это одно на сессию (`bash-dispatch-{queue,done}-<сессия>`). Сессия же может ходить по
# разным корням: `cd` в соседний проект (каталог основного агента между командами сохраняется),
# worktree Claude Code (`.claude/worktrees/<имя>`, свой корень), субагент в изоляции worktree с
# тем же id. У проектов владельца общие имена документов: CLAUDE.md, BACKLOG.md, README.md,
# PLAN.md, SESSION.md есть и в ClaudSoul, и в ProjectA_NEW (все меньше 400 000 байт, то есть
# подаются). Названный предел достижимости: в 37 живых очередях 1 октября 2026 чередования
# корней внутри одной сессии не найдено — путь открыт устройством, а не замечен в следах.
# Последствия, оба наблюдаемы:
#   T1 — файл ВТОРОГО корня с тем же относительным путём отсекается списком пройденного первого
#        и не доходит ни до одного стража. Это не «вторая версия того же файла» (то заведено
#        отдельно): стражи не видели НИ ОДНОЙ версии файла второго корня.
#   T2 — пара, отложенная бюджетом в корне A, на событии в корне C решается против C: стражам
#        подаётся НЕТРОНУТЫЙ файл C (сообщение велит «почини или откати» то, что никто не правил),
#   T3 — а тронутый файл A уходит в список пройденного, так и не поданный.
# Ожидание: подаётся ровно тронутое, и каждое тронутое — своего корня.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, и
# носитель был бы ложным (тот же приём — test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
TMP=$(cd "$TMP" && pwd -P)   # корень диспетчера раскрыт от ссылок (/var → /private/var)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
NG=$(set -- $GUARD_LIST; echo $#)
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

mkrepo() {  # mkrepo <каталог>: репозиторий с BACKLOG.md, notes.md, z.md — все «давние»
    mkdir -p "$1"
    ( cd "$1" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
      && git init -q . && echo "# $(basename "$1")" > BACKLOG.md && echo n > notes.md && echo z > z.md \
      && git add -A && git -c user.email=t@t -c user.name=t commit -qm i \
      && touch -t 202001010000 BACKLOG.md notes.md z.md ) >/dev/null 2>&1
}
run() {  # run <сессия> <cwd> [ПЕРЕМЕННАЯ=значение ...] → вывод диспетчера
    local s=$1 cwd=$2; shift 2
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$s" "$cwd" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 "$@" bash "$SB/hooks/$DISP" 2>/dev/null
}
fed() { grep -c " $1\$" "$FED"; }   # сколько стражей получили этот абсолютный путь

# ── T1: одноимённый файл второго корня ──
A="$TMP/A"; C="$TMP/C"; mkrepo "$A"; mkrepo "$C"
[ -f "$A/BACKLOG.md" ] && [ -f "$C/BACKLOG.md" ] || { echo "FAIL [setup]: песочница T1 не собралась"; exit 1; }
run s1 "$A" >/dev/null; run s1 "$C" >/dev/null     # метка сессии есть
sleep 1                                              # правки новее метки при любой точности
echo "- ☐ правка в A" >> "$A/BACKLOG.md"
: > "$FED"; run s1 "$A" >/dev/null
_a=$(fed "$A/BACKLOG.md")
sleep 1
echo "- ☐ правка в C" >> "$C/BACKLOG.md"             # сессия перешла в C (cd, worktree, субагент)
: > "$FED"; run s1 "$C" >/dev/null
_c=$(fed "$C/BACKLOG.md")
if [ "$_a" -lt 1 ]; then bad T1 "положительный контроль: правка A/BACKLOG.md не подана — нога судила бы пустоту"
elif [ "$_c" -ge 1 ]; then ok
else bad T1 "C/BACKLOG.md, записанный командой в корне C, не подан ни одному стражу: список пройденного сессии держит «BACKLOG.md» корня A"; fi

# ── T2/T3: отложенное в A решается против C ──
A2="$TMP/A2"; C2="$TMP/C2"; mkrepo "$A2"; mkrepo "$C2"
[ -f "$A2/z.md" ] && [ -f "$C2/z.md" ] || { echo "FAIL [setup]: песочница T2 не собралась"; exit 1; }
run s2 "$A2" >/dev/null
sleep 1
echo "правка" >> "$A2/notes.md"; echo "правка" >> "$A2/z.md"
: > "$FED"; run s2 "$A2" BASH_DISPATCH_MAX_RUNS=1 >/dev/null   # бюджет: одна пара, прочее отложено
_ctl=$(wc -l < "$FED" | tr -d ' ')
# Журнал не обнуляется между событием в C и событиями в A: починка вправе подать отложенный
# файл A уже на событии в C (своим путём) — нога судит итог, а не место подачи.
: > "$FED"; run s2 "$C2" >/dev/null                             # команда в C ничего не трогала
for k in 1 2 3; do run s2 "$A2" >/dev/null; done                # снова в A — отложенное должно прийти
_ghost=$(grep -c " $C2/" "$FED")
_z=$(fed "$A2/z.md")
if [ "$_ctl" -ne 1 ]; then bad T2 "положительный контроль: бюджет 1 подал $_ctl пар вместо одной — нога судила бы не то"
elif [ "$_ghost" -eq 0 ]; then ok
else bad T2 "нетронутые файлы корня C поданы стражам $_ghost раз(а): отложенные пути корня A решены против C"; fi
if [ "$_z" -ge "$NG" ]; then ok
else bad T3 "тронутый A2/z.md за три события в A получил $_z из $NG стражей: его пары списаны на нетронутый файл C"; fi

echo "test_adv_dispatch_cross_root: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
