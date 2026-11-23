#!/usr/bin/env bash
# СУДИТ: scripts/costly-tests.sh
# probe_D392.sh — прибор дорогих тестов судит ЦЕНУ ПООДИНОЧКЕ по порогу и держит реестр свежим:
# замер без строк >= 1,5 порога и без устаревших оправданий -> 0; УСТАРЕВШЕЕ оправдание (цена упала
# ниже половины порога) -> 1 со словами «РЕЕСТР УСТАРЕЛ»; зона между порогом и полутора порогами —
# предупреждение, кода не меняет (гистерезис).
# Судит ПРИБОР на синтетическом замере; живой замер мерит строка реестра замеров `costly-tests`.
# Коды: 0 — держится; 1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
P="$REPO/scripts/costly-tests.sh"
[ -f "$P" ] || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/state" "$d/tests" || exit 2
HDR='# замер поодиночке начат 2026-01-01 00:00:00, по журналу «# прогон начат 2026-01-01 00:00:00, тестов 9, полнота полный», кандидатов 2, порог 20 с CPU'
printf '# пустой реестр\n' > "$d/empty.tsv"  # непустой файл: awk NR==FNR на пустом первом файле путает входы
run() {  # run <реестр> <файл замера>
    HOME="$d" STATE_DIR="$d/state" SUITE_COST_FILE="$2" SUITE_RUN_FULL_LOG="$d/none.tsv" COSTLY_JUSTIFIED="$1" TESTS_DIR="$d/tests" \
      bash "$P" 2>&1
}
# серая зона (25 с при пороге 20) и дешёвый тест без строки реестра: код 0
printf '%s\n0\t25\t26\ttest_grey.sh\n0\t3\t3\ttest_cheap.sh\n' "$HDR" > "$d/grey.tsv"
OUT=$(run "$d/empty.tsv" "$d/grey.tsv"); RC=$?
[ "$RC" = 0 ] || { echo "серая зона дала код $RC, ожидался 0: $OUT"; exit 1; }
# строка реестра у теста, подешевевшего до 3 с (< 10): оправдание устарело -> 1
printf 'test_cheap.sh\t40 (2026-01-01)\tбыл дорогим\n' > "$d/just.tsv"
OUT=$(run "$d/just.tsv" "$d/grey.tsv"); RC=$?
[ "$RC" = 1 ] || { echo "устаревшее оправдание дало код $RC, ожидался 1"; exit 1; }
case "$OUT" in *"РЕЕСТР УСТАРЕЛ"*test_cheap.sh*) ;; *) echo "устаревшая строка не названа поимённо"; exit 1 ;; esac
# от полутора порогов (31 с) без оправдания: находка -> 1
printf '%s\n0\t31\t32\ttest_dear.sh\n' "$HDR" > "$d/dear.tsv"
run "$d/empty.tsv" "$d/dear.tsv" >/dev/null; RC=$?
[ "$RC" = 1 ] || { echo "31 с при пороге 20 без оправдания дали код $RC, ожидался 1"; exit 1; }
exit 0
