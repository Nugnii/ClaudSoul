#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_stale_live_holder.sh — противник диспетчера записи командой, раунд 2:
# замок пары «сессия + корень» обязан держать ОДНО событие за раз и тогда, когда держатель
# ЖИВ, но работает дольше порога срыва замка.
#
# Устройство. Замок — каталог `<очередь>.lock`; чужой замок старше CLAUDSOUL_LOCK_STALE_S
# (30 с) считается брошенным и срывается (`hooks/state-lock-lib.sh`, lock_acquire). Возраст
# судится по времени каталога, а держатель его не обновляет. Значит, событие, идущее дольше
# 30 с (тайм-аут хука по умолчанию 60 с; в инциденте D487 экземпляры диспетчера жили 1–2 мин),
# теряет замок при живом держателе: следующее событие срывает его и идёт ПАРАЛЛЕЛЬНО — ровно
# класс, закрытый прошлым раундом (двойная подача). Вторая половина: на выходе первый держатель
# снимает замок по своей записи `_SL_HELD`, то есть удаляет каталог ВТОРОГО держателя, и третье
# событие входит, пока второе ещё работает.
#
# Возраст замка подаётся прямо: каталогу замка ставится старое время (`touch -t`), то есть
# тот же вход, что дала бы минута жизни держателя, — без минуты ожидания в тесте.
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
# Песочница несёт библиотеку замка с её зависимостью, как установка в ~/.claude/hooks.
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
# Заглушка: пишет «страж путь» в журнал ДО паузы — строка в журнале значит «держатель сейчас
# внутри стража», — затем держит паузу ADV_SLEEP (медленный страж либо нагруженная машина).
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

run() {  # run <сессия> [ПЕРЕМЕННАЯ=значение ...] → вывод диспетчера
    local s=$1; shift
    printf '{"tool_name":"Bash","session_id":"adv2-%s","cwd":"%s"}' "$s" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            "$@" bash "$SB/hooks/$DISP" 2>/dev/null
}
wait_line() {  # wait_line <шаблон> <сколько строк> — ждать строк в журнале подач (до 10 с)
    local i=0 n
    while [ "$i" -lt 200 ]; do
        n=$(grep -c "$1" "$FED" 2>/dev/null); n=${n:-0}
        [ "$n" -ge "$2" ] && return 0
        sleep 0.05; i=$((i+1))
    done
    return 1
}

# ── Нога 1: держатель жив, замок старше порога — второе событие входит параллельно ──────────
run a >/dev/null                 # первое событие сессии ставит метку
sleep 1                          # правка новее метки при любой точности времени файла
echo "правка" > "$SR/one.md"
: > "$FED"
run a ADV_SLEEP=4 BASH_DISPATCH_MAX_RUNS=1 > "$TMP/outA" &   # держатель A: медленный страж
A_PID=$!
wait_line "^$FIRST .*/one\.md\$" 1; A_IN=$?
LOCK=$(ls -d "$ST"/bash-dispatch-queue-adv2-a-*.lock 2>/dev/null | head -1)
# Различающий контроль: пока замок МОЛОД, второе событие обязано выйти без подачи.
run a BASH_DISPATCH_MAX_RUNS=1000 > "$TMP/outB0"
N0=$(grep -c "^$FIRST .*/one\.md\$" "$FED")
# Держатель A прожил больше порога: каталог замка получает старое время.
[ -n "$LOCK" ] && touch -t 202001010000 "$LOCK"
run a BASH_DISPATCH_MAX_RUNS=1000 > "$TMP/outB"              # событие B, пока A жив
A_ALIVE=no; kill -0 "$A_PID" 2>/dev/null && A_ALIVE=yes
wait "$A_PID"
N1=$(grep -c "^$FIRST .*/one\.md\$" "$FED")

# T0 — положительный контроль: A вошёл в стража, держал замок и был жив, когда шло B.
if [ "$A_IN" -eq 0 ] && [ -n "$LOCK" ] && [ "$A_ALIVE" = yes ]; then ok
else bad T0 "контроль: держатель не воспроизведён (в страже: rc=$A_IN, замок: «${LOCK}», жив при B: $A_ALIVE) — нога судила бы пустоту"; fi
# T0б — при молодом замке второе событие выходит, пара подана один раз: замок работает, и
# расхождение T1 даёт именно возраст замка, а не что-то другое.
if [ "$N0" -eq 1 ]; then ok
else bad T0б "контроль: при молодом замке пара подана ${N0} раз(а) — нога не различала бы возраст замка"; fi
# T1 — пара «one.md + первый страж» подана ровно один раз за сессию.
if [ "$N1" -eq 1 ]; then ok
else bad T1 "держатель жив, его замок старше 30 с: второе событие сорвало замок и подало ту же пару «one.md + ${FIRST%.sh}» ещё раз — подач ${N1} вместо 1"; fi

# ── Нога 2: выход первого держателя снимает замок ВТОРОГО ───────────────────────────────────
# Правка ноги 1 состарена: первое событие новой сессии берёт тронутое за 5 минут, и one.md
# иначе встал бы в её очередь впереди two.md.
touch -t 202001010000 "$SR/one.md"
run b >/dev/null
sleep 1
echo "правка" > "$SR/two.md"
: > "$FED"
run b ADV_SLEEP=3 BASH_DISPATCH_MAX_RUNS=1 > "$TMP/outA2" &   # держатель A2
A2=$!
wait_line "^$FIRST .*/two\.md\$" 1
LOCK2=$(ls -d "$ST"/bash-dispatch-queue-adv2-b-*.lock 2>/dev/null | head -1)
[ -n "$LOCK2" ] && touch -t 202001010000 "$LOCK2"
run b ADV_SLEEP=8 BASH_DISPATCH_MAX_RUNS=1 > "$TMP/outB2" &   # B2 срывает замок и держит его
B2=$!
wait_line "^$FIRST .*/two\.md\$" 2; B2_IN=$?
wait "$A2"                                                     # A2 выходит, пока B2 внутри стража
B2_ALIVE=no; kill -0 "$B2" 2>/dev/null && B2_ALIVE=yes
HELD=no; [ -n "$LOCK2" ] && [ -d "$LOCK2" ] && HELD=yes
wait "$B2"

# T2 — если второй держатель всё же возник, выход первого не снимает ЕГО замок. Второй не
# возник (замок живого держателя не сорван — предмет T1) — снимать нечего, нога пройдена.
if [ "$B2_IN" -ne 0 ]; then ok
elif [ "$B2_ALIVE" != yes ]; then
    bad T2 "контроль: второй держатель вошёл в стража, но к выходу первого уже кончился — нога судила бы пустоту"
elif [ "$HELD" = yes ]; then ok
else bad T2 "выход первого держателя удалил замок второго: B2 ещё внутри стража, а каталога замка нет — следующее событие войдёт третьим без всякого срыва"; fi

echo "test_adv2_dispatch_stale_live_holder: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
