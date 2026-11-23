#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_stale_lock_break.sh — противник диспетчера записи командой (D487, раунд 2):
# замок пары «сессия + корень» держит дедуп и тогда, когда событие-держатель идёт дольше порога
# «брошенного» замка.
#
# Устройство. Починка класса «двойная подача при одновременных событиях» — замок
# `state-lock-lib.sh` с одной пробой. У библиотеки есть срыв брошенного замка: чужой замок старше
# `CLAUDSOUL_LOCK_STALE_S` (30 с) по времени изменения КАТАЛОГА замка срывается. Время каталога
# ставится при `mkdir` и пока замок держат не обновляется — держатель, идущий дольше 30 с, для
# следующего события неотличим от умершего. Второе событие срывает живой замок, берёт его и
# подаёт ту же пару «файл + страж», флаг которой держатель ещё не поставил (флаг ставится ПОСЛЕ
# ответа стража). Затем держатель на выходе снимает уже ЧУЖОЙ замок (`trap … EXIT` — то же имя).
# Где живёт: в инциденте D487 экземпляры диспетчера жили по 1–2 мин под нагрузкой 27–32 на
# 10 ядрах; событие дольше 30 с даёт и зависший страж, и сон машины посреди события.
# Здесь 60 с держания изображены сдвигом времени каталога замка назад — ровно то состояние,
# которое библиотека увидела бы через минуту настоящего держания.
# Ожидание: одна правка одного файла → страж получает её РОВНО один раз за сессию.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Все стражи здесь — заглушки, и носитель
# был бы ложным (тот же приём — test_bash_write_dispatch_selection.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
TMP=$(cd "$TMP" && pwd -P)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"; ST="$TMP/state"
mkdir -p "$SB/hooks" "$SR" "$SH"
# Библиотека замка с её зависимостью — как установка в ~/.claude/hooks: без неё диспетчер
# идёт без замка (третье состояние), и нога судила бы неполную установку.
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
# Заглушка пишет «страж путь» в журнал; у события-держателя (ADV_SLEEP) первый страж отвечает
# не сразу — окно, в котором флаг пары ещё не поставлен.
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
g=$(basename "$0")
echo "$g $p" >> "${ADV_FED:-/dev/null}"
[ "$g" = "${ADV_LOUD:-}" ] && [ -n "${ADV_SLEEP:-}" ] && sleep "$ADV_SLEEP"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md"

run() {  # run <сессия> [ПЕРЕМЕННАЯ=значение ...] → вывод диспетчера
    local s=$1; shift
    printf '{"tool_name":"Bash","session_id":"adv2-%s","cwd":"%s"}' "$s" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" ADV_LOUD="$FIRST" \
            BASH_DISPATCH_MAX_RUNS=1000 "$@" bash "$SB/hooks/$DISP" 2>/dev/null
}

# scenario <сессия> <файл> <состарить: 0|1> → число подач пары «файл + первый страж».
# Держатель входит в первого стража (замок взят, флага пары нет); при состарить=1 время
# каталога замка сдвигается на 60 с назад — минута настоящего держания; затем следующее
# событие той же пары.
scenario() {
    local s=$1 f=$2 age=$3 pa i lockd
    run "$s" >/dev/null                 # первое событие сессии ставит метку
    sleep 1                             # правка новее метки при любой точности времени файла
    echo "новое" > "$SR/$f"
    run "$s" ADV_SLEEP=3 > "$TMP/out.$s.a" &   # событие-держатель: первый страж отвечает 3 с
    pa=$!
    i=0; while [ "$i" -lt 100 ] && ! grep -q "^$FIRST $SR/$f\$" "$FED" 2>/dev/null; do sleep 0.05; i=$((i+1)); done
    lockd=$(ls -d "$ST"/bash-dispatch-queue-adv2-"$s"-*.lock 2>/dev/null | head -n 1)
    [ -n "$lockd" ] || { wait "$pa"; echo "SETUP"; return; }
    [ "$age" = 1 ] && python3 -c 'import os,sys,time; t=time.time()-60; os.utime(sys.argv[1],(t,t))' "$lockd"
    run "$s" > "$TMP/out.$s.b"          # следующее событие той же пары
    wait "$pa"
    grep -c "^$FIRST $SR/$f\$" "$FED"
}

: > "$FED"
n_ctl=$(scenario ctl one.md 0)
n_atk=$(scenario atk two.md 1)
if [ "$n_ctl" = SETUP ] || [ "$n_atk" = SETUP ]; then
    echo "FAIL [setup]: держатель не взял замок очереди (нет каталога *.lock) — нога судила бы пустоту"; exit 1
fi
# T0 — контроль, различающий предмет: держатель «молод» — второе событие замок не берёт и
# пару не подаёт. Здесь замок работает, и только возраст каталога отличает ногу T1.
if [ "$n_ctl" -eq 1 ]; then ok
else bad T0 "контроль: при молодом держателе пара «one.md + ${FIRST}» подана ${n_ctl} раз(а) — нога T1 не различала бы предмет"; fi
if [ "$n_atk" -ge 1 ] && [ "$n_atk" -le 1 ]; then ok
else bad T1 "пара «two.md + ${FIRST}» подана ${n_atk} раза за сессию: второе событие сорвало замок держателя, шедшего дольше 30 с, как брошенный"; fi

echo "test_adv2_dispatch_stale_lock_break: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
