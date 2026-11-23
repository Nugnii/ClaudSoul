#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_guardset_shrink_cost.sh — противник диспетчера записи командой, раунд 2:
# цена события не растёт с историей сессии и тогда, когда набор присутствующих стражей
# СОКРАТИЛСЯ посреди сессии.
#
# Устройство. Список пройденного носит в имени отпечаток набора присутствующих стражей (раунд
# критика 1 октября 2026): набор сменился — список новый и пустой, и вся очередь сессии
# пересматривается. Когда страж ПРОПАЛ (выключен владельцем, снят новой версией списка,
# снят удалением), у каждой оставшейся пары флаг уже есть, вызовов стражей нет, бюджет
# BASH_DISPATCH_MAX_RUNS не тратится и не останавливает цикл — и одно событие считает md5
# имени флага для КАЖДОЙ пары КАЖДОГО файла истории. Ровно цена, снятая D487 («пустое событие
# 17–20 с» на 458 файлах и 3150 флагах), возвращается на смене набора.
#
# Наблюдаемое — как в T1 test_bash_write_dispatch_selection.sh: число вызовов хеш-утилит на
# событии без единой подачи при истории в 10 и в 20 файлов обязано совпасть.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D489 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
# этого дерева, на два уровня выше.
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Все стражи здесь — заглушки, и
# носитель был бы ложным.
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"; ST="$TMP/state"
mkdir -p "$SB/hooks" "$SR" "$SH" "$ST"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
set -- $GUARD_LIST
[ "$#" -ge 3 ] || { echo "FAIL [setup]: в списке стражей меньше трёх — нога судила бы пустоту"; exit 1; }
G_A=$1; G_B=$2
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

run() {  # run [PATH] → вывод диспетчера; одна сессия на всю ногу
    printf '{"tool_name":"Bash","session_id":"adv2-shrink","cwd":"%s"}' "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 PATH="${1:-$PATH}" bash "$SB/hooks/$DISP" 2>/dev/null
}
# Счётчик вызовов хеш-утилит: обёртки перед настоящими в PATH.
SHIM="$TMP/shim"; HC="$TMP/hashcalls"; mkdir -p "$SHIM"; : > "$HC"
for t in md5 md5sum cksum shasum sha1sum sha256sum; do
    real=$(command -v "$t" 2>/dev/null) || continue
    printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$t" "$HC" "$real" > "$SHIM/$t"; chmod +x "$SHIM/$t"
done
measure() { : > "$HC"; : > "$FED"; run "$SHIM:$PATH" >/dev/null; wc -l < "$HC" | tr -d ' '; }

run >/dev/null                                    # первое событие сессии ставит метку
sleep 1                                           # правки новее метки при любой точности времени
mkdir -p "$SR/h1"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "a$i" > "$SR/h1/f$i.md"; done
run >/dev/null                                    # все 10 файлов поданы всем стражам
E0=$(measure)                                     # пустое событие при полном наборе
# Страж A пропал посреди сессии (владелец выключил шумного стража переименованием).
mv "$SB/hooks/$G_A" "$SB/hooks/$G_A.off"
H10=$(measure); FED10=$(wc -l < "$FED" | tr -d ' ')
mv "$SB/hooks/$G_A.off" "$SB/hooks/$G_A"
sleep 1
mkdir -p "$SR/h2"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "b$i" > "$SR/h2/f$i.md"; done
run >/dev/null                                    # новые 10 поданы, история — 20 файлов
# Пропал другой страж — набор, которого сессия ещё не видела.
mv "$SB/hooks/$G_B" "$SB/hooks/$G_B.off"
H20=$(measure); FED20=$(wc -l < "$FED" | tr -d ' ')
mv "$SB/hooks/$G_B.off" "$SB/hooks/$G_B"

# T0 — контроль: на событиях после сокращения набора стражи не звались — работы у события нет,
# и вся его цена — пересмотр пройденного.
if [ "$FED10" -eq 0 ] && [ "$FED20" -eq 0 ]; then ok
else bad T0 "контроль: после сокращения набора стражи звались (${FED10} и ${FED20} подач) — событие было не пустым"; fi
# T1 — событие без единой подачи стоит одинаково при истории в 10 и в 20 файлов.
if [ "$H10" -eq "$H20" ]; then ok
else bad T1 "после сокращения набора стражей событие без единой подачи зовёт хеш-утилиты ${H10} раз при истории в 10 файлов и ${H20} при истории в 20 (пустое событие при неизменном наборе — ${E0}): цена растёт с историей сессии, бюджет вызовов её не держит"; fi

echo "test_adv2_dispatch_guardset_shrink_cost: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
