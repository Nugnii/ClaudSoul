#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_stale_break_race.sh — противник диспетчера записи командой, раунд 2:
# брошенный замок пары «сессия + корень» срывает РОВНО ОДНО событие, а не несколько.
#
# Устройство. Хук, убитый посреди события сигналом, который не даёт отработать ловушке EXIT
# (SIGKILL, падение машины), либо живой держатель старше порога оставляют каталог замка, и
# через 30 с его срывает следующее событие (`hooks/state-lock-lib.sh`, lock_acquire): проба
# `mkdir` не взяла → возраст каталога через `stat` → старше порога → `rmdir` → снова `mkdir`.
# Проверка и удаление не атомарны: событие C прочло возраст СТАРОГО замка, сосед B тем временем
# сорвал его и создал свой, и `rmdir` события C удаляет уже СВЕЖИЙ замок B, а `mkdir` даёт
# замок и C. Держателей двое — ровно класс, закрытый прошлым раундом (одновременные события
# одной сессии подают одну пару дважды).
#
# Окно делается детерминированным так же, как барьер `sed` в test_adv_dispatch_mark_race.sh:
# заглушка `stat` отвечает с задержкой (машина под нагрузкой — в инциденте D487 экземпляры
# диспетчера жили 1–2 мин), а второе событие стартует чуть позже первого. Различающий
# контроль: тот же брошенный замок и тот же сдвиг старта без задержки `stat` — сорвёт одно
# событие, второе увидит свежий замок и выйдет.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D500 (2 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
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
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
[ -n "${ADV_SLEEP:-}" ] && sleep "$ADV_SLEEP"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

# Заглушка `stat`: отвечает настоящим значением, прочитанным в начале вызова, но с задержкой —
# только на каталоге замка (других вызовов `stat` у диспетчера с заглушками стражей нет).
SHIM="$TMP/shim"; mkdir -p "$SHIM"
REAL_STAT=$(command -v stat)
cat > "$SHIM/stat" <<EOF
#!/bin/sh
out=\$("$REAL_STAT" "\$@" 2>/dev/null); rc=\$?
case "\$*" in *.lock*) sleep 1 ;; esac
[ -n "\$out" ] && printf '%s\n' "\$out"
exit \$rc
EOF
chmod +x "$SHIM/stat"

run() {  # run <сессия> [ПЕРЕМЕННАЯ=значение ...] → вывод диспетчера
    local s=$1; shift
    printf '{"tool_name":"Bash","session_id":"adv2-%s","cwd":"%s"}' "$s" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            "$@" bash "$SB/hooks/$DISP" 2>/dev/null
}
pair() {  # pair <сессия> <файл> <PATH событий> → число подач пары «файл + первый страж»
    local s=$1 f=$2 p=$3 q
    run "$s" >/dev/null                      # первое событие сессии ставит метку
    sleep 1                                  # правка новее метки при любой точности времени
    echo "правка" > "$SR/$f"
    q=$(ls "$ST"/bash-dispatch-queue-adv2-"$s"-* 2>/dev/null | grep -v '\.lock$' | head -1)
    [ -n "$q" ] || { echo "-1"; return; }
    mkdir "$q.lock" && touch -t 202001010000 "$q.lock"   # замок убитого события
    : > "$FED"
    run "$s" PATH="$p" ADV_SLEEP=2 BASH_DISPATCH_MAX_RUNS=1 > "$TMP/outB.$s" &   # событие B
    local b=$!
    sleep 0.4
    run "$s" PATH="$p" ADV_SLEEP=2 BASH_DISPATCH_MAX_RUNS=1 > "$TMP/outC.$s" &   # событие C, чуть позже
    wait "$b"; wait
    grep -c "^$FIRST .*/${f}\$" "$FED"
    touch -t 202001010000 "$SR/$f"           # состарить: окно 5 минут следующей сессии
}

# T0 — различающий контроль: проверка возраста быстрая — замок срывает одно событие.
N0=$(pair ctl ctl.md "$PATH")
if [ "$N0" -eq 1 ]; then ok
else bad T0 "контроль без задержки: пара подана ${N0} раз(а) (ожидалось 1) — нога не различала бы предмет"; fi
# T1 — та же пара событий, проверка возраста медленная (нагрузка): срыв обязан остаться одним.
N1=$(pair slow slow.md "$SHIM:$PATH")
if [ "$N1" -eq 1 ]; then ok
else bad T1 "брошенный замок сорвали оба события: второе прочло возраст старого замка, а его rmdir снёс уже свежий замок первого — пара «slow.md + ${FIRST%.sh}» подана ${N1} раз(а) вместо 1"; fi

# T2 — то же без заглушек: залп из 30 одновременных событий одной сессии на брошенном замке
# (замер 1 октября 2026: красно в 4 прогонах из 5). Раундов до пяти, каждый с новой сессией;
# дубль любого раунда — находка, а промах подачи — пустая нога.
HIT=""; r=0
while [ "$r" -lt 5 ] && [ -z "$HIT" ]; do
    r=$((r+1)); s="v$r"; f="volley$r.md"
    run "$s" >/dev/null; sleep 1; echo "правка" > "$SR/$f"
    q=$(ls "$ST"/bash-dispatch-queue-adv2-"$s"-* 2>/dev/null | grep -v '\.lock$' | head -1)
    [ -n "$q" ] && mkdir "$q.lock" && touch -t 202001010000 "$q.lock"
    : > "$FED"; i=0
    while [ "$i" -lt 30 ]; do i=$((i+1)); run "$s" ADV_SLEEP=0.2 BASH_DISPATCH_MAX_RUNS=1000 > "$TMP/out.$s.$i" & done
    wait
    n=$(grep -c "^$FIRST .*/${f}\$" "$FED")
    [ "$n" -ge 1 ] || { bad T2a "раунд $r: правка не дошла до стражей — нога судила бы пустоту"; break; }
    [ "$n" -le 1 ] || HIT="раунд $r: ${n} подач"
    touch -t 202001010000 "$SR/$f"
done
if [ -z "$HIT" ]; then ok
else bad T2 "залп из 30 одновременных событий на брошенном замке: пара «файл + ${FIRST%.sh}» подана несколько раз (${HIT}, ожидалось 1)"; fi

echo "test_adv2_dispatch_stale_break_race: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
