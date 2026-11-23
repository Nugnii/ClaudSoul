#!/usr/bin/env bash
set -u
# СУДИТ: hooks/tests/run_all.sh
# probe_D1281 — выборочный прогон берёт тесты механизмов, зависящих от изменённого через библиотеку-посредника:
#   (п) правка `hooks/lib/write_targets.py` выбирает `test_skill_name_ascii_guard.sh` (страж → command-scope-lib.sh →
#       write_targets.py; откат D1277 прошёл набор зелёным именно так);
#   (к) правка `hooks/command-scope-lib.sh` его выбирает (положительный контроль: тест в учёте есть, выбор жив).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/tests/run_all.sh" ] && [ -f "$R/.claude-docs/dep-index.tsv" ] || exit 2
sel() { (cd "$R" && CHANGED_FILES="$1" bash hooks/tests/run_all.sh --list 2>/dev/null) | grep -cx 'test_skill_name_ascii_guard.sh'; }
k=$(sel hooks/command-scope-lib.sh)
[ "${k:-0}" -ge 1 ] 2>/dev/null || { echo "рамка: и правка command-scope-lib.sh тест стража не выбирает (k=${k:-?})" >&2; exit 2; }
p=$(sel hooks/lib/write_targets.py)
[ "${p:-0}" -ge 1 ] 2>/dev/null && { echo "правка разбора выбирает тест стража, зависящего через библиотеку"; exit 0; }
echo "правка hooks/lib/write_targets.py не выбирает test_skill_name_ascii_guard.sh (второй шаг зависимости)"
exit 1
