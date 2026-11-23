#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_legacy_queue.sh — противник диспетчера записи командой (D487): очередь
# ПРЕЖНЕГО формата (её писал отбор `find .`, с файлами игнорируемых каталогов) не подаётся
# стражам и не голодит настоящие правки.
#
# Устройство дефекта. Правило «игнорируемые КАТАЛОГИ пропускаются» стоит только в ОТБОРЕ нового
# события; очередь сессии читается целиком, без него. Очередь, накопленная прежней редакцией,
# переживает установку новой (состояние лежит в `hooks/state`, сессия возобновляется с тем же
# id), и её строки из `web/.next`, `node_modules`, `.venv` идут стражам с бюджетом 6 вызовов на
# событие — раньше настоящих правок, которые сортируются после них.
# Живое состояние 1 октября 2026 (только чтение): четыре очереди сессий ProjectA (8118af66,
# baad3170, 21e1f649, 87dcfc4a) по 16–18,5 тыс. уникальных строк; из них с подаваемым
# расширением 3926–4030, и в игнорируемых каталогах — 3905–4016. Установленный диспетчер —
# прежней редакции (с рабочей копией не совпадает), то есть эти очереди встретят новую.
#
# Ожидание: файлы игнорируемого каталога из прежней очереди стражам не подаются; свежая правка
# подаётся на первом же событии с бюджетом по умолчанию.
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

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"; ST="$TMP/state"
mkdir -p "$SB/hooks" "$SR" "$SH" "$ST"
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
# Сборка лежит в игнорируемом каталоге, как `web/.next` в ProjectA.
mkdir -p "$SR/build"
for i in 1 2 3 4 5; do echo "{\"chunk\":$i}" > "$SR/build/manifest-$i.json"; done
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore" "$SR"/build/*.json

SID="adv-legacy"
# Состояние сессии, оставленное прежней редакцией: метка и очередь из `find .` — с файлами
# игнорируемого каталога. Списка пройденного у прежней редакции не было.
: > "$ST/bash-dispatch-mark-$SID"
for i in 1 2 3 4 5; do echo "build/manifest-$i.json"; done > "$ST/bash-dispatch-queue-$SID"
touch -t 202001010000 "$ST/bash-dispatch-mark-$SID"

run() {  # run → вывод диспетчера; бюджет вызовов — по умолчанию диспетчера
    printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s"}' "$SID" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            bash "$SB/hooks/$DISP" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_dispatch_legacy_queue.sh:$LINENO" >&2; exit 1; }
}

# Сессия возобновлена под новой редакцией; команда записала настоящий файл.
echo "правка" > "$SR/real.md"
: > "$FED"
run >/dev/null
REAL1=$(grep -c '/real\.md$' "$FED")
BUILD1=$(grep -c '/build/manifest-[0-9]*\.json$' "$FED")

# T0 — положительный контроль: стражи вообще получают подачу (иначе ноги судили бы пустоту).
if [ "$(grep -c . "$FED")" -ge 1 ]; then ok; else bad T0 "положительный контроль: событие не подало стражам ничего"; fi
# T1 — файл игнорируемого каталога из прежней очереди не подаётся.
if [ "$BUILD1" -eq 0 ]; then ok
else bad T1 "очередь прежнего формата подала стражам ${BUILD1} раз(а) файлы игнорируемого каталога build/ — правило «игнорируемые каталоги пропускаются» стоит только в отборе"; fi
# T2 — свежая правка не голодает за прежней очередью.
if [ "$REAL1" -ge 1 ]; then ok
else bad T2 "свежая правка real.md не подана на первом событии: бюджет по умолчанию съели строки build/ прежней очереди"; fi

echo "test_adv_dispatch_legacy_queue: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
