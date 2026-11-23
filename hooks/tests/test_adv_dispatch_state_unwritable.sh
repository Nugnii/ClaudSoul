#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# вынесен из набора до починки пункта; прежнее имя — test_adv_dispatch_state_unwritable.sh.
# test_adv_dispatch_state_unwritable.sh — противник диспетчера записи командой (D487): каталог
# состояния, в который нельзя писать, не делает диспетчер молча слепым.
#
# Устройство дефекта. Отбор нового события попадает к стражам ТОЛЬКО через файл очереди:
# `printf … >> ОЧЕРЕДЬ 2>/dev/null`, затем `CHANGED` читается из очереди. Если очередь создать
# нельзя (каталог состояния без прав записи: создан под sudo, смонтирован только для чтения,
# диск полон), дописывание глохнет в /dev/null, `CHANGED` пуст, и событие выходит кодом 0 без
# единого слова — правка команды не доходит ни до одного стража, и ничто об этом не говорит.
# Правило дерева (`.claude/rules/claudsoul-hooks.md`, «У прибора три состояния»): «инструмент
# сломался» обязан говорить — молчание здесь читается как «чисто».
#
# Ожидание: при неписаемом состоянии событие либо подаёт свежую правку стражам (находка
# видна), либо называет свою слепоту. Пустой вывод — дефект.
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
TMP=$(mktemp -d)   # временное уберёт система (D360); права каталога возвращаются в конце
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; ST="$TMP/state"
mkdir -p "$SB/hooks" "$SR" "$SH" "$ST"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
# Каждая заглушка на файле secret.md отвечает находкой — как `secret-guard` на ключе.
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
case "$p" in */secret.md) printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"ADV-SECRET-FOUND\"}}" ;; esac
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

run() {  # run <сессия> <каталог состояния> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$2" PATHS_LIB="$SB/hooks/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=100 \
            bash "$SB/hooks/$DISP" 2>/dev/null; return $?  # код предмета — вызывающему: T1 судит его (скептик D1194, H1)
}

echo "AKIA-ключ" > "$SR/secret.md"     # команда записала файл
# T0 — положительный контроль: при писаемом состоянии та же правка доходит и называется.
OK_OUT=$(run ctl "$TMP/state-ok")
if grep -qF "ADV-SECRET-FOUND" <<< "$OK_OUT"; then ok
else bad T0 "положительный контроль: при писаемом состоянии находка не названа: «${OK_OUT:0:120}»"; fi

chmod 555 "$ST"
if ( : > "$ST/probe" ) 2>/dev/null; then
    chmod 755 "$ST"
    echo "SKIP: каталог состояния остался писаемым (запуск от root) — предмет недостижим"
    echo "test_adv_dispatch_state_unwritable: прошло $PASS, упало $FAIL"
    exit $(( FAIL != 0 ))
fi
OUT=$(run ro "$ST")
RC=$?
chmod 755 "$ST"

# T1 — неписаемое состояние: правка либо подана стражам, либо названа слепота; молчание — дефект.
if [ -n "$OUT" ]; then ok
else bad T1 "каталог состояния без прав записи: событие вышло кодом ${RC} с ПУСТЫМ выводом — ключ в secret.md не увиден ни одним стражем, и слепота не названа"; fi

echo "test_adv_dispatch_state_unwritable: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
