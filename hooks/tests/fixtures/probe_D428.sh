#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py
# probe_D428.sh — «Проверка» пункта D428: ребро «использует <функция>» не рождается из СТРОКОВОГО
#                 литерала; настоящий вызов ребро даёт (положительный контроль в той же пробе).
# Результат: `print("compute_action(")` в .py и `echo "compute_action("` в .sh ребра к файлу
#            определения не дают; `compute_action()` в .py и `"$(compute_action)"` в .sh — дают.
# Проверка результата: bash hooks/tests/fixtures/probe_D428.sh → 0. Сегодня 1 (дефект наблюдён:
#            :321-322 совпадает внутри строки, code_lines снимает лишь комментарии и докстринги),
#            2 — рамка не собралась.
#
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой)
# и исполняется в своём временном проекте; живой ~/.claude не читается (HOME, LESSONS_DIR).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
[ -f "$MECH/scripts/project-graph.py" ] || { echo "probe_D428: нет $MECH/scripts/project-graph.py" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D428: нет git" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || exit 2   # физический путь: /var → /private/var на macOS, иначе relpath уводит «вне дерева»
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/scripts" "$P/pkg" "$P/hooks" "$P/.claude-docs" "$P/mcp-server/visualization" "$T/home" "$T/lessons"
cp "$MECH/scripts/project-graph.py" "$P/scripts/" || exit 2
export HOME="$T/home" LESSONS_DIR="$T/lessons" PYTHONDONTWRITEBYTECODE=1 CLAUDSOUL_REPO="$P"

printf 'def compute_action():\n    return "act"\n' > "$P/pkg/worker.py"
printf 'print("compute_action(")\n' > "$P/pkg/printer.py"                      # литерал, не вызов
printf 'from pkg.worker import compute_action\ncompute_action()\n' > "$P/pkg/caller.py"   # вызов
printf '#!/usr/bin/env bash\necho "compute_action("\n' > "$P/hooks/say.sh"      # литерал, не вызов
printf '#!/usr/bin/env bash\nx="$(compute_action)"\necho "$x"\n' > "$P/hooks/call.sh"  # вызов в кавычках
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'pkg/worker.py\ta\t\t\t\tcompute_action\n'
  printf 'pkg/printer.py\tb\t\t\t\t\n'
  printf 'pkg/caller.py\tc\t\t\t\t\n'
  printf 'hooks/say.sh\td\t\t\t\t\n'
  printf 'hooks/call.sh\te\t\t\t\t\n'; } > "$P/.claude-docs/dep-index.tsv"
( cd "$P" && git init -q . && git add -A && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 \
    || { echo "probe_D428: git-песочница не поднялась" >&2; exit 2; }
pg() { ( cd "$P" && python3 scripts/project-graph.py "$@" 2>/dev/null ); }

OUT=$(pg --node pkg/caller.py); RC=$?          # первый вызов собирает карту и пишет кэш
[ "$RC" = 0 ] || { echo "probe_D428: механизм не отработал (код $RC)" >&2; exit 2; }
grep -qF 'использует compute_action' <<< "$OUT" \
    || { echo "probe_D428: настоящий вызов compute_action() в pkg/caller.py ребра не дал — положительный контроль пуст" >&2; exit 1; }
grep -qF 'использует compute_action' <<< "$(pg --node hooks/call.sh)" \
    || { echo "probe_D428: вызов \"\$(compute_action)\" в hooks/call.sh ребра не дал — положительный контроль пуст" >&2; exit 1; }
if grep -qF 'использует compute_action' <<< "$(pg --node pkg/printer.py)"; then
    echo "probe_D428: строковый литерал print(\"compute_action(\") в pkg/printer.py дал ребро «использует compute_action» → pkg/worker.py" >&2; exit 1
fi
if grep -qF 'использует compute_action' <<< "$(pg --node hooks/say.sh)"; then
    echo "probe_D428: строковый литерал echo \"compute_action(\" в hooks/say.sh дал ребро «использует compute_action» → pkg/worker.py" >&2; exit 1
fi
exit 0
