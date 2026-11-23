#!/usr/bin/env bash
# СУДИТ: hooks/running-file-edit-guard.sh
# test_running_file_edit_guard.sh — страж говорит на файле, который ИСПОЛНЯЕТСЯ, и молчит,
# когда файл лишь упомянут в чужой командной строке.
#
# Результат: правка bash-скрипта под живым прогоном не уходит молча.
# Проверка результата: этот тест даёт 0.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/running-file-edit-guard.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
VICTIM="$TMP/victim.sh"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$VICTIM"; chmod +x "$VICTIM"
IDLE="$TMP/idle.sh"
printf '#!/usr/bin/env bash\n:\n' > "$IDLE"

ask() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" | bash "$GUARD" 2>/dev/null; }

# T1. Файл, который никто не исполняет, — молчание.
[ -z "$(ask "$IDLE")" ] && ok T1 || bad T1 "сказал о свободном файле"

# T2. Тот же файл под живым прогоном — страж обязан назвать его.
bash "$VICTIM" & VPID=$!
# ЖДЁМ СОБЫТИЯ, А НЕ СЕКУНДЫ (23 сентября 2026). Под нагрузкой полного набора (восемь
# потоков) процесс не успевал появиться за фиксированную секунду, и прибор ложной зелени
# записал этот тест в «рамка не собралась» — при том что в одиночку он зелен.
_wait=0
while ! ps -p "$VPID" >/dev/null 2>&1 && [ "$_wait" -lt 50 ]; do sleep 0.2; _wait=$((_wait+1)); done
OUT=$(ask "$VICTIM")
if grep -q "исполняется ПРЯМО СЕЙЧАС" <<< "$OUT"; then ok T2
else bad T2 "промолчал на файле, который исполняет живой процесс (pid ${VPID}): «${OUT}»"; fi

# T3. Положительный контроль называет ЧИСЛО процессов, а не просто ругается.
grep -qE '\([0-9]+ процесс' <<< "$OUT" && ok T3 || bad T3 "не назвал число процессов: «${OUT}»"

kill "$VPID" 2>/dev/null; wait "$VPID" 2>/dev/null

# T4. После смерти прогона страж снова молчит — он судит ЖИВОЕ состояние, а не имя файла.
_wait=0
while ps -p "$VPID" >/dev/null 2>&1 && [ "$_wait" -lt 50 ]; do sleep 0.2; _wait=$((_wait+1)); done
[ -z "$(ask "$VICTIM")" ] && ok T4 || bad T4 "сказал о файле, прогон которого завершился"

# T5. Файл лишь УПОМЯНУТ в чужой командной строке (не исполняется) — молчание.
#     Это отрицательный класс признака: правка тут безвредна.
( grep -q "никогда-не-встретится-$$" "$VICTIM"; sleep 20 ) & GPID=$!
_wait=0
while ! ps -p "$GPID" >/dev/null 2>&1 && [ "$_wait" -lt 50 ]; do sleep 0.2; _wait=$((_wait+1)); done
OUT5=$(ask "$VICTIM")
kill "$GPID" 2>/dev/null; wait "$GPID" 2>/dev/null
[ -z "$OUT5" ] && ok T5 || bad T5 "сказал о файле, который процесс лишь упоминает: «${OUT5}»"

# T6. Не-shell файл страж не судит: интерпретатор Python читает файл целиком.
PY="$TMP/thing.py"; printf 'pass\n' > "$PY"
[ -z "$(ask "$PY")" ] && ok T6 || bad T6 "судил .py"

# T7–T9 — ТОТ ЖЕ ФАЙЛ, А НЕ ТО ЖЕ ИМЯ (D1090). Повод: правка копии хука в репозитории звалась опасной, пока исполнялась
# установленная копия с тем же именем — отдельный файл.
mkdir -p "$TMP/inst" "$TMP/repo" "$TMP/sub" "$TMP/away"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$TMP/inst/twin.sh"; cp "$TMP/inst/twin.sh" "$TMP/repo/twin.sh"
cp "$TMP/inst/twin.sh" "$TMP/sub/rel.sh"; cp "$TMP/inst/twin.sh" "$TMP/away/rel.sh"
printf '#!/usr/bin/env bash\ncd /\nsleep 30\n' > "$TMP/sub/hop.sh"
live() { local _w=0; while ! ps -p "$1" >/dev/null 2>&1 && [ "$_w" -lt 50 ]; do sleep 0.2; _w=$((_w+1)); done; sleep 0.3; }
bash "$TMP/inst/twin.sh" & P7=$!
( cd "$TMP/sub" && exec bash rel.sh ) & P8=$!
( cd "$TMP" && exec bash sub/hop.sh ) & P9=$!
live "$P7"; live "$P8"; live "$P9"
# T7. Исполняется одноимённый ДРУГОЙ файл (абсолютный путь) — правка этого молчит; правка исполняемого — названа.
[ -z "$(ask "$TMP/repo/twin.sh")" ] && ok T7 || bad T7 "назвал занятым другой файл с тем же именем"
grep -q "исполняется ПРЯМО СЕЙЧАС" <<< "$(ask "$TMP/inst/twin.sh")" && ok T7b || bad T7b "промолчал на исполняемом файле"
# T8. Относительный путь — от каталога процесса: исполняемый назван, одноимённый в другом каталоге молчит.
grep -q "исполняется ПРЯМО СЕЙЧАС" <<< "$(ask "$TMP/sub/rel.sh")" && ok T8 || bad T8 "относительный путь не развёрнут от каталога процесса"
[ -z "$(ask "$TMP/away/rel.sh")" ] && ok T8b || bad T8b "назвал занятым одноимённый файл другого каталога"
# T9. Процесс сменил каталог (как `run_all.sh`): путь не разворачивается — прежняя сверка по имени, файл назван.
grep -q "исполняется ПРЯМО СЕЙЧАС" <<< "$(ask "$TMP/sub/hop.sh")" && ok T9 || bad T9 "пропустил занятый файл процесса, сменившего каталог"
kill "$P7" "$P8" "$P9" 2>/dev/null; wait "$P7" "$P8" "$P9" 2>/dev/null

echo "running-file-edit-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
