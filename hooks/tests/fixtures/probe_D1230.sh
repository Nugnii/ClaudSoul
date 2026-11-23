#!/usr/bin/env bash
set -u
# СУДИТ: scripts/project-graph.py
# probe_D1230 — спайка рёбер исполнения (`project-graph.py --scc --exec`) называется, только если рекурсия достижима.
#   Рамка — песочный git-репозиторий (как у probe_D406), живой граф не читается. Пять пар:
#   · lazy  — питон импортирует соседа ВНУТРИ функции, сосед импортирует его на уровне модуля: кольца импорта нет;
#   · mode  — A зовёт B в режиме `--judge`, B зовёт A только под охраной `if [ "${1:-}" = "--install" ]`: режимы разные;
#   · text  — имя соседа стоит в тексте heredoc для `cat` и в хвостовом комментарии, сосед подключает файл: не вызов;
#   · case  — то же, что mode, но охрана — ветка `--install)` в `case "${1:-}" in` (форма commit-trap.sh);
#   · ring  — оба подключают друг друга (`source`): настоящая спайка (контроль);
#   · same  — A зовёт B в режиме `--go`, B под охраной `--go` зовёт A: режим совпал, спайка настоящая (контроль).
#   · dx, vm — прямой запуск без `bash` и режим в переменной: настоящие (контроли H1 скептика).
#   0 — названы ровно ring, same, dx, vm; 1 — названа ложная пара либо пропущен контроль; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
[ -f "$R/scripts/project-graph.py" ] || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
t="$d/t"; mkdir -p "$t/scripts" "$t/hooks" "$t/.claude-docs" "$t/mcp-server/visualization" "$d/lessons" || exit 2
cp "$R/scripts/project-graph.py" "$t/scripts/" || exit 2
git -C "$t" init -q . && git -C "$t" config user.email t@t && git -C "$t" config user.name t || exit 2
printf 'def run():\n    import lazyb\n    return lazyb.f()\n' > "$t/scripts/lazya.py"
printf 'import lazya\n\n\ndef f():\n    return 1\n' > "$t/scripts/lazyb.py"
printf '#!/usr/bin/env bash\nbash hooks/modeb.sh --judge "$1"\n' > "$t/hooks/modea.sh"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--install" ]; then\n    exec bash hooks/modea.sh "$@"\nfi\necho судит\n' > "$t/hooks/modeb.sh"
printf '#!/usr/bin/env bash\nx=1   # hooks/textb.sh упомянут в хвосте\ncat <<'"'"'TXT'"'"'\nСпособ добычи: hooks/textb.sh\nTXT\n' > "$t/hooks/texta.sh"
printf '#!/usr/bin/env bash\nsource hooks/texta.sh\n' > "$t/hooks/textb.sh"
printf '#!/usr/bin/env bash\nbash hooks/caseb.sh --judge "$1"\n' > "$t/hooks/casea.sh"
printf '#!/usr/bin/env bash\ncase "${1:-}" in\n--install)\n    exec bash hooks/casea.sh "$@" ;;\n--judge)\n    echo судит ;;\nesac\n' > "$t/hooks/caseb.sh"
# Настоящие рекурсии, которые разбор режимов обязан оставить (скептик opus по 86b1d5bb, H1, M1): прямой запуск без
# `bash` (место не узнано — режим любой) и режим, переданный переменной.
printf '#!/usr/bin/env bash\nhooks/dxb.sh --install\n' > "$t/hooks/dxa.sh"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--install" ]; then\n    bash hooks/dxa.sh\nfi\n' > "$t/hooks/dxb.sh"
printf '#!/usr/bin/env bash\nM=--install\nbash hooks/vmb.sh "$M"\n' > "$t/hooks/vma.sh"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--install" ]; then\n    bash hooks/vma.sh\nfi\n' > "$t/hooks/vmb.sh"
printf '#!/usr/bin/env bash\nsource hooks/ringb.sh\n' > "$t/hooks/ringa.sh"
printf '#!/usr/bin/env bash\nsource hooks/ringa.sh\n' > "$t/hooks/ringb.sh"
printf '#!/usr/bin/env bash\nbash hooks/sameb.sh --go\n' > "$t/hooks/samea.sh"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--go" ]; then\n    bash hooks/samea.sh\nfi\n' > "$t/hooks/sameb.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  for p in lazy:scripts:py mode:hooks:sh text:hooks:sh case:hooks:sh ring:hooks:sh same:hooks:sh dx:hooks:sh vm:hooks:sh; do
      n=${p%%:*}; r=${p#*:}; dir=${r%%:*}; e=${r#*:}
      printf '%s/%sa.%s\t1\t%s/%sb.%s\t\t\t\n' "$dir" "$n" "$e" "$dir" "$n" "$e"
      printf '%s/%sb.%s\t1\t%s/%sa.%s\t\t\t\n' "$dir" "$n" "$e" "$dir" "$n" "$e"
  done; } > "$t/.claude-docs/dep-index.tsv"
git -C "$t" add -A >/dev/null 2>&1 && git -C "$t" commit -qm i >/dev/null 2>&1 || exit 2
out=$(cd "$t" && LESSONS_DIR="$d/lessons" CLAUDSOUL_REPO="$PWD" python3 scripts/project-graph.py --scc --exec 2>&1)
grep -q 'спаек (кусков, где всё достижимо из всего)' <<< "$out" || { echo "рамка: прибор не дал строки спаек: $out"; exit 2; }
bad=0
for n in lazy mode text case; do grep -q "${n}a\." <<< "$out" && { echo "ложная спайка исполнения: пара ${n}"; bad=1; }; done
for n in ring same dx vm; do grep -q "${n}a\." <<< "$out" || { echo "пропущена настоящая спайка: пара ${n}"; bad=1; }; done
exit "$bad"
