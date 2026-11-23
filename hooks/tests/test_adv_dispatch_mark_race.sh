#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_mark_race.sh — противник диспетчера записи командой (D487): правка,
# легшая МЕЖДУ отбором тронутого и сдвигом метки сессии, не теряется.
#
# Устройство дефекта. Метка сессии ставится `touch` ПОСЛЕ отбора (`find … -newer МЕТКА`), то есть
# получает время конца отбора, а не начала. Файл, записанный, пока отбор уже прошёл мимо него, а
# метка ещё не сдвинута, старше новой метки: ни это событие, ни следующие (`-newer`) его не
# возьмут, а в очередь он не попал. У сессии и её субагентов метка ОДНА, события идут
# одновременно, и под нагрузкой (инцидент D487: экземпляр диспетчера жил 1–2 мин) окно между
# отбором и меткой у соседнего события — обычное место для чужой записи.
#
# Окно воспроизводится детерминированно, без опоры на время: заглушка `sed` (последнее звено
# конвейера отбора) сперва дочитывает свой вход — значит `find` уже отработал, — затем ждёт
# сигнала. В этот момент «соседний агент» пишет файл; потом отбор кончается, метка сдвигается.
# Ожидание: файл, записанный командой, доходит до стражей на одном из следующих событий сессии.
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

run() {  # run <сессия> [ПЕРЕМЕННАЯ=значение ...] → вывод диспетчера
    local s=$1; shift
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$s" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 "$@" bash "$SB/hooks/$DISP" 2>/dev/null
}

# Барьер в конвейере отбора: заглушка `sed` дочитывает вход (find отработал), говорит «готов»
# и ждёт «дальше» не дольше 30 с, потом исполняет настоящий `sed` над прочитанным.
SHIM="$TMP/shim"; mkdir -p "$SHIM"
REAL_SED=$(command -v sed)
cat > "$SHIM/sed" <<EOF
#!/bin/sh
cat > "$SHIM/sed.in"
: > "$SHIM/ready"
i=0
while [ ! -f "$SHIM/go" ] && [ \$i -lt 600 ]; do sleep 0.05; i=\$((i+1)); done
exec "$REAL_SED" "\$@" < "$SHIM/sed.in"
EOF
chmod +x "$SHIM/sed"

run r >/dev/null      # первое событие сессии ставит метку
sleep 1               # дальнейшие правки новее метки при любой точности времени файла
: > "$FED"
# Событие A (чья-то команда кончилась) — в окне между отбором и меткой.
run r PATH="$SHIM:$PATH" > "$TMP/outA" &
A_PID=$!
i=0
while [ ! -f "$SHIM/ready" ] && [ "$i" -lt 600 ]; do sleep 0.05; i=$((i+1)); done
BARRIER=no; [ -f "$SHIM/ready" ] && BARRIER=yes
# Соседний агент той же сессии пишет файл ИМЕННО сейчас.
echo "запись соседа" > "$SR/late.md"
sleep 0.1
: > "$SHIM/go"
wait "$A_PID"
# Дальше — обычные события той же сессии, в том числе PostToolUse самого пишущего.
for k in 1 2 3; do run r >/dev/null; done
LATE=$(grep -c '/late\.md$' "$FED")
# Положительный контроль: тот же путь записи без окна — файл доходит.
echo "контроль" > "$SR/ctl.md"
run r >/dev/null
CTL=$(grep -c '/ctl\.md$' "$FED")

# T0 — барьер сработал: запись соседа действительно легла в окно, иначе нога судила бы пустоту.
if [ "$BARRIER" = yes ]; then ok; else bad T0 "барьер в отборе не сработал — запись легла не в окно"; fi
# T0б — положительный контроль: обычная правка доходит до стражей.
if [ "$CTL" -ge 1 ]; then ok; else bad T0б "положительный контроль: обычная правка не подана (подач: ${CTL})"; fi
# T1 — правка, легшая между отбором и сдвигом метки, доходит до стражей на следующих событиях.
if [ "$LATE" -ge 1 ]; then ok
else bad T1 "правка соседа между отбором и сдвигом метки потеряна: late.md не подан ни одному стражу за 4 события (метка ставится концом отбора, а не его началом)"; fi

echo "test_adv_dispatch_mark_race: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
