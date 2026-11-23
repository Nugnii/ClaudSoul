#!/usr/bin/env bash
# test_root_map_local_to_project.sh — карта корней берётся у ПРОЕКТА СЕССИИ, а не у ClaudSoul.
# en: the root map is read from the session's project, not always from ClaudSoul.
#
# Результат: в чужом проекте прибор читает его ROOTS.md; в ClaudSoul — свою; отсутствие карты
#            у проекта отдаёт карту ClaudSoul, а не пустоту.
# Проверка результата: bash hooks/tests/test_root_map_local_to_project.sh даёт 0
#
# Повод (11 сентября 2026, D395). Карта объявлена ЛОКАЛЬНОЙ для проекта — CLAUDE.md §5:
# «общее между проектами ходит паттернами базы знаний, а не через этот файл», — но
# scripts/root-map.py:34-35 читал её всегда у ClaudSoul. В самом ClaudSoul оба пути
# совпадают, и дефект был невидим. Поймали первым запуском в чужом проекте: в ProjectA_NEW
# развернули пустую карту из шаблона, а прибор напечатал ШЕСТЬ корней ClaudSoul и выдал их
# за корни проекта. Дробь корня — основание решений о починке, и она пришла бы от другого
# дерева.
#
# Ноги держат обе стороны: без T2 тест зеленел бы у прибора, который всегда читает текущий
# каталог и потерял бы поведение внутри ClaudSoul; без T1 — у прежнего, читающего только
# ClaudSoul.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/root-map.py"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3 — пропуск"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- T1: чужой проект со своей картой — читается ЕГО карта ---
P="$TMP/foreign"; mkdir -p "$P"
( cd "$P" && git init -q 2>/dev/null )   # корень репозитория, выше него подниматься нельзя
printf '# ROOTS\n\n## R1 — единственный корень чужого проекта\n**Устройство.** проверочный\n' > "$P/ROOTS.md"
N1=$( (cd "$P" && python3 "$TOOL" --count 2>/dev/null) )
[ "${N1:-0}" = "1" ] && ok \
    || bad T1 "в чужом проекте прочитано корней «${N1}», а в его карте один — взята чужая карта"

# --- T2: внутри ClaudSoul поведение прежнее ---
N2=$( (cd "$REPO" && python3 "$TOOL" --count 2>/dev/null) )
EXPECT=$(grep -c '^## R' "$REPO/ROOTS.md" 2>/dev/null || true)
[ "${N2:-0}" = "${EXPECT:-0}" ] && ok \
    || bad T2 "в ClaudSoul прочитано «${N2}» при $EXPECT корнях в его карте"

# --- T3: у проекта карты НЕТ — отдаётся карта ClaudSoul, а не пустота ---
# Отсутствие своей карты не должно превращаться в «корней ноль»: это разные состояния.
P2="$TMP/nomap"; mkdir -p "$P2"
( cd "$P2" && git init -q 2>/dev/null )
N3=$( (cd "$P2" && CLAUDSOUL_REPO="$REPO" python3 "$TOOL" --count 2>/dev/null) )
[ "${N3:-0}" = "${EXPECT:-0}" ] && ok \
    || bad T3 "без своей карты прочитано «${N3}» вместо карты ClaudSoul ($EXPECT)"

# --- T4: явный ROOTS_MAP сильнее всего остального ---
printf '# ROOTS\n\n## R7 — явная карта\n**Устройство.** проверочный\n## R8 — вторая\n**Устройство.** проверочный\n' > "$TMP/explicit.md"
N4=$( (cd "$REPO" && ROOTS_MAP="$TMP/explicit.md" python3 "$TOOL" --count 2>/dev/null) )
[ "${N4:-0}" = "2" ] && ok || bad T4 "явный ROOTS_MAP не перекрыл карту проекта: «${N4}» вместо 2"

echo "root map local to project: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
