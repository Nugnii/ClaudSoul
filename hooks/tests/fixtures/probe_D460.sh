#!/usr/bin/env bash
# СУДИТ: scripts/costly-tests.sh
# probe_D460.sh — прибор дорогих тестов различает три состояния мира: дорогой БЕЗ оправдания -> 1 со словами
# «ДОРОГИЕ БЕЗ ОПРАВДАНИЯ»; тот же дорогой с строкой реестра (число и причина) -> 0; замера нет -> 2.
# Судит ПРИБОР на синтетическом замере и реестре в песочнице; живой замер (`state/suite-cost.tsv`) и
# живой реестр цен мерит строка реестра замеров `costly-tests`.
# Коды: 0 — держится; 1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
P="$REPO/scripts/costly-tests.sh"
[ -f "$P" ] || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/state" "$d/tests" || exit 2
HDR='# замер поодиночке начат 2026-01-01 00:00:00, по журналу «# прогон начат 2026-01-01 00:00:00, тестов 9, полнота полный», кандидатов 1, порог 20 с CPU'
printf '%s\n0\t40\t41\ttest_fake_costly.sh\n' "$HDR" > "$d/state/cost.tsv"
printf '# пустой реестр\n' > "$d/empty.tsv"  # непустой файл: awk NR==FNR на пустом первом файле путает входы
run() {  # run <реестр> <файл замера>
    HOME="$d" STATE_DIR="$d/state" SUITE_COST_FILE="$2" SUITE_RUN_FULL_LOG="$d/none.tsv" COSTLY_JUSTIFIED="$1" TESTS_DIR="$d/tests" \
      bash "$P" 2>&1
}
OUT=$(run "$d/empty.tsv" "$d/state/cost.tsv"); RC=$?
[ "$RC" = 1 ] || { echo "дорогой без оправдания дал код $RC, ожидался 1"; exit 1; }
case "$OUT" in *"ДОРОГИЕ БЕЗ ОПРАВДАНИЯ"*test_fake_costly.sh*) ;; *) echo "дорогой не назван поимённо"; exit 1 ;; esac
printf 'test_fake_costly.sh\t40 (2026-01-01)\tпредмет — дерево целиком\n' > "$d/just.tsv"
OUT=$(run "$d/just.tsv" "$d/state/cost.tsv"); RC=$?
[ "$RC" = 0 ] || { echo "оправданный дорогой дал код $RC, ожидался 0: $OUT"; exit 1; }
case "$OUT" in *"ДОРОГИЕ БЕЗ ОПРАВДАНИЯ"*) echo "оправданный назван без оправдания"; exit 1 ;; esac
run "$d/just.tsv" "$d/нет-замера.tsv" >/dev/null; RC=$?
[ "$RC" = 2 ] || { echo "без замера код $RC, ожидался 2 (мерить нечем != дорогих нет)"; exit 1; }
exit 0
