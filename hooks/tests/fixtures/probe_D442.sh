#!/usr/bin/env bash
# probe_D442.sh — «Проверка» пункта D442: `scripts/backlog-recheck.sh` (блок D411) читает
# `mcp-server/visualization/project-graph-data.json` МИМО `project-graph.py` (D427) и на
# карте с висячим циклическим ребром путает «карта НЕ ЦЕЛА» с «нет python3 либо git» —
# ОДНО значение канала `_SPIRAL="?"` на ДВА разных состояния мира.
# Результат: карта с висячим циклическим ребром (1→999→1, python3 РАБОТАЕТ) даёт блоку
#            D411 сообщение, которое а) не поминает python3/git и б) ТЕКСТУАЛЬНО отличается
#            от сообщения при истинно НЕДОСТИЖИМОМ python3 — различаются РАЗБОРОМ, а не
#            словом внутри одной и той же ветки. Целая карта проходит без обеих веток.
# Проверка результата: bash hooks/tests/fixtures/probe_D442.sh → 0. Сегодня 1 (дефект
#            наблюдён: :184-189,221,252-253 читают кэш напрямую, KeyError на :221 и «нет
#            python3» падают в ОДНО значение "?" канала), 2 — рамка не собралась.
#
# Третье состояние (python3 недостижим, карта цела) заведено 17 сентября 2026 разбором
# скептика: патч, который лишь ПЕРЕПИСЫВАЕТ текст ветки "?" без разбора (не заводя третье
# значение канала), красил СТАРУЮ пробу зелёным — сообщение битой карты случайно перестаёт
# буквально содержать фразу «нет python3» и совпадает по форме с «НЕ ЦЕЛА», хотя это ВСЁ
# ЕЩЁ одна и та же ветка на оба состояния. Проверяется ИСХОД (сообщения при «карта бита» и
# «python3 недостижим» обязаны различаться, и только второе называет python3/git), а не
# наличие слова в одном выводе.
#
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с
# починкой backlog-recheck.sh). Исполняется в СВОЁМ временном проекте: скрипт сам читает
# CLAUDSOUL_REPO как корень проверяемого проекта (BACKLOG.md, knowledge/META.md, кэш
# карты), поэтому копия ставится внутрь песочницы, а переменная переназначается на неё.
# Живой ~/.claude не читается: HOME и LESSONS_DIR указывают в песочницу.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
[ -f "$MECH/scripts/backlog-recheck.sh" ] || { echo "probe_D442: нет $MECH/scripts/backlog-recheck.sh" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D442: нет python3 в оболочке хоста — рамка не собралась" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D442: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
P="$T/proj"
mkdir -p "$P/scripts" "$P/knowledge" "$P/mcp-server/visualization" "$P/hooks" "$T/home" "$T/lessons" "$T/shim"
cp "$MECH/scripts/backlog-recheck.sh" "$P/scripts/" || exit 2
printf '# BACKLOG\n\n- ☑ **D1** тест\n' > "$P/BACKLOG.md"
printf 'origin: case\npreceded_artifact: none\n' > "$P/knowledge/META.md"
: > "$P/hooks/a.sh"
CACHE="$P/mcp-server/visualization/project-graph-data.json"
export HOME="$T/home" LESSONS_DIR="$T/lessons" STATE_DIR="$T/home/.claude/hooks/state" CLAUDSOUL_REPO="$P"
run() { bash "$P/scripts/backlog-recheck.sh" 2>&1; }
d411() { grep 'D411' <<< "$1" | head -1; }   # строка блока D411, без счёта прочих пунктов

INTACT='{"nodes":[{"id":1,"key":"hooks/a.sh","name":"a.sh","type":"hook"}],"edges":[{"source":1,"target":1,"type":"зовёт","strength":1}],"domains":[],"shared_names":{}}'
DEFECT='{"nodes":[{"id":1,"key":"hooks/a.sh","name":"a.sh","type":"hook"}],"edges":[{"source":1,"target":999,"type":"зовёт","strength":1},{"source":999,"target":1,"type":"зовёт","strength":1}],"domains":[],"shared_names":{}}'

# Положительный контроль: ЦЕЛАЯ карта (узел ссылается на себя, оба конца ребра существуют)
# не роняет блок D411 и не несёт ложного диагноза ни про целость, ни про инструменты.
printf '%s' "$INTACT" > "$CACHE"
LINE_A=$(d411 "$(run)")
[ -n "$LINE_A" ] || { echo "probe_D442: блок D411 не отработал на целой карте — рамка не собралась" >&2; exit 2; }
if grep -qi 'python3' <<< "$LINE_A"; then
    echo "probe_D442: контроль — на ЦЕЛОЙ карте D411 уже говорит про python3/git: $LINE_A" >&2
    exit 2
fi

# Судимое состояние: узел 1 (реальный) образует цикл с узлом 999, которого в `nodes` нет —
# то же нарушение ссылочной целости, что и в probe_D427.sh; python3 при этом РАБОТАЕТ.
printf '%s' "$DEFECT" > "$CACHE"
LINE_B=$(d411 "$(run)")
[ -n "$LINE_B" ] || { echo "probe_D442: блок D411 не отработал на дефектной карте — рамка не собралась" >&2; exit 2; }

# Контроль третьего состояния: инструментов ИСТИННО нет, карта — ЦЕЛАЯ. Проверяет, что
# «нет инструментов» как значение канала действительно НАЗЫВАЕТ python3/git, а не
# растворилось в переписанном тексте вместе с веткой «карта не цела».
# ИСТИННОЕ ОТСУТСТВИЕ, А НЕ ШИМ `exit 1` (правка 19 сентября 2026 по находке скептика).
# Шим — это «интерпретатор ЕСТЬ и сломан», и механизм теперь различает его отдельным
# значением канала; состояние «инструментов нет» ставится теневым PATH, где есть всё,
# кроме python3. Прежняя редакция пробы подменяла одно другим и судила не то состояние.
mkdir -p "$T/nopy"
for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
        _b=$(basename "$_f")
        case "$_b" in python3*|python) continue ;; esac
        [ -e "$T/nopy/$_b" ] || ln -s "$_f" "$T/nopy/$_b" 2>/dev/null
    done
done
[ -x "$T/nopy/git" ] || { echo "probe_D442: теневой PATH не собрался (нет git) — рамка не собралась" >&2; exit 2; }
if PATH="$T/nopy" command -v python3 >/dev/null 2>&1; then
    echo "probe_D442: теневой PATH всё ещё видит python3 — рамка не собралась" >&2; exit 2
fi
printf '%s' "$INTACT" > "$CACHE"
LINE_C=$(d411 "$(PATH="$T/nopy" run)")
[ -n "$LINE_C" ] || { echo "probe_D442: блок D411 не отработал при отсутствующих инструментах — рамка не собралась" >&2; exit 2; }
if ! grep -qi 'python3' <<< "$LINE_C"; then
    echo "probe_D442: контроль — состояние «инструментов нет» не называет python3/git: $LINE_C" >&2
    exit 2
fi

# Суд: сообщение битой карты (B) и сообщение недостижимого python3 (C) обязаны различаться,
# и B не должно ссылаться на python3/git — иначе оба состояния мира всё ещё отвечают одним
# значением канала, только под другим словом.
if [ "$LINE_B" = "$LINE_C" ]; then
    echo "probe_D442: дефект — сообщение битой карты совпадает с сообщением «инструментов нет»: $LINE_B" >&2
    exit 1
fi
if grep -qi 'python3' <<< "$LINE_B"; then
    echo "probe_D442: дефект — битая карта (python3 отработал) всё равно объясняется через python3/git: $LINE_B" >&2
    exit 1
fi
if grep -qiE 'НЕ ЦЕЛ|целост' <<< "$LINE_B"; then
    exit 0
fi
echo "probe_D442: неожиданный ответ D411 на дефектной карте (ни python3, ни распознанная целость): $LINE_B" >&2
exit 2
