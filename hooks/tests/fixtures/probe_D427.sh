#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py
# probe_D427.sh — «Проверка» пункта D427: `project-graph.py --check` краснеет на ВИСЯЧЕМ ребре.
# Результат: карта, где ребро ведёт в несуществующий узел, не проходит --check; целая карта проходит.
# Проверка результата: bash hooks/tests/fixtures/probe_D427.sh → 0. Сегодня 1 (дефект наблюдён:
#            :842-843 судит только непустоту), 2 — рамка не собралась (нет механизма, нет git).
#
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой),
# а исполняется в СВОЁМ временном проекте: project-graph.py читает CLAUDSOUL_REPO как корень
# проекта, поэтому скрипт копируется, а переменная переназначается на песочницу.
# Живой ~/.claude не читается: HOME и LESSONS_DIR указывают в песочницу.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
[ -f "$MECH/scripts/project-graph.py" ] || { echo "probe_D427: нет $MECH/scripts/project-graph.py" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D427: нет git" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || exit 2   # физический путь: /var → /private/var на macOS, иначе relpath уводит «вне дерева»
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/scripts" "$P/hooks" "$P/.claude-docs" "$P/mcp-server/visualization" "$T/home" "$T/lessons"
cp "$MECH/scripts/project-graph.py" "$P/scripts/" || exit 2
export HOME="$T/home" LESSONS_DIR="$T/lessons" PYTHONDONTWRITEBYTECODE=1 CLAUDSOUL_REPO="$P"

printf '#!/usr/bin/env bash\necho one\n' > "$P/hooks/one.sh"
printf '#!/usr/bin/env bash\nbash hooks/one.sh\n' > "$P/hooks/two.sh"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/one.sh\ta\t\t\t\t\nhooks/two.sh\tb\thooks/one.sh\t\t\t\n' \
    > "$P/.claude-docs/dep-index.tsv"
( cd "$P" && git init -q . && git add -A && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 \
    || { echo "probe_D427: git-песочница не поднялась" >&2; exit 2; }
CACHE="$P/mcp-server/visualization/project-graph-data.json"
pg() { ( cd "$P" && python3 scripts/project-graph.py "$@" ); }

# Положительный контроль: ЦЕЛАЯ карта (оба конца каждого ребра существуют) проходит --check.
printf '{"nodes":[{"id":1,"name":"one.sh","type":"hook","key":"hooks/one.sh"},{"id":2,"name":"two.sh","type":"hook","key":"hooks/two.sh"}],"edges":[{"source":2,"target":1,"type":"зовёт","strength":3}],"domains":[],"shared_names":{}}' > "$CACHE"
touch "$CACHE"   # свежее учёта — иначе load() пересоберёт карту и судить будет не кэш
OUT=$(pg --check 2>/dev/null); RC=$?
grep -q 'узлов: 2 ' <<< "$OUT" || { echo "probe_D427: кэш не прочитан (вывод: ${OUT:-пусто}) — рамка не собралась" >&2; exit 2; }
[ "$RC" = 0 ] || { echo "probe_D427: целая карта не прошла --check (код $RC) — положительный контроль пуст" >&2; exit 1; }

# Дефект: узел один, ребро 1→999 — узла 999 в карте нет.
printf '{"nodes":[{"id":1,"name":"one.sh","type":"hook","key":"hooks/one.sh"}],"edges":[{"source":1,"target":999,"type":"зовёт","strength":3}],"domains":[],"shared_names":{}}' > "$CACHE"
touch "$CACHE"
OUT=$(pg --check 2>&1); RC=$?
grep -q 'узлов: 1 ' <<< "$OUT" || { echo "probe_D427: кэш с висячим ребром не прочитан (вывод: ${OUT:-пусто}) — рамка не собралась" >&2; exit 2; }
case "$RC" in
    0) echo "probe_D427: --check зелен (код 0) на карте с ребром 1→999, узла 999 нет" >&2; exit 1 ;;
    # Код 1 засчитывается, только если нарушение НАЗВАНО (конец 999 в выводе): Traceback после печати
    # чисел снимка тоже давал бы единицу, и проба зеленела бы от падения, а не от проверки (находка
    # скептика 17 сентября 2026; от формы прежде держала нога T40 теста, а не проба).
    1) grep -q '999' <<< "$OUT" && exit 0
       echo "probe_D427: --check ответил 1, но нарушение не названо (вывод: ${OUT:-пусто})" >&2; exit 1 ;;
    *) echo "probe_D427: --check ответил кодом $RC — это не вердикт о карте" >&2; exit 2 ;;
esac
