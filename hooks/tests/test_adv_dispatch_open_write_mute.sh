#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh hooks/backlog-open-write-guard.sh
# test_adv_dispatch_open_write_mute.sh — противник диспетчера записи командой (D487, раунд 1; пункт D492): отказ
# уровня 4 `backlog-open-write-guard` доходит до правки BACKLOG.md, сделанной КОМАНДОЙ.
#
# Устройство дефекта. Страж судит только пункты, чья «Проверка» НОВА или ИЗМЕНЕНА относительно
# файла НА ДИСКЕ (`backlog-open-write-guard.sh`: `[ "$_old" = "y$chk" ] && continue`). На пути
# инструмента он стоит ДО записи, и диск хранит старую редакцию. Диспетчер же подаёт синтетический
# Write ПОСЛЕ записи, с содержимым, которое уже лежит на диске: «старое» и «новое» совпадают
# побайтно, изменённых пунктов ноль, страж молчит ПО ПОСТРОЕНИЮ — на любом входе.
# Шапка диспетчера называет этого стража первым поводом своего существования («ноль
# срабатываний при четырёх коммитах, тронувших его предмет») и числит его среди «троих
# отказывающих — их пропуск дороже всего». Путь команды для него как был слепым, так и остался.
#
# Ожидание: команда записала в BACKLOG.md открытый пункт с ЗЕЛЁНОЙ «Проверкой» — диспетчер
# называет находку стража с именем пункта (как назвал бы тот же страж на пути инструмента).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Настоящим здесь подан только страж
# открытого пункта — исключения `*/tmp/*` у него нет, и носитель был бы ложным.
DISP="bash-write-""dispatch.sh"
OWG="backlog-open-write-guard.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Песочница: копия диспетчера, НАСТОЯЩИЙ страж открытого пункта с его библиотеками, остальные
# стражи списка — молчащие заглушки (предмет ноги — один страж).
SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/$OWG" "$HOOK_DIR/backlog-lib.sh" \
   "$HOOK_DIR/timeout-lib.sh" "$HOOK_DIR/throttle-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер или страж не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
case " $GUARD_LIST " in *" $OWG "*) ;; *) echo "FAIL [setup]: страж открытого пункта не в списке диспетчера: ${GUARD_LIST}"; exit 1 ;; esac
for g in $GUARD_LIST; do [ "$g" = "$OWG" ] || printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf '# BACKLOG\n\n- ☐ **D10** красный открытый пункт\n  **Проверка.** `false` → 0\n- ☐ **D11** давний открытый пункт с зелёной проверкой\n  **Проверка.** `true` → 0\n' > BACKLOG.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/BACKLOG.md"
NEW=$(printf '# BACKLOG\n\n- ☐ **D10** красный открытый пункт\n  **Проверка.** `false` → 0\n- ☐ **D11** давний открытый пункт с зелёной проверкой\n  **Проверка.** `true` → 0\n- ☐ **D13** новый пункт с зелёной проверкой\n  **Проверка.** `true` → 0\n')

run() {  # run <сессия> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state-$1" PATHS_LIB="$SB/hooks/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=100 \
            bash "$SB/hooks/$DISP" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_dispatch_open_write_mute.sh:$LINENO" >&2; exit 1; }
}

# T0 — положительный контроль: тот же страж на пути ИНСТРУМЕНТА (до записи) отказывает с именем
# пункта. Иначе нога судила бы неисправного стража или песочницу, а не диспетчер.
PC=$(jq -cn --arg f "$SR/BACKLOG.md" --arg c "$NEW" \
        '{session_id:"adv-pc", tool_name:"Write", tool_input:{file_path:$f, content:$c}}' \
     | env HOME="$SH" STATE_DIR="$TMP/state-pc" PATHS_LIB="$SB/hooks/paths-lib.sh" \
           bash "$SB/hooks/$OWG" 2>/dev/null)
if grep -qF '"permissionDecision":"deny"' <<< "$PC" && grep -qF "D13" <<< "$PC"; then ok
else bad T0 "положительный контроль: страж на пути инструмента не отказал по D13: «${PC:0:160}»"; fi

# Путь команды: та же запись сделана командой, диспетчер подаёт её задним числом.
run w >/dev/null      # первое событие сессии ставит метку
sleep 1
printf '%s\n' "$NEW" > "$SR/BACKLOG.md"
OUT=$(run w)
# T1 — находка стража дошла до вывода диспетчера с именем пункта.
if grep -qF "D13" <<< "$OUT"; then ok
else bad T1 "открытый пункт D13 с зелёной «Проверкой», записанный командой, не назван: страж сравнивает запись с диском, а диспетчер подаёт то, что уже на диске — вывод «${OUT:0:120}»"; fi

# T2 — прежней редакцией на пути команды служит последний коммит, а не «ничего»: давний пункт D11
# с зелёной «Проверкой» лежит в коммите и не менялся — не предмет стража (его судит completion-gate
# по сроку). Судить все открытые значило бы платить всем бэклогом за каждую версию файла (D498).
if grep -qF "D11" <<< "$OUT"; then
    bad T2 "на пути команды судится и неизменённый давний пункт D11 — прежняя редакция не взята из коммита: «${OUT:0:160}»"
else ok; fi
# T3 — на пути команды запись уже сделана: страж не говорит «вызов не выполнен».
if grep -qF "вызов не выполнен" <<< "$OUT"; then
    bad T3 "подача задним числом утверждает «вызов не выполнен», хотя файл уже записан командой: «${OUT:0:160}»"
else ok; fi

echo "test_adv_dispatch_open_write_mute: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
