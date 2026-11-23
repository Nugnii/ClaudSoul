#!/usr/bin/env bash
# СУДИТ: scripts/dep-index.py scripts/project-graph.py
# probe_D429.sh — «Проверка» пункта D429: у универсума файлов ОДИН владелец — новый файл, который
#                 видит учёт (dep-index.py: tracked + untracked), виден и карте (project-graph.py).
# Результат: untracked pkg/newfile.py, названный учётом расхождением в `--check`, стоит узлом в
#            карте и несёт свои исходящие рёбра, как любой tracked файл (положительный контроль:
#            tracked pkg/caller.py с тем же вызовом даёт узел и ребро).
# Проверка результата: bash hooks/tests/fixtures/probe_D429.sh → 0. Сегодня 1 (дефект наблюдён:
#            project-graph.py:106-108 берёт только `git ls-files`), 2 — рамка не собралась.
#
# Оба механизма берутся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой) и
# исполняются в своём временном проекте; живой ~/.claude не читается (HOME, LESSONS_DIR).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
for s in project-graph.py dep-index.py; do
    [ -f "$MECH/scripts/$s" ] || { echo "probe_D429: нет $MECH/scripts/$s" >&2; exit 2; }
done
command -v git >/dev/null 2>&1 || { echo "probe_D429: нет git" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || exit 2   # физический путь: /var → /private/var на macOS, иначе relpath уводит «вне дерева»
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/scripts" "$P/pkg" "$P/.claude-docs" "$P/mcp-server/visualization" "$T/home" "$T/lessons"
cp "$MECH/scripts/project-graph.py" "$MECH/scripts/dep-index.py" "$P/scripts/" || exit 2
export HOME="$T/home" LESSONS_DIR="$T/lessons" PYTHONDONTWRITEBYTECODE=1 CLAUDSOUL_REPO="$P"

printf 'def compute_action():\n    return "act"\n' > "$P/pkg/worker.py"
printf 'from pkg.worker import compute_action\ncompute_action()\n' > "$P/pkg/caller.py"
( cd "$P" && git init -q . && git add -A && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 \
    || { echo "probe_D429: git-песочница не поднялась" >&2; exit 2; }
( cd "$P" && python3 scripts/dep-index.py --all >/dev/null 2>&1 ) \
    || { echo "probe_D429: учёт не собрался" >&2; exit 2; }
# Новый файл — untracked: не добавлен в git, но и не игнорируется.
printf 'from pkg.worker import compute_action\ncompute_action()\n' > "$P/pkg/newfile.py"

# Контраст, конец учёта: `--check` пересчитывает универсум и называет untracked-файл расхождением.
OUT=$(cd "$P" && python3 scripts/dep-index.py --check 2>/dev/null)
grep -qF 'pkg/newfile.py' <<< "$OUT" \
    || { echo "probe_D429: учёт не увидел untracked pkg/newfile.py — контраста нет (вывод: ${OUT:-пусто})" >&2; exit 2; }

pg() { ( cd "$P" && python3 scripts/project-graph.py "$@" 2>/dev/null ); }
OUT=$(pg --refresh --node pkg/caller.py); RC=$?
[ "$RC" = 0 ] || { echo "probe_D429: механизм не отработал (код $RC)" >&2; exit 2; }
grep -qF 'использует compute_action' <<< "$OUT" \
    || { echo "probe_D429: tracked pkg/caller.py без ребра «использует compute_action» — положительный контроль пуст" >&2; exit 1; }

# Конец карты: тот же файл, тот же вызов — узел и ребро обязаны быть.
OUT=$(pg --node pkg/newfile.py)
if grep -qF 'в карте нет' <<< "$OUT"; then
    echo "probe_D429: учёт видит pkg/newfile.py (назвал его в --check), карта — нет: «${OUT}»" >&2; exit 1
fi
grep -qF 'использует compute_action' <<< "$OUT" \
    || { echo "probe_D429: узел pkg/newfile.py есть, а ребра «использует compute_action» нет — файл вне универсума обхода" >&2; exit 1; }
exit 0
