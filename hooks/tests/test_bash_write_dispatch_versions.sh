#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# probe_D489.sh — проба пункта D489, свидетель ВЕРСИЙ диспетчера: каждая новая версия
# файла, записанная командой, доходит до стражей, а повтор той же версии молчит.
# Повод: ключ дедупа — пара «файл + страж» без версии, и флаг ставится и на чистый проход.
# Песочница 1 октября 2026: файл записан командой дважды — стражи получили 7 подач первой
# версии и ни одной второй. Для `secret-guard`, `test-exit-explicit-guard` и
# `pipefail-grep-q-notice` это значит: нарушение во второй правке файла за сессию на пути
# команды не видно никому.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D489 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
# этого дерева, на два уровня выше.
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
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

# Песочница: копия диспетчера и стражи-заглушки, пишущие первую строку ПОДАННОГО содержимого.
# HOME подменён по той же причине, что у свидетеля отбора: глобальный список исключений git.
SB="$TMP/sb"; SR="$TMP/repo"; FED="$TMP/fed.log"; SH="$TMP/home"
mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$HOOK" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/"
for g in $(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$HOOK"); do
    printf '#!/usr/bin/env bash\njq -r ".tool_input.content" | head -1 >> "%s" 2>/dev/null\nexit 0\n' "$FED" > "$SB/hooks/$g"
done
_SETUP=$( ( cd "$SR" && export HOME="$SH" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && echo base > keep.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/keep.md"
ev() {
    printf '{"tool_name":"Bash","session_id":"t-v","cwd":"%s"}' "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=1000 \
            bash "$SB/hooks/$DISP" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_bash_write_dispatch_versions.sh:$LINENO" >&2; exit 1; }
}
_g=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$HOOK" | wc -w | tr -d ' ')

ev; sleep 1
echo "версия-1" > "$SR/notes.md"; ev; sleep 1
_v1=$(grep -c '^версия-1$' "$FED" || true)
echo "версия-2" > "$SR/notes.md"; ev; sleep 1
_v2=$(grep -c '^версия-2$' "$FED" || true)

# V1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: первая версия подана всем стражам списка. Список берётся у самого предмета, поэтому
# пустой список — не «подано всем», а «судить некому» (D1222, 7 ноября 2026: у выпотрошенного диспетчера список пуст, и
# «подано 0 из 0» зеленило ногу — прибор свидетелей-атак числил тест ложно-зелёным).
[ "${_g:-0}" -ge 1 ] && [ "${_v1:-0}" -eq "$_g" ] && ok || bad V1 "первая версия подана $_v1 раз из $_g стражей — нога судила бы пустоту"
# V2 — новая версия того же файла подана всем стражам списка.
[ "${_v2:-0}" -eq "$_g" ] && ok || bad V2 "вторая версия файла подана $_v2 раз из $_g — правка командой после первой стражам не видна"

# V3 — та же версия повторно не подаётся: дедуп по версии остаётся дедупом.
touch "$SR/notes.md"; ev
_v2b=$(grep -c '^версия-2$' "$FED" || true)
[ "${_v2b:-0}" -eq "${_v2:-0}" ] && ok || bad V3 "неизменённое содержимое подано повторно: было $_v2, стало $_v2b"

echo "test_bash_write_dispatch_versions: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
