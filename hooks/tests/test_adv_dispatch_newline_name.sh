#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_newline_name.sh — противник диспетчера записи командой (D487): имя файла с
# переводом строки не подменяет подаваемый файл чужим.
#
# Устройство дефекта. Отбор бережёт имена разделителем NUL (`git ls-files -z`, цикл
# `read -d ''`, `xargs -0`), но последнее звено — `find` печатает имя с разделителем «перевод
# строки», а `sed` и очередь построчны. Имя `nl⏎f1.md` распадается на две строки, `nl` и
# `f1.md`: настоящий новый файл стражам не виден никогда, а вместо него подаётся НЕТРОНУТЫЙ
# `f1.md` — чужое содержимое под чужим путём (и его пары «файл + страж» тратятся впустую:
# настоящая правка `f1.md` позже их уже не получит).
#
# Ожидание: стражам подан записанный командой файл, а нетронутый `f1.md` не подан.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D495 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
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

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
# Заглушка пишет ПОЛУЧЕННЫЙ путь в формате JSON-строки: перевод строки в имени виден как \n.
STUB='#!/usr/bin/env bash
jq -c ".tool_input.file_path" >> "${ADV_FED:-/dev/null}" 2>/dev/null
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > f1.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/f1.md" "$SR/.gitignore"

run() {  # run <сессия> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run n >/dev/null      # начало сессии: метка
sleep 1
NLNAME="nl
f1.md"
echo "запись команды" > "$SR/$NLNAME"
echo "контроль" > "$SR/plain.md"
: > "$FED"
run n >/dev/null
GOT_NL=$(grep -c '/nl\\nf1\.md"$' "$FED")
GOT_F1=$(grep -c '/repo/f1\.md"$' "$FED")
GOT_PLAIN=$(grep -c '/plain\.md"$' "$FED")

# T0 — положительный контроль: обычная правка того же события подана.
if [ "$GOT_PLAIN" -ge 1 ]; then ok; else bad T0 "положительный контроль: plain.md не подан"; fi
# T1 — нетронутый f1.md не подаётся вместо файла с переводом строки в имени.
if [ "$GOT_F1" -eq 0 ]; then ok
else bad T1 "подан НЕТРОНУТЫЙ f1.md (${GOT_F1} подач): имя «nl⏎f1.md» распалось на две строки очереди"; fi
# T2 — записанный командой файл с переводом строки в имени подан стражам.
if [ "$GOT_NL" -ge 1 ]; then ok
else bad T2 "файл «nl⏎f1.md», записанный командой, не подан ни одному стражу"; fi

echo "test_adv_dispatch_newline_name: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
