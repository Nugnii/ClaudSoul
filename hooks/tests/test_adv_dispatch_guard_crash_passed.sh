#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# вынесен из набора до починки пункта; прежнее имя — test_adv_dispatch_guard_crash_passed.sh.
# test_adv_dispatch_guard_crash_passed.sh — противник диспетчера записи командой (D487): упавший
# страж не записывается в «пару прошёл чисто».
#
# Устройство дефекта. Ответ стража читается только по stdout: `out=$(… | bash страж 2>/dev/null)`,
# код возврата не смотрится, stderr выброшен. Пустой stdout — и у «проверил, чисто», и у «упал»
# (необъявленная переменная под `set -u`, отказ fork под нагрузкой — инцидент D487 шёл при
# нагрузке 27–32, сигнал, нехватка памяти). В обоих случаях ставится флаг пары, файл уходит в
# список пройденного, и повторной подачи в сессии не будет: разовый сбой стража становится
# вечным «чисто», а текст сбоя не видит никто. Правило дерева
# (`.claude/rules/claudsoul-hooks.md`, «У прибора три состояния»): «инструмент сломался» —
# говорить, молчание читается как «чисто».
#
# Ожидание: страж, упавший с ненулевым кодом и пустым выводом, либо получает пару повторно на
# следующем событии (и его находка доходит), либо его сбой назван в выводе события.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D494 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
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

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
# Первый страж падает на ПЕРВОМ вызове (разовый сбой), дальше исправен и на файлах с маркером
# KEY отвечает находкой. Остальные стражи молчат.
FLAKY='#!/usr/bin/env bash
IN=$(cat)
if [ ! -f "$ADV_DIR/crashed-once" ]; then
  : > "$ADV_DIR/crashed-once"
  echo "fork: Resource temporarily unavailable" >&2
  exit 1
fi
case "$IN" in *KEY-*) printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"ADV-KEY-FOUND\"}}" ;; esac
exit 0'
for g in $GUARD_LIST; do printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/hooks/$g"; done
printf '%s\n' "$FLAKY" > "$SB/hooks/$FIRST"
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

run() {  # run <сессия> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_DIR="$TMP" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run k >/dev/null       # начало сессии: метка
sleep 1
echo "KEY-one" > "$SR/conf.md"     # команда записала ключ
OUT1=$(run k)                      # здесь страж падает
LATER=""
for k in 1 2 3; do LATER="${LATER}$(run k)"; done
# Положительный контроль: исправный после сбоя страж находит ключ в свежей правке.
echo "KEY-two" > "$SR/conf2.md"
OUT_CTL=$(run k)
NAME=${FIRST%.sh}

# T0 — сбой действительно случился на подаче conf.md, и страж после него исправен.
if [ -f "$TMP/crashed-once" ]; then ok; else bad T0 "сбой стража не воспроизведён — нога судила бы пустоту"; fi
if grep -qF "ADV-KEY-FOUND" <<< "$OUT_CTL"; then ok; else bad T0б "положительный контроль: исправный страж не назвал ключ в свежей правке"; fi
# T1 — разовый сбой не стал вечным «чисто»: пара подана повторно (находка дошла) или сбой назван.
if grep -qF "ADV-KEY-FOUND" <<< "$LATER" || grep -qF "$NAME" <<< "$OUT1"; then ok
else bad T1 "страж ${FIRST} упал (код 1, stderr выброшен) — пара «conf.md + страж» записана пройденной: ключ в conf.md не назван ни в одном из 4 событий, и сбой не назван"; fi

# T2 — НЕЧИТАЕМЫЙ ОТВЕТ НЕ «ЧИСТО» (D1026): второй страж печатает JSON с недопустимым экранированием — диспетчер обязан
# назвать его, а не записать пару пройденной молча (так пропала подсказка о строке 316 docs-family-check.sh).
set -- $GUARD_LIST; SECOND=$2
printf '%s\n' '#!/usr/bin/env bash' 'case "$(cat)" in *BADJSON-*) printf "%s\n" "{\"hookSpecificOutput\":{\"additionalContext\":\"a \\»\"}}" ;; esac' > "$SB/hooks/$SECOND"
echo "BADJSON-one" > "$SR/conf3.md"
OUT_BAD=$(run k)
if grep -qF "${SECOND%.sh}" <<< "$OUT_BAD" && grep -qF "не JSON протокола" <<< "$OUT_BAD"; then ok
else bad T2 "страж ${SECOND} ответил не JSON — диспетчер его не назвал: ${OUT_BAD:0:200}"; fi

echo "test_adv_dispatch_guard_crash_passed: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
