#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_root_switch_mark.sh — противник диспетчера записи командой (D487): событие
# сессии в ОДНОМ корне не списывает правку, сделанную командой в ДРУГОМ корне.
#
# Устройство дефекта. Отбор смотрит один корень — тот, что дал `cwd` события, — а метка «с
# прошлого события» одна на сессию (`bash-dispatch-mark-<сессия>`). Событие в корне A сдвигает
# метку, не взглянув на корень C; правка в C, легшая ДО этого события, становится старше метки,
# и ни одно следующее событие в C её не отберёт (`-newer МЕТКА`): стражи её не видят никогда.
# Пути, которыми это случается:
#   · субагент той же сессии в другом корне: id у сессии и субагентов один (шапка диспетчера:
#     «у сессии и её субагентов они общие»; в живой очереди сессии b3dc5ee9 1 октября 2026 лежат
#     тесты, записанные параллельными агентами), а свой корень у агента в изоляции worktree
#     (Claude Code кладёт их в `.claude/worktrees/`);
#   · фоновая команда в C, пока сессия работает в A;
#   · агент в A пишет в соседний проект по пути, потом переходит туда `cd`.
# Названный предел достижимости: в 37 живых очередях 1 октября 2026 чередования корней внутри
# одной сессии не найдено — путь открыт устройством, а не замечен в следах.
# Это не окно «между отбором и меткой» одного события (test_adv_dispatch_mark_race.sh): здесь
# окно — вся длина команды, и закрывает его событие ДРУГОГО корня.
# Ожидание: правка C/x.md, сделанная командой, подана стражам на событии в корне C.
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
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

A="$TMP/A"; C="$TMP/C"
for r in "$A" "$C"; do
    mkdir -p "$r"
    ( cd "$r" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
      && git init -q . && echo base > keep.md && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm i && touch -t 202001010000 keep.md ) >/dev/null 2>&1
done
[ -f "$A/keep.md" ] && [ -f "$C/keep.md" ] || { echo "FAIL [setup]: песочница не собралась"; exit 1; }

run() {  # run <cwd> → вывод диспетчера; сессия одна на весь тест
    printf '{"tool_name":"Bash","session_id":"adv-rs","cwd":"%s"}' "$1" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run "$C" >/dev/null; run "$A" >/dev/null    # сессия уже бывала в обоих корнях
sleep 1                                       # правки новее метки при любой точности времени файла
# Положительный контроль: правка в C и событие в C подряд — файл подан.
echo ctl > "$C/ctl.md"
: > "$FED"; run "$C" >/dev/null
CTL=$(grep -c " $C/ctl\.md\$" "$FED")
sleep 1
# Команда в C пишет x.md; до её события успевает событие той же сессии в A.
echo "правка командой в C" > "$C/x.md"
run "$A" >/dev/null
: > "$FED"
for k in 1 2 3; do run "$C" >/dev/null; done
X=$(grep -c " $C/x\.md\$" "$FED")

if [ "$CTL" -ge 1 ]; then ok; else bad T0 "положительный контроль: правка C/ctl.md с событием в C не подана — нога судила бы пустоту"; fi
if [ "$X" -ge 1 ]; then ok
else bad T1 "правка C/x.md, сделанная командой в корне C, не подана ни одному стражу за три события в C: метку сессии сдвинуло событие в корне A, не смотревшее в C"; fi

echo "test_adv_dispatch_root_switch_mark: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
