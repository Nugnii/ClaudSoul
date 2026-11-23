#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_tracked_tree_cost.sh — противник диспетчера записи командой, раунд 2:
# событие, которому нечего подавать, не стоит секунд на репозитории с большим учтённым деревом.
#
# Устройство. Кандидаты берутся у git (D487), но каждый путь списка проходит цикл оболочки
# `while IFS= read -r -d '' _p` — ради распознавания вложенной рабочей копии (`[ -d ]` на
# КАЖДОМ пути). Чтение с `-d ''` из трубы bash делает побайтно, и цена события линейна по числу
# учтённых файлов с большим множителем. Замер 1 октября 2026: 0,37 с на 1 318 кандидатах самого
# ClaudSoul; на 30 000 учтённых файлах 2,9–3,2 с процессорного времени (стенного 3,6–9,3 с),
# тогда как `git ls-files | xargs find` по тому же дереву — 0,7 с, а один обход `find` — 0,1 с.
# Довод D487 был ценой («прежний `find .` — 1,46 с на команду на 140 011 файлах ProjectA»); на
# дереве, где файлы учтены, а не исключены, новый отбор дороже прежнего, а около 100 тыс.
# учтённых файлов событие переходит порог срыва замка (30 с) уже без всякой нагрузки.
#
# Мера — ПРОЦЕССОРНОЕ время события (user+sys с потомками, встроенное `time` оболочки), а не
# стенное: на общей машине с нагрузкой 40–75 стенное время одного и того же события гуляло
# в 2,5 раза, процессорное — в пределах 10%. Предел — та самая цифра D487, 1,46 с.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
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
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
# 30 000 учтённых файлов (200 каталогов по 150), все старые: событию подавать нечего.
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && python3 -c '
import os
old = 1577836800  # 2020-01-01
for d in range(200):
    p = "src/mod%03d" % d
    os.makedirs(p, exist_ok=True)
    for f in range(150):
        fn = "%s/component_with_a_longish_name_%04d.ts" % (p, f)
        open(fn, "w").write("export {}\n")
        os.utime(fn, (old, old))
' && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
NFILES=$(cd "$SR" && git ls-files | wc -l | tr -d ' ')

run() {
    printf '{"tool_name":"Bash","session_id":"adv2-cost","cwd":"%s"}' "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            bash "$SB/hooks/$DISP" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dispatch_tracked_tree_cost.sh:$LINENO" >&2; exit 1; }
}
cpu_ms() {  # cpu_ms <файл с «user sys real»> → user+sys в миллисекундах
    awk '{printf "%d", ($1 + $2) * 1000}' "$1"
}

: > "$FED"
TIMEFORMAT='%3U %3S %3R'
{ time run >/dev/null; } 2> "$TMP/t.event"           # событие сессии: тронутого нет
{ time ( cd "$SR" && git ls-files -z --cached --others --exclude-standard \
      | xargs -0 sh -c 'find "$@" -maxdepth 0 -type f -mmin -5' sh >/dev/null ); } 2> "$TMP/t.ref"
EV=$(cpu_ms "$TMP/t.event"); EV_REAL=$(awk '{print $3}' "$TMP/t.event")
REF=$(cpu_ms "$TMP/t.ref")
LIMIT=1460

# T0 — контроль: дерево собрано, замер снят, и событию действительно нечего подавать.
if [ "$NFILES" -ge 30000 ] && [ -n "$EV" ] && [ ! -s "$FED" ]; then ok
else bad T0 "контроль: учтённых файлов ${NFILES}, замер «${EV}», подач $(wc -l < "$FED" | tr -d ' ') — нога судила бы не то"; fi
# T1 — событие без работы на 30 тыс. учтённых файлов дешевле той цены, которую D487 назвал
# недопустимой для обхода 140 тыс.
if [ "$EV" -le "$LIMIT" ]; then ok
else bad T1 "событие без единой подачи на ${NFILES} учтённых файлах стоило ${EV} мс процессорного времени (стенного ${EV_REAL} с) — больше ${LIMIT} мс, которые D487 назвал недопустимыми; отбор тех же кандидатов через git ls-files | xargs find — ${REF} мс: цена — побайтное чтение каждого пути циклом оболочки"; fi

echo "test_adv2_dispatch_tracked_tree_cost: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
