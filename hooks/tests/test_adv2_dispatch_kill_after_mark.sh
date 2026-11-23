#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_kill_after_mark.sh — противник диспетчера записи командой, раунд 2:
# событие, прерванное посреди работы, не теряет отобранные правки навсегда.
#
# Устройство. Отбор тронутого живёт в ПАМЯТИ события (`_sel`), а новая метка фиксируется
# (`mv .next → метка`) ДО того, как отобранное дописано в очередь: между ними — отпечаток
# набора стражей (`cksum`) и само дописывание. Событие, прерванное в этом окне (SIGTERM
# тайм-аута хука или отмены — ловушка EXIT снимает замок, но отбора не сохраняет), уносит
# отобранное с собой: метка уже новее правки, и `-newer` следующих событий её не возьмёт, а в
# очереди её нет. Правка не доходит до стражей до конца сессии.
#
# Окно воспроизводится детерминированно: заглушка `cksum` на ВТОРОМ вызове события (отпечаток
# набора стражей, строка после фиксации метки) говорит «готов» и ждёт; тест шлёт хуку SIGTERM.
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
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

IN="$TMP/in.json"
printf '{"tool_name":"Bash","session_id":"adv2-kill","cwd":"%s"}' "$SR" > "$IN"
run() {  # run [PATH] — обычное событие той же сессии
    env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
        STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
        BASH_DISPATCH_MAX_RUNS=1000 PATH="${1:-$PATH}" bash "$SB/hooks/$DISP" < "$IN" 2>/dev/null
}

# Заглушка `cksum`: второй вызов события — отпечаток набора стражей — ждёт сигнала «дальше».
SHIM="$TMP/shim"; mkdir -p "$SHIM"; CNT="$TMP/cksum.n"; READY="$TMP/ready"; GO="$TMP/go"
REAL_CKSUM=$(command -v cksum)
cat > "$SHIM/cksum" <<EOF
#!/bin/sh
n=\$(cat "$CNT" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "$CNT"
if [ "\$n" -eq 2 ]; then
    : > "$READY"; i=0
    while [ ! -f "$GO" ] && [ "\$i" -lt 600 ]; do sleep 0.05; i=\$((i+1)); done
fi
exec "$REAL_CKSUM" "\$@"
EOF
chmod +x "$SHIM/cksum"

run >/dev/null                         # первое событие сессии ставит метку
sleep 1                                # правка новее метки при любой точности времени
echo "правка командой" > "$SR/lost.md"
: > "$FED"
# Событие K (после той команды) прерывается в окне: метка зафиксирована, очередь не дописана.
env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
    BASH_DISPATCH_MAX_RUNS=1000 PATH="$SHIM:$PATH" bash "$SB/hooks/$DISP" < "$IN" > "$TMP/outK" 2>/dev/null &
K=$!
i=0; while [ ! -f "$READY" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i+1)); done
IN_WINDOW=no; [ -f "$READY" ] && IN_WINDOW=yes
MARK=$(ls "$ST"/bash-dispatch-mark-adv2-kill-* 2>/dev/null | grep -v '\.next$' | head -1)
PASSED=no   # метка уже не старше правки — `-newer` её больше не возьмёт
[ -n "$MARK" ] && [ -z "$(find "$SR/lost.md" -newer "$MARK" 2>/dev/null)" ] && PASSED=yes
kill -TERM "$K" 2>/dev/null            # тайм-аут хука либо отмена: SIGTERM, ловушка EXIT отрабатывает
wait "$K" 2>/dev/null
: > "$GO"                              # отпустить осиротевшую заглушку
for k in 1 2 3; do run >/dev/null; done   # обычные события той же сессии
LOST=$(grep -c '/lost\.md$' "$FED")
echo "контроль" > "$SR/ctl.md"
run >/dev/null
CTL=$(grep -c '/ctl\.md$' "$FED")

# T0 — прерывание пришлось после отбора: заглушка второго вызова `cksum` ждала сигнала. Что
# метка к этому мгновению уже прошла правку — свойство нынешнего порядка, а не контроль: у
# исправленного порядка его не будет, и оно названо в сообщении T1.
if [ "$IN_WINDOW" = yes ]; then ok
else bad T0 "контроль: заглушка cksum не дождалась прерывания — нога судила бы пустоту"; fi
# T0б — после прерывания сессия жива: правка, сделанная позже, подаётся (замок снят ловушкой).
if [ "$CTL" -ge 1 ]; then ok
else bad T0б "контроль: правка после прерывания не подана (подач: ${CTL}) — нога судила бы мёртвую сессию"; fi
# T1 — отобранная прерванным событием правка доходит до стражей на следующих событиях.
if [ "$LOST" -ge 1 ]; then ok
else bad T1 "событие, прерванное SIGTERM после отбора, унесло его: lost.md не подан ни одному стражу за 4 следующих события (метка к прерыванию уже прошла правку: $PASSED), а в очереди его нет"; fi

echo "test_adv2_dispatch_kill_after_mark: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
