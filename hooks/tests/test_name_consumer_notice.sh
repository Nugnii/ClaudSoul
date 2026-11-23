#!/usr/bin/env bash
# СУДИТ: hooks/name-consumer-notice.sh hooks/lib/name_consumers.py
# test_name_consumer_notice.sh — правка, снимающая с файла чтение переменной окружения, называет тех, кто её ещё задаёт и зовёт этот файл (D1200).
#
# Результат: повод D1200 и его формы названы (Edit, Write, MultiEdit, подача диспетчера, неучтённый потребитель,
#            чтение в Python); законные — молчат (чтение через названную библиотеку, потребитель не зовёт файл,
#            потребитель только читает, файла нет в коммите, правка не применится, повтор).
# Проверка результата: bash hooks/tests/test_name_consumer_notice.sh даёт 0
#
# Ноги держат обе стороны различения: без тишины тест зеленел бы у стража, кричащего на любое снятое имя
# (на истории 13 таких из 16), без находок — у немого. Хелперы — у соседа test_pipefail_grep_q_notice.sh.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/name-consumer-notice.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_silent()   { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: ${1}"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: ${1}"; fi; }
assert_not_contains() { if grep -Fq "$2" <<< "$1"; then bad "$3" "есть '$2' в: ${1}"; else ok; fi; }
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "SKIP: нет python3 или jq"; exit 0; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ncn.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
# Дерево с файлом, читающим ARCH_PATH, и потребителем, задающим его и зовущим файл. $1 — каталог.
mkrepo() {
    local d="$1"; mkdir -p "$d/scripts" "$d/tests"
    git -C "$d" init -q && git -C "$d" config user.email t@t && git -C "$d" config user.name t
    printf '#!/usr/bin/env bash\nA="${ARCH_PATH:-x.md}"\necho "$A"\n' > "$d/scripts/recheck.sh"
    printf '#!/usr/bin/env bash\nARCH_PATH=/tmp/a.md bash scripts/recheck.sh\n' > "$d/tests/probe.sh"
    git -C "$d" add -A && git -C "$d" commit -qm init
}
# Событие правки; печатает ответ хука. $1 — JSON tool_input, $2 — имя инструмента, $3 — событие.
# Сессия у каждого вызова своя и случайная: `run` зовётся из подстановки, счётчик в ней не дожил бы до следующего.
run() {
    jq -cn --argjson ti "$1" --arg t "${2:-Edit}" --arg e "${3:-PreToolUse}" --arg s "s$RANDOM$RANDOM" \
        '{hook_event_name:$e, tool_name:$t, session_id:$s, tool_input:$ti}' | bash "$GUARD" 2>&1
}
edit() { jq -cn --arg f "$1" --arg o "$2" --arg n "$3" '{file_path:$f, old_string:$o, new_string:$n}'; }

R="$TMP/r1"; mkrepo "$R"
F="$R/scripts/recheck.sh"
# --- T1: повод — переименование читаемой переменной, потребитель задаёт старое имя и зовёт файл ---
OUT=$(run "$(edit "$F" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")
assert_contains "$OUT" "tests/probe.sh:2" "T1: потребитель повода не назван"
assert_contains "$OUT" "ARCH_PATH" "T1: снятое имя не названо"
assert_contains "$OUT" '"hookEventName":"PreToolUse"' "T1: событие ответа не то"

# --- T2: старое чтение осталось в комментарии — чтением не считается (мутант «комментарий — код» краснит) ---
OUT=$(run "$(edit "$F" 'A="${ARCH_PATH:-x.md}"' '# было A="${ARCH_PATH:-x.md}" — свой путь, не общий
A="${RECHECK_ARCH:-x.md}"')")
assert_contains "$OUT" "tests/probe.sh:2" "T2: слово в комментарии сочтено чтением"

# --- T3: правка не снимает чтения — молчание ---
assert_silent "$(run "$(edit "$F" 'echo "$A"' 'printf "%s\n" "$A"')")" "T3: заговорил без снятого имени"

# --- T4: чтение уходит в библиотеку, которую файл называет, — договор остался ---
printf '#!/usr/bin/env bash\nA="${ARCH_PATH:-x.md}"\n' > "$R/scripts/paths-lib.sh"
assert_silent "$(run "$(edit "$F" 'A="${ARCH_PATH:-x.md}"' '. "$(dirname "$0")/paths-lib.sh"')")" "T4: чтение через названную библиотеку сочтено снятием"
rm -f "$R/scripts/paths-lib.sh"

# --- T5: Write целиком ---
OUT=$(run "$(jq -cn --arg f "$F" '{file_path:$f, content:"#!/usr/bin/env bash\necho x\n"}')" Write)
assert_contains "$OUT" "tests/probe.sh:2" "T5: Write не судится"

# --- T6: MultiEdit — правки применяются по порядку ---
OUT=$(run "$(jq -cn --arg f "$F" '{file_path:$f, edits:[{old_string:"echo", new_string:"printf"}, {old_string:"ARCH_PATH", new_string:"NEW_ARCH"}]}')" MultiEdit)
assert_contains "$OUT" "tests/probe.sh:2" "T6: MultiEdit не судится"

# --- T7: подача диспетчера — файл уже записан, «было» берётся у коммита ---
cp "$F" "$TMP/recheck.orig"
printf '#!/usr/bin/env bash\nA="${RECHECK_ARCH:-x.md}"\n' > "$F"
OUT=$(run "$(jq -cn --arg f "$F" --rawfile c "$F" '{file_path:$f, content:$c}')" Write PostToolUse)
assert_contains "$OUT" "tests/probe.sh:2" "T7: подача диспетчера не судится"
assert_contains "$OUT" '"hookEventName":"PostToolUse"' "T7: событие ответа не то"
cp "$TMP/recheck.orig" "$F"

# --- T8: повтор той же находки в той же сессии — молчание ---
P=$(jq -cn --argjson ti "$(edit "$F" 'ARCH_PATH:-' 'RECHECK_ARCH:-')" '{hook_event_name:"PreToolUse", tool_name:"Edit", session_id:"same", tool_input:$ti}')
OUT=$(bash "$GUARD" <<< "$P"); assert_contains "$OUT" "tests/probe.sh:2" "T8: первая подача молчит"
assert_silent "$(bash "$GUARD" <<< "$P")" "T8: повтор той же находки в сессии не погашен"

# --- T9: неучтённый потребитель (новый файл соседней сессии) — найден (D1240) ---
printf 'ARCH_PATH=/x bash scripts/recheck.sh\n' > "$R/tests/fresh.sh"
OUT=$(run "$(edit "$F" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")
assert_contains "$OUT" "tests/fresh.sh:1" "T9: неучтённый потребитель не найден"
rm -f "$R/tests/fresh.sh"

# --- T10: потребитель задаёт имя, но файла не зовёт — молчание ---
R2="$TMP/r2"; mkrepo "$R2"
printf '#!/usr/bin/env bash\nARCH_PATH=/tmp/a.md bash scripts/other.sh\n' > "$R2/tests/probe.sh"
git -C "$R2" commit -qam other
assert_silent "$(run "$(edit "$R2/scripts/recheck.sh" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")" "T10: потребитель чужого файла назван"

# --- T11: потребитель только читает — не задаёт, ломать нечего ---
printf '#!/usr/bin/env bash\necho "$ARCH_PATH"; bash scripts/recheck.sh\n' > "$R2/tests/probe.sh"
git -C "$R2" commit -qam reader
assert_silent "$(run "$(edit "$R2/scripts/recheck.sh" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")" "T11: читатель сочтён потребителем"

# --- T12: файла нет в последнем коммите — снимать нечего ---
printf '#!/usr/bin/env bash\nB="${ARCH_PATH:-y}"\n' > "$R/scripts/new.sh"
printf 'ARCH_PATH=/z bash scripts/new.sh\n' > "$R/tests/new_probe.sh"
assert_silent "$(run "$(edit "$R/scripts/new.sh" 'ARCH_PATH' 'NEW_PATH')")" "T12: файл вне коммита судится"
rm -f "$R/scripts/new.sh" "$R/tests/new_probe.sh"

# --- T13: правка не применится (old_string не найден) — молчание ---
assert_silent "$(run "$(edit "$F" 'нет такого текста' 'x')")" "T13: судилась неприменимая правка"

# --- T14: чтение в Python и задание словарём окружения ---
R3="$TMP/r3"; mkdir -p "$R3"
git -C "$R3" init -q && git -C "$R3" config user.email t@t && git -C "$R3" config user.name t
printf 'import os\nA = os.environ.get("ARCH_PATH", "x")\n' > "$R3/tool.py"
printf 'import subprocess\nsubprocess.run(["python3", "tool.py"], env={"ARCH_PATH": "/a"})\n' > "$R3/caller.py"
git -C "$R3" add -A && git -C "$R3" commit -qm py
OUT=$(run "$(edit "$R3/tool.py" '"ARCH_PATH"' '"NEW_ARCH"')")
assert_contains "$OUT" "caller.py:2" "T14: потребитель Python не назван"

# --- T15: не код и вне репозитория — молчание ---
assert_silent "$(run "$(jq -cn --arg f "$R/README.md" '{file_path:$f, content:"x"}')" Write)" "T15: не код судится"
printf 'A="${ARCH_PATH:-x}"\n' > "$TMP/loose.sh"
assert_silent "$(run "$(edit "$TMP/loose.sh" 'ARCH_PATH' 'NEW_PATH')")" "T15: файл вне репозитория судится"

# --- T16: разбор сломан — говорит, а не молчит ---
mkdir -p "$TMP/badhooks/lib"
cp "$GUARD" "$TMP/badhooks/"; cp "$REPO/hooks/paths-lib.sh" "$TMP/badhooks/"
printf 'import sys\nsys.exit(5)\n' > "$TMP/badhooks/lib/name_consumers.py"
OUT=$(jq -cn --argjson ti "$(edit "$F" 'ARCH_PATH:-' 'RECHECK_ARCH:-')" '{tool_name:"Edit", session_id:"bad", tool_input:$ti}' | bash "$TMP/badhooks/name-consumer-notice.sh")
assert_contains "$OUT" "НЕ ПРОВЕРЕНЫ" "T16: сломанный разбор промолчал"
assert_not_contains "$OUT" "tests/probe.sh" "T16: сломанный разбор выдал находку"

# --- T17: потребитель не читается — назван как непрочитанный, а не выпал молча (род B) ---
printf 'ARCH_PATH=/x bash scripts/recheck.sh\n' > "$R/tests/locked.sh"; chmod 000 "$R/tests/locked.sh"
if [ -r "$R/tests/locked.sh" ]; then echo "SKIP [T17]: права не отнимаются (root?)"; else
    OUT=$(run "$(edit "$F" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")
    assert_contains "$OUT" "tests/locked.sh — не прочитан" "T17: непрочитанный потребитель выпал молча"
fi
chmod 600 "$R/tests/locked.sh"; rm -f "$R/tests/locked.sh"

# --- T18: вход хука не разобран — говорит, а не молчит (род B) ---
OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"' "$F" | bash "$GUARD" 2>&1)
assert_contains "$OUT" "НЕ ПРОВЕРЕНЫ" "T18: неразборный вход прочитан как «находок нет»"

# --- Ноги круга скептика opus по d0deffd0: у каждой свой мутант, снимающий одно условие (M1–M4, L1, L3, L4) ---
# T19 (M1): второй читатель имени есть, но F его не называет — договор не держит, находка остаётся
R5="$TMP/r5"; mkrepo "$R5"
printf '#!/usr/bin/env bash\nX="${ARCH_PATH:-y}"\n' > "$R5/scripts/archiver.sh"
OUT=$(run "$(edit "$R5/scripts/recheck.sh" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")
assert_contains "$OUT" "tests/probe.sh:2" "T19: читатель, которого F не называет, погасил находку"

# T20 (m3): replace_all снимает оба чтения — находка; без replace_all второе чтение остаётся — тишина
R6="$TMP/r6"; mkrepo "$R6"
printf '#!/usr/bin/env bash\nA="${ARCH_PATH:-x}"\nB="${ARCH_PATH:-x}"\n' > "$R6/scripts/recheck.sh"; git -C "$R6" commit -qam twice
OUT=$(run "$(jq -cn --arg f "$R6/scripts/recheck.sh" '{file_path:$f, old_string:"ARCH_PATH:-", new_string:"NEW_ARCH:-", replace_all:true}')")
assert_contains "$OUT" "tests/probe.sh:2" "T20: replace_all не применён"
assert_silent "$(run "$(edit "$R6/scripts/recheck.sh" 'ARCH_PATH:-' 'NEW_ARCH:-')")" "T20: без replace_all снято и второе чтение"

# T21 (m5): в одной сессии вторая, ДРУГАЯ находка по тому же файлу — говорит (ключ — состав, а не путь)
R7="$TMP/r7"; mkrepo "$R7"
printf '#!/usr/bin/env bash\nA="${ONE_PATH:-x}"\nB="${TWO_PATH:-x}"\n' > "$R7/scripts/recheck.sh"
printf '#!/usr/bin/env bash\nONE_PATH=/a TWO_PATH=/b bash scripts/recheck.sh\n' > "$R7/tests/probe.sh"; git -C "$R7" commit -qam two
P1=$(jq -cn --argjson ti "$(edit "$R7/scripts/recheck.sh" 'ONE_PATH:-' 'NEW_ONE:-')" '{tool_name:"Edit", session_id:"same21", tool_input:$ti}')
P2=$(jq -cn --argjson ti "$(edit "$R7/scripts/recheck.sh" 'TWO_PATH:-' 'NEW_TWO:-')" '{tool_name:"Edit", session_id:"same21", tool_input:$ti}')
# Подготовка проверяется: без первой находки вторая судилась бы на пустом журнале и зеленела по неверной причине.
OUT=$(bash "$GUARD" <<< "$P1"); assert_contains "$OUT" "ONE_PATH" "T21: подготовка — первая находка не выдана"
OUT=$(bash "$GUARD" <<< "$P2"); assert_contains "$OUT" "TWO_PATH" "T21: другая находка того же файла погашена дедупом"

# T22 (m6): потребитель называет F только в комментарии — не потребитель
R8="$TMP/r8"; mkrepo "$R8"
printf '#!/usr/bin/env bash\n# зовёт scripts/recheck.sh\nARCH_PATH=/q bash "$X"\n' > "$R8/tests/commented.sh"
OUT=$(run "$(edit "$R8/scripts/recheck.sh" 'ARCH_PATH:-' 'RECHECK_ARCH:-')")
assert_contains "$OUT" "tests/probe.sh:2" "T22: настоящий потребитель не назван"
assert_not_contains "$OUT" "tests/commented.sh" "T22: названный в комментарии сочтён потребителем"

# T23 (m7): MultiEdit — снятие первой правкой, посторонняя последней
OUT=$(run "$(jq -cn --arg f "$R8/scripts/recheck.sh" '{file_path:$f, edits:[{old_string:"ARCH_PATH:-", new_string:"NEW_ARCH:-"}, {old_string:"echo", new_string:"printf"}]}')" MultiEdit)
assert_contains "$OUT" "tests/probe.sh:2" "T23: MultiEdit применил не все правки"

# T24 (M2): читатель назван в новой редакции только прозой — не подключение, находка остаётся
R9="$TMP/r9"; mkrepo "$R9"
printf '#!/usr/bin/env bash\nX="${ARCH_PATH:-y}"\n' > "$R9/scripts/archive-lib.sh"
OUT=$(run "$(edit "$R9/scripts/recheck.sh" 'A="${ARCH_PATH:-x.md}"' 'echo "путь читает archive-lib.sh"
A="${RECHECK_ARCH:-x.md}"')")
assert_contains "$OUT" "tests/probe.sh:2" "T24: упоминание прозой (кириллица) сочтено подключением"
# ...и докстрока питона — тоже проза, даже без кириллицы
R10="$TMP/r10"; mkdir -p "$R10"
git -C "$R10" init -q && git -C "$R10" config user.email t@t && git -C "$R10" config user.name t
printf 'import os\nA = os.environ.get("ARCH_PATH", "x")\n' > "$R10/tool.py"
printf 'import os\nB = os.environ.get("ARCH_PATH", "y")\n' > "$R10/lib_reader.py"
printf 'import subprocess\nsubprocess.run(["python3", "tool.py"], env={"ARCH_PATH": "/a"})\n' > "$R10/caller.py"
git -C "$R10" add -A && git -C "$R10" commit -qm py
OUT=$(run "$(jq -cn --arg f "$R10/tool.py" '{file_path:$f, content:"\"\"\"Pairs with lib_reader.\"\"\"\nimport os\nA = os.environ.get(\"NEW_ARCH\", \"x\")\n"}')" Write)
assert_contains "$OUT" "caller.py:2" "T24: упоминание в докстроке сочтено подключением"

# T25 (M4): чтение через обёртку — голый литерал в файле, трогающем окружение
printf 'import os\ndef _int(k, d): return int(os.environ.get(k, d))\nT = _int("ARCH_TIMEOUT", 3)\n' > "$R10/tool2.py"
printf 'import subprocess\nsubprocess.run(["python3", "tool2.py"], env={"ARCH_TIMEOUT": "1"})\n' > "$R10/caller2.py"
git -C "$R10" add -A && git -C "$R10" commit -qm wrap
OUT=$(run "$(edit "$R10/tool2.py" '"ARCH_TIMEOUT"' '"NEW_TIMEOUT"')")
assert_contains "$OUT" "caller2.py:2" "T25: чтение через обёртку не увидено"

# T26 (M4): задание через monkeypatch.setenv; T27 (L1): чистый читатель os.environ["X"] — не потребитель
printf 'import tool\ndef test_x(monkeypatch):\n    monkeypatch.setenv("ARCH_PATH", "/a")\n' > "$R10/test_tool.py"
printf 'import os, subprocess\nsubprocess.run(["python3", "tool.py"])\nx = os.environ["ARCH_PATH"]\n' > "$R10/reader.py"
OUT=$(run "$(edit "$R10/tool.py" '"ARCH_PATH"' '"NEW_ARCH"')")
assert_contains "$OUT" "test_tool.py:3" "T26: monkeypatch.setenv не увидено"
assert_not_contains "$OUT" "reader.py" "T27: чистый читатель os.environ[...] сочтён задающим"

# T28 (M3): подача диспетчера после свежего коммита — «было» у родителя; старый коммит — тишина
R11="$TMP/r11"; mkrepo "$R11"
printf '#!/usr/bin/env bash\nA="${RECHECK_ARCH:-x.md}"\n' > "$R11/scripts/recheck.sh"; git -C "$R11" commit -qam rename
OUT=$(run "$(jq -cn --arg f "$R11/scripts/recheck.sh" --rawfile c "$R11/scripts/recheck.sh" '{file_path:$f, content:$c}')" Write PostToolUse)
assert_contains "$OUT" "tests/probe.sh:2" "T28: коммит той же командой спрятал снятие"
assert_contains "$OUT" "Коммит" "T28: подсказка не называет, что снятие уже в коммите"
R12="$TMP/r12"; mkrepo "$R12"
printf '#!/usr/bin/env bash\nA="${RECHECK_ARCH:-x.md}"\n' > "$R12/scripts/recheck.sh"
GIT_COMMITTER_DATE="2026-01-01T00:00:00" git -C "$R12" commit -qam rename
assert_silent "$(run "$(jq -cn --arg f "$R12/scripts/recheck.sh" --rawfile c "$R12/scripts/recheck.sh" '{file_path:$f, content:$c}')" Write PostToolUse)" "T28: давний коммит судится как свежий"

# T29 (L3): копия F с той же основой читает имя — договора у F не держит
R13="$TMP/r13"; mkrepo "$R13"
mkdir -p "$R13/old"; cp "$R13/scripts/recheck.sh" "$R13/old/recheck.sh"
OUT=$(run "$(edit "$R13/scripts/recheck.sh" 'A="${ARCH_PATH:-x.md}"' 'TAG=recheck
A="${RECHECK_ARCH:-x.md}"')")
assert_contains "$OUT" "tests/probe.sh:2" "T29: копия F с той же основой погасила находку"

# T30 (M4): чтение awk ENVIRON; L4: адрес — строка задания рядом с вызовом F
R14="$TMP/r14"; mkrepo "$R14"
printf '#!/usr/bin/env bash\nawk %s\n' "'BEGIN { print ENVIRON[\"ARCH_PATH\"] }'" > "$R14/scripts/recheck.sh"
printf '#!/usr/bin/env bash\nARCH_PATH=/a bash scripts/other.sh\nARCH_PATH=/b bash scripts/recheck.sh\n' > "$R14/tests/probe.sh"
git -C "$R14" commit -qam awk
OUT=$(run "$(edit "$R14/scripts/recheck.sh" 'ENVIRON["ARCH_PATH"]' 'ENVIRON["NEW_ARCH"]')")
assert_contains "$OUT" "tests/probe.sh:3" "T30: awk ENVIRON не увиден либо адрес — не строка вызова F"

# T31: прокладка — F подключает одноимённый файл из другого каталога, тот читает имя (40f9c372) — тишина
R15="$TMP/r15"; mkrepo "$R15"
mkdir -p "$R15/lib"; printf '#!/usr/bin/env bash\nA="${ARCH_PATH:-x.md}"\n' > "$R15/lib/recheck.sh"
# Живая форма прокладки (hooks/tests/universe-lib.sh в 40f9c372): каталог и имя разделены `" && pwd)/`.
assert_silent "$(run "$(edit "$R15/scripts/recheck.sh" 'A="${ARCH_PATH:-x.md}"' '. "$(cd "$(dirname "$0")/../lib" && pwd)/recheck.sh"')")" "T31: прокладка к одноимённой библиотеке сочтена снятием"

# T32: имя читается по префиксу (`startswith("ARCH_")`, b281b0ea) — не снято
R16="$TMP/r16"; mkdir -p "$R16"
git -C "$R16" init -q && git -C "$R16" config user.email t@t && git -C "$R16" config user.name t
printf 'import os\nSCRUB = ("ARCH_PATH", "ARCH_ROOT")\nenv = dict((k, v) for k, v in os.environ.items() if k not in SCRUB)\n' > "$R16/tool.py"
printf 'import subprocess\nsubprocess.run(["python3", "tool.py"], env={"ARCH_PATH": "/a"})\n' > "$R16/caller.py"
git -C "$R16" add -A && git -C "$R16" commit -qm prefix
# Обе половины пишут файл целиком: кортеж SCRUB с литералом имени сам держал бы чтение, и тишина шла бы не от префикса.
# Содержимое — файлом через --rawfile: `{k: v for k, v …}` внутри `"$(… '…' …)"` системный bash 3.2 раскрывает как скобки.
printf 'import os\nenv = dict((k, v) for k, v in os.environ.items() if not k.startswith("ARCH_"))\n' > "$TMP/t32a.py"
printf 'import os\nenv = dict((k, v) for k, v in os.environ.items() if k != "OTHER_NAME")\n' > "$TMP/t32b.py"
assert_silent "$(run "$(jq -cn --arg f "$R16/tool.py" --rawfile c "$TMP/t32a.py" '{file_path:$f, content:$c}')" Write)" "T32: чтение по префиксу сочтено снятием"
OUT=$(run "$(jq -cn --arg f "$R16/tool.py" --rawfile c "$TMP/t32b.py" '{file_path:$f, content:$c}')" Write)
assert_contains "$OUT" "caller.py:2" "T32: без префикса снятие не названо (нога не различает)"

echo "name-consumer-notice: $PASS прошло, $FAIL упало"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
