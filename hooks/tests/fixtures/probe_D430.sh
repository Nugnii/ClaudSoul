#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py
# probe_D430.sh — «Проверка» пункта D430: `--touch` считает исходящие рёбра файла тем же правилом,
#                 что полная сборка (роль — у dep_role), и снимает исчезнувшие.
# Результат: после `--touch` у файла с `grep x hooks/one.sh` ребро «читает» (как даёт полная
#            сборка), у файла с `bash hooks/one.sh` — «зовёт» (положительный контроль), а у файла,
#            из которого зависимость убрана, ребра нет.
# Проверка результата: bash hooks/tests/fixtures/probe_D430.sh → 0. Сегодня 1 (дефект наблюдён:
#            :784-785 пишет «зовёт» литералом, минуя dep_role, и ничего не снимает), 2 — рамка
#            не собралась.
#
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой)
# и исполняется в своём временном проекте; живой ~/.claude не читается (HOME, LESSONS_DIR).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
[ -f "$MECH/scripts/project-graph.py" ] || { echo "probe_D430: нет $MECH/scripts/project-graph.py" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D430: нет git" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || exit 2   # физический путь: /var → /private/var на macOS, иначе relpath уводит «вне дерева»
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/scripts" "$P/hooks" "$P/.claude-docs" "$P/mcp-server/visualization" "$T/home" "$T/lessons"
cp "$MECH/scripts/project-graph.py" "$P/scripts/" || exit 2
export HOME="$T/home" LESSONS_DIR="$T/lessons" PYTHONDONTWRITEBYTECODE=1 CLAUDSOUL_REPO="$P"
CACHE="$P/mcp-server/visualization/project-graph-data.json"

printf '#!/usr/bin/env bash\necho one\n' > "$P/hooks/one.sh"
printf '#!/usr/bin/env bash\ngrep x hooks/one.sh\n' > "$P/hooks/three.sh"   # чтение; в учёте — зависимость
printf '#!/usr/bin/env bash\necho four\n' > "$P/hooks/four.sh"
printf '#!/usr/bin/env bash\necho five\n' > "$P/hooks/five.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/one.sh\ta\t\t\t\t\n'
  printf 'hooks/three.sh\tb\thooks/one.sh\t\t\t\n'
  printf 'hooks/four.sh\tc\t\t\t\t\n'
  printf 'hooks/five.sh\td\t\t\t\t\n'; } > "$P/.claude-docs/dep-index.tsv"
( cd "$P" && git init -q . && git add -A && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 \
    || { echo "probe_D430: git-песочница не поднялась" >&2; exit 2; }
pg() { ( cd "$P" && python3 scripts/project-graph.py "$@" >/dev/null 2>&1 ); }
edge() {  # edge <src> <dst> → типы рёбер src→dst из кэша, через запятую (пусто — ребра нет)
    python3 - "$CACHE" "$1" "$2" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
ids = {n['key']: n['id'] for n in g['nodes']}
s, d = ids.get(sys.argv[2]), ids.get(sys.argv[3])
print(','.join(sorted(e['type'] for e in g['edges'] if e['source'] == s and e['target'] == d)))
PY
}

pg --refresh || { echo "probe_D430: полная сборка не отработала" >&2; exit 2; }
[ -f "$CACHE" ] || { echo "probe_D430: кэш не записан" >&2; exit 2; }
# Контраст, конец полной сборки: `grep x hooks/one.sh` — ребро «читает».
FULL=$(edge hooks/three.sh hooks/one.sh)
[ "$FULL" = "читает" ] || { echo "probe_D430: полная сборка дала «${FULL:-ничего}» вместо «читает» — контраст не собрался" >&2; exit 2; }

# Положительный контроль: настоящий вызов после --touch даёт «зовёт».
printf '#!/usr/bin/env bash\nbash hooks/one.sh\n' > "$P/hooks/four.sh"
pg --touch hooks/four.sh || { echo "probe_D430: --touch не отработал" >&2; exit 2; }
GOT=$(edge hooks/four.sh hooks/one.sh)
[ "$GOT" = "зовёт" ] || { echo "probe_D430: после --touch у «bash hooks/one.sh» ребро «${GOT:-отсутствует}» вместо «зовёт» — положительный контроль пуст" >&2; exit 1; }

# Конец --touch: та же строка чтения, что у three.sh, — роль обязана совпасть с полной сборкой.
printf '#!/usr/bin/env bash\ngrep x hooks/one.sh\n' > "$P/hooks/five.sh"
pg --touch hooks/five.sh || { echo "probe_D430: --touch не отработал" >&2; exit 2; }
GOT=$(edge hooks/five.sh hooks/one.sh)
[ "$GOT" = "читает" ] || { echo "probe_D430: после --touch у «grep x hooks/one.sh» ребро «${GOT:-отсутствует}», полная сборка даёт «читает»" >&2; exit 1; }

# Зависимость убрана из файла — после --touch ребра быть не должно.
printf '#!/usr/bin/env bash\necho three\n' > "$P/hooks/three.sh"
pg --touch hooks/three.sh || { echo "probe_D430: --touch не отработал" >&2; exit 2; }
GOT=$(edge hooks/three.sh hooks/one.sh)
[ -z "$GOT" ] || { echo "probe_D430: зависимость из hooks/three.sh убрана, а после --touch ребро «${GOT}» → hooks/one.sh осталось" >&2; exit 1; }
exit 0
