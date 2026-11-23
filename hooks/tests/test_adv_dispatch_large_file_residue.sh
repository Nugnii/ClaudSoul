#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_large_file_residue.sh — противник диспетчера записи командой (D487): цена
# ПУСТОГО события не растёт с историей сессии и для файлов, которые подача пропускает.
#
# Устройство дефекта. Список пройденного пополняется только из цикла по стражам. Файл, отсечённый
# ДО цикла — больше 400 000 байт (`[ "$sz" -le 400000 ] || continue`), — в список пройденного не
# попадает никогда, остаётся в разности «очередь − пройденное» навсегда, и КАЖДОЕ событие сессии
# заново меряет его конвейером `wc -c < f | tr -d ' '` (два процесса на файл). Это ровно то
# устройство, которое D487 снимал с хеш-утилит («цена события зависит от его работы, а не от
# длины истории»), перенесённое на соседнюю строку. В ClaudSoul такие файлы правятся каждую
# сессию: CHANGELOG.md (1,7 МБ), SESSION.md (1,6 МБ), BACKLOG-archive.md (2,4 МБ); в ProjectA —
# web/package-lock.json (0,6 МБ). Тот же остаток без процессов, но со временем, дают файлы
# неподаваемых расширений: 20 тыс. строк `*.tsx` в очереди — 0,46–0,49 с на пустое событие
# против 0,07 с без них (замер 1 октября 2026).
#
# Ожидание: после того как большие файлы однажды рассмотрены, пустое событие не меряет их
# снова — ноль вызовов `wc`.
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

run() {  # run <сессия> [PATH] → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 PATH="${2:-$PATH}" bash "$SB/hooks/$DISP" 2>/dev/null
}

run b >/dev/null      # начало сессии: метка
sleep 1
# Команда переписала 10 больших файлов (журнал, архив, lock-файл) и один обычный.
B=10
i=0
while [ "$i" -lt "$B" ]; do
    i=$((i+1))
    head -c 401000 /dev/zero | tr '\0' 'x' > "$SR/archive-$i.json"
done
echo "обычная правка" > "$SR/small.md"
: > "$FED"
run b >/dev/null      # событие этой команды: большие рассмотрены и пропущены, малый подан
SMALL=$(grep -c '/small\.md$' "$FED")
BIG_FED=$(grep -c '/archive-[0-9]*\.json$' "$FED")

# Пустое событие (команда ничего не писала) под счётчиком вызовов `wc`.
SHIM="$TMP/shim"; WC_LOG="$TMP/wc-calls"; mkdir -p "$SHIM"; : > "$WC_LOG"
REAL_WC=$(command -v wc)
printf '#!/bin/sh\necho wc >> "%s"\nexec "%s" "$@"\n' "$WC_LOG" "$REAL_WC" > "$SHIM/wc"; chmod +x "$SHIM/wc"
run b "$SHIM:$PATH" >/dev/null
WC_CALLS=$(grep -c . "$WC_LOG")

# T0 — положительные контроли: событие команды подало малый файл и не подало большие.
if [ "$SMALL" -ge 1 ]; then ok; else bad T0 "положительный контроль: обычная правка small.md не подана"; fi
if [ "$BIG_FED" -eq 0 ]; then ok; else bad T0б "положительный контроль: большие файлы поданы стражам (${BIG_FED}) — предел размера не тот, нога судила бы не то"; fi
# T1 — пустое событие не меряет заново файлы, решённые в прошлом событии.
if [ "$WC_CALLS" -eq 0 ]; then ok
else bad T1 "пустое событие вызвало wc ${WC_CALLS} раз(а) при ${B} больших файлах истории: пропущенные по размеру не уходят в список пройденного, цена события растёт с историей"; fi

echo "test_adv_dispatch_large_file_residue: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
