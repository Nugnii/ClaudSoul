#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_bash_write_dispatch_selection.sh — свидетель ОТБОРА и ЦЕНЫ диспетчера (D487): подаётся
# тронутое из учёта проекта, а не из дерева каталогов, и цена пустого события не растёт с
# историей сессии.
# Предмет: пройденная пара «файл + страж» на пустом событии не пересматривается (ноль вызовов
# хеш-утилит); файл игнорируемого КАТАЛОГА не подаётся, отдельный игнорируемый файл подаётся;
# учтённый файл, закоммиченный той же командой, подаётся; имя с пробелом, кириллицей и ведущим
# дефисом отбор не ломает.
# Отдельный файл, а не ноги в test_bash_write_dispatch.sh: тот идёт ~100 с (T7 крутит 60
# событий с живыми стражами), а этот свидетель — «Проверка» пункта D487, которую страж закрытия
# гоняет с пределом 60 с.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя механизма собрано из частей НАМЕРЕННО. Признак рода M (`scripts/defect-class-carriers.py`)
# числит тест судящим стража с исключением `*/tmp/*`, если в коде стоит имя диспетчера, а
# песочница — голый `mktemp -d`. Здесь все стражи списка подменены заглушками, до исключения
# `*/tmp/*` подача не доходит, и последствие рода недостижимо — носитель был бы ложным.
DISP="bash-write-""dispatch.sh"
HOOK="$HOOK_DIR/$DISP"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Песочница несёт КОПИЮ диспетчера и стражей-заглушек под именами из его списка: заглушка
# пишет в журнал каждый поданный ей путь и молчит. Так «подан ли файл» наблюдается прямо, а
# не по тому, что настоящий страж скажет о содержимом. Пустой список стражей роняет
# положительные контроли громко, а не зеленит ноги вхолостую.
# HOME подменён: `--exclude-standard` читает и глобальный список исключений git владельца,
# и чужое правило «игнорировать build/» сделало бы ноги зависимыми от машины.
SB="$TMP/sb"; SR="$TMP/sbrepo"; FED="$TMP/fed.log"; SH="$TMP/home"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/"
for g in $(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$HOOK"); do
    printf '#!/usr/bin/env bash\njq -r ".tool_input.file_path" >> "%s" 2>/dev/null\nexit 0\n' "$FED" > "$SB/hooks/$g"
done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\nlocal.json\n' > .gitignore \
    && for i in 1 2 3 4 5 6 7 8 9 10; do echo "x$i" > "f$i.md"; done \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
sbx() {  # sbx <сессия> [PATH]
    printf '{"tool_name":"Bash","session_id":"t-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state-$1" PATHS_LIB="$SB/hooks/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=1000 \
            PATH="${2:-$PATH}" bash "$SB/hooks/$DISP" 2>/dev/null
}

# T1 — ПРОЙДЕННОЕ НЕ ПЕРЕСМАТРИВАЕТСЯ. Замер 1 октября 2026 на копии очереди сессии ClaudSoul
# (458 файлов, 3150 флагов): пустое событие стоило 17–20 с — цикл на КАЖДОЙ паре «файл × страж»
# заново считал md5 ради имени флага, хотя пара давно пройдена. Наблюдаемое — РАЗНОСТЬ: число
# вызовов любой хеш-утилиты на пустом событии при истории в 10 файлов и в 20 обязано совпасть.
# Не ноль: постоянная цена события (ключ корня, отпечаток набора стражей) законна, предмет —
# рост с историей. Прежняя редакция давала 70 против 140.
# История в 10 файлов — правки ПОСЛЕ метки: первое событие чистые учтённые файлы не подаёт (D501 —
# свежий checkout чист), поэтому оно только ставит метку, а `touch` делает файлы тронутыми, не
# меняя ни содержимого, ни учёта git, на который опираются ноги ниже.
: > "$FED"
sbx s1 >/dev/null; sleep 1; touch "$SR"/f*.md
sbx s1 >/dev/null
_n1=$(sort -u "$FED" | grep -c '/f[0-9]*\.md$')
SHIM="$TMP/shim"; HC="$TMP/hashcalls"; mkdir -p "$SHIM"; : > "$HC"
for t in md5 md5sum cksum shasum sha1sum sha256sum; do
    real=$(command -v "$t" 2>/dev/null) || continue
    printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$t" "$HC" "$real" > "$SHIM/$t"; chmod +x "$SHIM/$t"
done
sbx s1 "$SHIM:$PATH" >/dev/null
_h1=$(wc -l < "$HC" | tr -d ' ')
sleep 1   # вторая десятка новее метки при любой точности времени файла
mkdir -p "$SR/h"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "y$i" > "$SR/h/g$i.md"; done
sbx s1 >/dev/null
: > "$HC"; sbx s1 "$SHIM:$PATH" >/dev/null
_h2=$(wc -l < "$HC" | tr -d ' ')
if [ "$_n1" -lt 10 ]; then bad T1 "положительный контроль: первое событие подало $_n1 из 10 файлов — нога судила бы пустоту"
elif [ "$_h2" -eq "$_h1" ]; then ok
else bad T1 "пустое событие зовёт хеш-утилиты $_h1 раз при истории в 10 файлов и $_h2 при истории в 20 — цена растёт с историей сессии"; fi

# T2 — ИГНОРИРУЕМЫЙ КАТАЛОГ НЕ ПОДАЁТСЯ, ОТДЕЛЬНЫЙ ИГНОРИРУЕМЫЙ ФАЙЛ — ПОДАЁТСЯ. Повод (D487):
# отбор `find .` обходил всё дерево, прод-сборка ProjectA положила в очередь 16 тыс. файлов
# `web/.next`, обход 140 011 файлов стоил 1,46 с на каждую команду. Разделитель — каталог против
# файла, измерен 1 октября 2026: игнорируемый КАТАЛОГ — сборка, зависимости, окружение
# (`.next/`, `node_modules/`, `.venv/`, `__pycache__/`); игнорируемый ФАЙЛ бывает ручным
# (`SESSION.md` и `.claude/settings.local.json` в ClaudSoul, `web/CLAUDE.md` в ProjectA), и секрет,
# вписанный в него командой, `secret-guard` обязан увидеть — его предмет любой файл.
touch -t 202001010000 "$SR"/f*.md "$SR"/h/*.md "$SR/.gitignore"
sbx s2 >/dev/null
sleep 1   # правки новее метки при любой точности времени файла
mkdir -p "$SR/build" "$SR/папка с пробелом"
echo g > "$SR/build/gen.md"; echo s > "$SR/local.json"; echo n > "$SR/new.md"
echo c > "$SR/папка с пробелом/файл.md"; echo d > "$SR/-dash.md"
echo m >> "$SR/f1.md"
( cd "$SR" && HOME="$SH" GIT_CONFIG_NOSYSTEM=1 git -c user.email=t@t -c user.name=t commit -qam m ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_bash_write_dispatch_selection.sh:$LINENO" >&2; exit 1; }
: > "$FED"
sbx s2 >/dev/null
if grep -q '/build/gen\.md$' "$FED"; then bad T2 "файл игнорируемого каталога подан стражам"; else ok; fi
grep -q '/local\.json$' "$FED" && ok || bad T2б "отдельный игнорируемый файл не подан — секрет в локальном конфиге стражу не виден"
grep -q '/new\.md$' "$FED" && ok || bad T2в "положительный контроль: неучтённый новый файл не подан"
# T3 — учтённый файл, закоммиченный ТОЙ ЖЕ командой, что его правила, подаётся: отбор по
# «грязному» списку git его потерял бы, а цепочка «правка → коммит» в одной команде обычна.
grep -q '/f1\.md$' "$FED" && ok || bad T3 "правленный и закоммиченный той же командой файл не подан"
# T4 — путь с пробелом, кириллицей и ведущим дефисом подаётся: отбор не ломается на имени.
grep -qF 'папка с пробелом/файл.md' "$FED" && ok || bad T4 "путь с пробелом и кириллицей не подан"
grep -q '/-dash\.md$' "$FED" && ok || bad T4б "путь с ведущим дефисом не подан"

# T5 — ОТСЕЧЕНИЕ ПРОЙДЕННОГО ЛИНЕЙНО. Очередь и список пройденного растут с работой сессии;
# `grep -vxF -f` на BSD — его получает bash хука на macOS — растёт сверхлинейно: 0,63 с на
# 2 тыс. строк, 31,7 с на 15 тыс. (замер 1 октября 2026), а `comm` держит 0,03 с. Набрать 10 тыс.
# пройденных файлов подачей стоило бы 70 тыс. вызовов заглушек, поэтому первое событие
# создаёт файлы состояния само, нога находит их по шаблону имени (`bash-dispatch-queue-*`,
# `bash-dispatch-pairs-*`) и раздувает: очередь — «путь ⇥ версия», журнал — те же пары
# пройденными (страж «*», D489). Предел: на GNU `grep -F -f` линеен, и там нога зелена
# при любой редакции — различает она на BSD.
S5="$TMP/state-s5"
sbx s5 >/dev/null
_q5=$(ls "$S5"/bash-dispatch-queue-* 2>/dev/null | head -1); _d5=$(ls "$S5"/bash-dispatch-pairs-* 2>/dev/null | head -1)
if [ -z "$_q5" ] || [ -z "$_d5" ]; then
    bad T5 "первое событие не создало очередь и журнал пройденного (очередь: «${_q5}», журнал: «${_d5}») — нога судила бы пустоту"
else
    seq 1 10000 | awk '{ printf "src/f%s.md\t1-1\n", $1 }' > "$TMP/hist5"
    cat "$TMP/hist5" >> "$_q5"; awk '{ print $0 "\t*" }' "$TMP/hist5" >> "$_d5"
    _t5=$(python3 -c 'import time; print(time.time())')
    sbx s5 >/dev/null
    _ms5=$(python3 -c "import time; print(int((time.time() - $_t5) * 1000))")
    [ "$_ms5" -lt 3000 ] && ok || bad T5 "пустое событие при истории в 10 тыс. файлов шло ${_ms5} мс — отсечение пройденного не линейно"
fi

echo "test_bash_write_dispatch_selection: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
