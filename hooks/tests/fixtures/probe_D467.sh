#!/usr/bin/env bash
# probe_D467.sh — «Проверка» пункта D467: значение канала `_SPIRAL` в блоке D411
# `scripts/backlog-recheck.sh` обязано различать СОСТОЯНИЯ МИРА, а не сводить их в одно
# сообщение про python3.
# Результат: семь подготовленных состояний дают ПОПАРНО РАЗЛИЧНЫЕ ответы блока D411, и
#            ТОЛЬКО состояние «инструментов нет» называет python3/git.
# Проверка результата: bash hooks/tests/fixtures/probe_D467.sh → 0. Сегодня 1 (дефект
#            наблюдён), 2 — рамка не собралась.
#
# ПОЧЕМУ СУД ПОПАРНЫЙ, А НЕ «КАЖДОЕ ПРОТИВ ЭТАЛОНА» (находка скептика 19 сентября 2026).
# Прежняя редакция сверяла каждое состояние только с эталоном «нет python3». Подделка,
# которая НИЧЕГО не разводит — переписывает текст ветки «?» на «карта НЕ ЦЕЛА» и решает по
# прокси «запустился ли python3», — проходила её зелёной, отвечая ТРЁМ разным состояниям
# мира одной и той же новой фразой. Различение доказывает только попарное сравнение.
#
# ПОЧЕМУ «ИНСТРУМЕНТОВ НЕТ» СТАВИТСЯ ТЕНЕВЫМ PATH, А НЕ ШИМОМ `exit 1`. Шим — это
# «интерпретатор ЕСТЬ и сломан», отдельное состояние мира; механизм теперь различает и его.
# Истинное отсутствие ставится PATH, где есть всё, кроме python3.
#
# Механизм берётся из CLAUDSOUL_REPO: зелёная сторона подставляет копию с починкой.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
[ -f "$MECH/scripts/backlog-recheck.sh" ] || { echo "probe_D467: нет $MECH/scripts/backlog-recheck.sh" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D467: нет python3 в оболочке хоста — рамка не собралась" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D467: нет git — рамка не собралась" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D467: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
P="$T/proj"
mkdir -p "$P/scripts" "$P/knowledge" "$P/mcp-server/visualization" "$P/hooks" "$T/home" "$T/lessons" "$T/nopy"
cp "$MECH/scripts/backlog-recheck.sh" "$P/scripts/" || exit 2
printf '# BACKLOG\n\n- ☑ **D1** тест\n' > "$P/BACKLOG.md"
printf 'origin: case\npreceded_artifact: none\n' > "$P/knowledge/META.md"
: > "$P/hooks/a.sh"
CACHE="$P/mcp-server/visualization/project-graph-data.json"
export HOME="$T/home" LESSONS_DIR="$T/lessons" STATE_DIR="$T/home/.claude/hooks/state" CLAUDSOUL_REPO="$P"

# Теневой PATH: всё, что есть в живом PATH, кроме python3 — истинное отсутствие инструмента.
for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
        _b=$(basename "$_f")
        case "$_b" in python3*|python) continue ;; esac
        [ -e "$T/nopy/$_b" ] || ln -s "$_f" "$T/nopy/$_b" 2>/dev/null
    done
done
[ -x "$T/nopy/git" ] || { echo "probe_D467: теневой PATH не собрался (нет git) — рамка не собралась" >&2; exit 2; }
if PATH="$T/nopy" command -v python3 >/dev/null 2>&1; then
    echo "probe_D467: теневой PATH всё ещё видит python3 — рамка не собралась" >&2; exit 2
fi

run() { bash "$P/scripts/backlog-recheck.sh" 2>&1; }
d411() { grep 'D411' <<< "$1" | head -1; }

INTACT='{"nodes":[{"id":1,"key":"hooks/a.sh","name":"a.sh","type":"hook"}],"edges":[{"source":1,"target":1,"type":"зовёт","strength":1}],"domains":[],"shared_names":{}}'

# Состояния мира. Порядок значения не имеет; важно, что ответы попарно различны.
printf '%s' "$INTACT" > "$CACHE"
L_OK=$(d411 "$(run)")                                   # карта цела
rm -f "$CACHE"
L_NOMAP=$(d411 "$(run)")                                # снимка нет
printf '%s' '{"nodes": [' > "$CACHE"
L_BADJSON=$(d411 "$(run)")                              # снимок не разбирается
printf '%s' '{"nodes":[{"id":1,"key":"hooks/a.sh","name":"a","type":"hook"}],"edges":[{"target":1,"type":"зовёт"}],"domains":[],"shared_names":{}}' > "$CACHE"
L_NOSRC=$(d411 "$(run)")                                # ребро без source
printf '%s' '{"nodes":"нет","edges":[],"domains":[],"shared_names":{}}' > "$CACHE"
L_NOTLIST=$(d411 "$(run)")                              # nodes не список
printf '%s' '{"nodes":[{"id":1,"key":"нет-такого.sh","name":"a","type":"hook"}],"edges":[{"source":1,"target":1,"type":"зовёт","strength":1}],"domains":[],"shared_names":{}}' > "$CACHE"
L_GHOST=$(d411 "$(run)")                                # в спайке нет существующих файлов
printf '%s' "$INTACT" > "$CACHE"
L_NOTOOLS=$(d411 "$(PATH="$T/nopy" run)")               # инструментов НЕТ

# Рамка: каждое состояние обязано дать строку. Пустая строка значит «блок не отработал»,
# а не «чисто», и различать это обязана рамка, а не суд.
_i=0
for _v in "$L_NOMAP" "$L_BADJSON" "$L_NOSRC" "$L_NOTLIST" "$L_GHOST" "$L_NOTOOLS"; do
    _i=$((_i + 1))
    [ -n "$_v" ] || { echo "probe_D467: состояние №$_i не дало строки D411 — рамка не собралась" >&2; exit 2; }
done

# Контроль: «инструментов нет» обязано НАЗЫВАТЬ python3/git, иначе суд ниже пуст.
if ! grep -qi 'python3' <<< "$L_NOTOOLS"; then
    echo "probe_D467: контроль — состояние «инструментов нет» не называет python3/git: $L_NOTOOLS" >&2
    exit 2
fi

# СУД ПЕРВЫЙ: попарная различность. Шесть отказных состояний плюс здоровое.
NAMES="здоровая|нет снимка|снимок не разбирается|ребро без source|nodes не список|спайка пуста|инструментов нет"
VALS=("$L_OK" "$L_NOMAP" "$L_BADJSON" "$L_NOSRC" "$L_NOTLIST" "$L_GHOST" "$L_NOTOOLS")
_bad=0
_n=${#VALS[@]}
_a=0
while [ "$_a" -lt "$_n" ]; do
    _b=$((_a + 1))
    while [ "$_b" -lt "$_n" ]; do
        if [ "${VALS[$_a]}" = "${VALS[$_b]}" ]; then
            _na=$(printf '%s' "$NAMES" | cut -d'|' -f$((_a + 1)))
            _nb=$(printf '%s' "$NAMES" | cut -d'|' -f$((_b + 1)))
            echo "probe_D467: дефект — состояния «${_na}» и «${_nb}» отвечают ОДНИМ значением канала: ${VALS[$_a]}" >&2
            _bad=1
        fi
        _b=$((_b + 1))
    done
    _a=$((_a + 1))
done

# СУД ВТОРОЙ: python3/git называет ТОЛЬКО состояние «инструментов нет».
for _pair in "нет снимка|$L_NOMAP" "снимок не разбирается|$L_BADJSON" "ребро без source|$L_NOSRC" \
             "nodes не список|$L_NOTLIST" "спайка пуста|$L_GHOST"; do
    _name=${_pair%%|*}; _line=${_pair#*|}
    if grep -qi 'python3' <<< "$_line"; then
        echo "probe_D467: дефект — состояние «${_name}» объясняется через python3/git: $_line" >&2
        _bad=1
    fi
done

[ "$_bad" -eq 0 ] || exit 1
exit 0
