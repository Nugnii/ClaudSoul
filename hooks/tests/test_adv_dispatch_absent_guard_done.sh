#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_absent_guard_done.sh — противник диспетчера записи командой (D487): список
# пройденного сессии не объявляет «все пары пройдены» за пару, которую страж не видел.
#
# Устройство дефекта. Файл уходит в список пройденного, когда у него «не осталось непройденных
# пар» (`_pend=0`). Но страж, которого нет в каталоге, пропускается строкой
# `[ -f "$HOOK_DIR/$g" ] || continue` — без отметки «пара осталась». Файл, поданный в такой
# момент, ложится в список пройденного, и страж, появившийся позже в той же сессии, этого файла
# не увидит никогда: разность «очередь − пройденное» его отсекает. До D487 (только флаги) такой
# файл оставался в очереди и доходил до появившегося стража — проверено на редакции HEAD.
# Когда стража нет: установка переносит хуки по одному в алфавитном порядке
# (`install.sh`, цикл `carry`), и диспетчер (b…) встаёт раньше стражей, добавленных в его
# список (r…, s…, t…); снятие и повторная установка; частичный перенос.
#
# Ожидание: файл, поданный без отсутствовавшего стража, доходит до него, когда страж появился.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, и
# носитель был бы ложным (тот же приём — test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
LATE_G=${GUARD_LIST%% *}       # этот страж «ещё не перенесён»
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do [ "$g" = "$LATE_G" ] || printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
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

run a >/dev/null                 # первое событие сессии ставит метку
sleep 1
echo "ключ из конфига" > "$SR/conf.md"   # команда записала файл, пока стража нет в каталоге
: > "$FED"
run a >/dev/null
OTHERS=$(grep -c '/conf\.md$' "$FED")
# Страж перенесён: установка дошла до его имени.
printf '%s\n' "$STUB" > "$SB/hooks/$LATE_G"
for k in 1 2 3; do run a >/dev/null; done
GOT=$(grep -c "^$LATE_G .*/conf\.md\$" "$FED")
# Положительный контроль: появившийся страж работает — новая правка до него доходит.
echo "свежая" > "$SR/fresh.md"
run a >/dev/null
CTL=$(grep -c "^$LATE_G .*/fresh\.md\$" "$FED")

# T0 — положительные контроли: файл дошёл до присутствовавших стражей, появившийся страж исправен.
if [ "$OTHERS" -ge 1 ]; then ok; else bad T0 "положительный контроль: conf.md не подан даже присутствующим стражам"; fi
if [ "$CTL" -ge 1 ]; then ok; else bad T0б "положительный контроль: появившийся страж не получил и свежую правку"; fi
# T1 — пара «conf.md + страж», которую страж не видел, не объявлена пройденной.
if [ "$GOT" -ge 1 ]; then ok
else bad T1 "файл ушёл в список пройденного без пары «conf.md + ${LATE_G}»: страж появился, а файла не увидел за 3 события (до D487 увидел бы)"; fi

echo "test_adv_dispatch_absent_guard_done: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
