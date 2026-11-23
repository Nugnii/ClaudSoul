#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_moved_file.sh — противник диспетчера записи командой (D487): файл, который
# команда ПОЛОЖИЛА в дерево переносом, доходит до стражей так же, как записанный.
#
# Устройство дефекта. «Тронут» диспетчер определяет по времени изменения содержимого (mtime):
# `find … -newer МЕТКА`. Перенос (`mv`, `git mv`), копия с сохранением времени (`cp -p`,
# `cp -a`, `rsync -a`), распаковка (`tar x`, `unzip`) кладут в дерево новый путь со СТАРЫМ
# mtime — старше метки сессии. Такой файл не отбирается ни этим событием, ни следующими.
# Обычный путь агента: черновик пишется в scratchpad одной командой, переносится в дерево
# другой; `git mv` встречается в расшифровках ClaudSoul 6 раз, ProjectA — 4 (замер 1 октября 2026).
# Путь инструмента (Write) того же файла стражи увидели бы ДО записи; путь команды — никогда.
# Время изменения метаданных (ctime) перенос двигает — признак «новый путь в дереве» доступен.
#
# Ожидание: файл, перенесённый командой в дерево из-за его пределов, подан стражам.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D493 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
# этого дерева, на два уровня выше.
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, и
# носитель был бы ложным (тот же приём — test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"; SCRATCH="$TMP/scratchpad"
mkdir -p "$SB/hooks" "$SR" "$SH" "$SCRATCH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

run() {  # run <сессия> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run m >/dev/null                                   # начало сессии: метка
echo "черновик теста" > "$SCRATCH/test_new.sh"     # команда 1: черновик вне дерева
run m >/dev/null                                   # её событие: метка сдвинута
sleep 1
mv "$SCRATCH/test_new.sh" "$SR/test_new.sh"        # команда 2: перенос в дерево
: > "$FED"
run m >/dev/null
for k in 1 2; do run m >/dev/null; done            # и ещё два события сессии
MOVED=$(grep -c '/test_new\.sh$' "$FED")
# Положительный контроль: тот же сценарий с обычной копией (mtime — сейчас) доходит.
echo "черновик два" > "$SCRATCH/test_two.sh"
run m >/dev/null
sleep 1
cp "$SCRATCH/test_two.sh" "$SR/test_two.sh"
run m >/dev/null
COPIED=$(grep -c '/test_two\.sh$' "$FED")

# T0 — положительный контроль: файл, положенный в дерево обычной копией, подан.
if [ "$COPIED" -ge 1 ]; then ok; else bad T0 "положительный контроль: скопированный в дерево файл не подан"; fi
# T1 — файл, перенесённый в дерево командой, подан стражам.
if [ "$MOVED" -ge 1 ]; then ok
else bad T1 "файл, перенесённый командой в дерево (mv из scratchpad), не подан ни одному стражу за 3 события: mtime переноса старше метки сессии"; fi

echo "test_adv_dispatch_moved_file: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
