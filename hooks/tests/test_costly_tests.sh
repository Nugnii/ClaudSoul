#!/usr/bin/env bash
# test_costly_tests.sh — свидетель прибора дорогих тестов (D392): цена судится по замеру поодиночке,
#                        оправдание — строкой реестра с числом и причиной, устаревшее оправдание — находка.
# Результат: 0 на замере, где дорогой тест оправдан; 1 — дорогой без строки, строка без причины, строка о
#            подешевевшем или отсутствующем тесте; 2 — замера нет; порог — рычаг; предупреждения о старом
#            замере и немерянных кандидатах не меняют код; --measure пишет замер поодиночке с настоящим CPU.
# Проверка результата: bash hooks/tests/test_costly_tests.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TOOL="$ROOT/scripts/costly-tests.sh"
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система
mkdir -p "$TMP/tests"
HDR='# замер поодиночке начат 2026-09-13 00:00:00, по журналу «# прогон начат 2026-09-13 00:00:00, тестов 3, полнота полный», кандидатов 1, порог 20 с CPU'
cost() { local f="$1"; shift; { printf '%s\n' "$HDR"; printf '%s\n' "$@"; } > "$f"; }
run() { SUITE_COST_FILE="$1" COSTLY_JUSTIFIED="$2" SUITE_RUN_FULL_LOG="${4:-$TMP/no-log.tsv}" TESTS_DIR="$TMP/tests" COSTLY_CPU_MAX="${3:-20}" bash "$TOOL" 2>&1; }
C="$TMP/cost.tsv"; R="$TMP/reg.tsv"; L="$TMP/log.tsv"

# T1: дорогой оправдан → 0 и назван с причиной
cost "$C" $'0\t35\t40\ttest_a.sh' $'0\t3\t5\ttest_b.sh'
printf '# реестр\ntest_a.sh\t35 с CPU (13 сентября 2026)\tобходит всё дерево — предмет\n' > "$R"
OUT=$(run "$C" "$R"); RC=$?
[ "$RC" = 0 ] && grep -q "35 с CPU  test_a.sh — обходит всё дерево" <<< "$OUT" && ok || bad "T1" "оправданный дорогой: rc $RC: $OUT"
# T2: дорогой без строки → 1, назван с CPU, стенными и кодом
printf '# реестр\n' > "$R"
OUT=$(run "$C" "$R"); RC=$?
[ "$RC" = 1 ] && grep -q "35 с CPU  test_a.sh  (стенных 40 с, код 0)" <<< "$OUT" && ok || bad "T2" "дорогой без оправдания: rc $RC: $OUT"
# T3: судится CPU, не стенные: 70 стенных при 8 CPU — не дорогой
cost "$C" $'0\t8\t70\ttest_a.sh' $'0\t3\t5\ttest_b.sh'
RC=$(run "$C" "$R" >/dev/null; echo $?); [ "$RC" = 0 ] && ok || bad "T3" "стенные 70 с при CPU 8 с сочтены дорогими (rc $RC)"
# T4: оправдание устарело — тест подешевел → 1
printf '# реестр\ntest_a.sh\t35 с CPU\tпричина\n' > "$R"
OUT=$(run "$C" "$R"); RC=$?
[ "$RC" = 1 ] && grep -q "test_a.sh: цена упала до 8 с CPU" <<< "$OUT" && ok || bad "T4" "устаревшее оправдание не названо: rc $RC: $OUT"
# T4b: гистерезис — 15 с CPU при строке реестра и пороге 20 не устарело (шум замера до ±50%)
cost "$C" $'0\t15\t20\ttest_a.sh' $'0\t3\t5\ttest_b.sh'
RC=$(run "$C" "$R" >/dev/null; echo $?); [ "$RC" = 0 ] && ok || bad "T4b" "оправдание при 15 с (выше половины порога) объявлено устаревшим (rc $RC)"
cost "$C" $'0\t8\t70\ttest_a.sh' $'0\t3\t5\ttest_b.sh'
# T5: строка о тесте, которого в замере нет → 1
printf '# реестр\ntest_zz.sh\t40 с CPU\tпричина\n' > "$R"
OUT=$(run "$C" "$R"); RC=$?
[ "$RC" = 1 ] && grep -q "test_zz.sh: теста в замере поодиночке нет" <<< "$OUT" && ok || bad "T5" "строка об отсутствующем тесте не названа: rc $RC: $OUT"
# T6: строка без причины → 1
cost "$C" $'0\t35\t40\ttest_a.sh'
printf '# реестр\ntest_a.sh\t35 с CPU\n' > "$R"
OUT=$(run "$C" "$R"); RC=$?
[ "$RC" = 1 ] && grep -q "test_a.sh: строка без числа или причины" <<< "$OUT" && ok || bad "T6" "строка без причины принята: rc $RC: $OUT"
# T7: замера нет → 2
RC=$(run "$TMP/none.tsv" "$R" >/dev/null; echo $?); [ "$RC" = 2 ] && ok || bad "T7" "без замера дал $RC, ждали 2"
# T8: порог — рычаг: при 40 тест с 35 с CPU не дорогой
printf '# реестр\n' > "$R"
RC=$(run "$C" "$R" 40 >/dev/null; echo $?); [ "$RC" = 0 ] && ok || bad "T8" "порог 40 не применён (rc $RC)"
# T9: журнал полнее/новее замера → предупреждение, код прежний (0 при оправданном)
printf '# реестр\ntest_a.sh\t35 с CPU\tпричина\n' > "$R"
printf '# прогон начат 2026-09-13 09:00:00, тестов 3, полнота полный\n0\t40\ttest_a.sh\t50\n0\t5\ttest_b.sh\t3\n0\t9\ttest_c.sh\t25\n' > "$L"
OUT=$(run "$C" "$R" 20 "$L"); RC=$?
[ "$RC" = 0 ] && grep -q "замер старше журнала" <<< "$OUT" && grep -q "test_c.sh (в журнале 25 с CPU)" <<< "$OUT" && ok || bad "T9" "предупреждения о старом замере и немерянном кандидате: rc $RC: $OUT"
# T10: --measure: настоящий CPU поодиночке — тяжёлый ≥ 1 с, лёгкий 0; кандидаты берутся из журнала
printf '#!/usr/bin/env bash\npython3 -c "\nimport time; t=time.process_time()\nwhile time.process_time()-t < 1.2: pass"\nexit 0\n' > "$TMP/tests/test_cpu.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/tests/test_cheap.sh"
printf '# прогон начат 2026-09-13 09:00:00, тестов 2, полнота полный\n0\t3\ttest_cpu.sh\t25\n0\t1\ttest_cheap.sh\t25\n' > "$L"
printf '# реестр\n' > "$R"
OUT=$(SUITE_COST_FILE="$TMP/measured.tsv" COSTLY_JUSTIFIED="$R" SUITE_RUN_FULL_LOG="$L" TESTS_DIR="$TMP/tests" TIMEOUT_LIB="$ROOT/hooks/timeout-lib.sh" COSTLY_CPU_MAX=1 bash "$TOOL" --measure 2>&1); RC=$?
CPU_HEAVY=$(awk -F'\t' '$4 == "test_cpu.sh" { print $2 }' "$TMP/measured.tsv" 2>/dev/null)
CPU_CHEAP=$(awk -F'\t' '$4 == "test_cheap.sh" { print $2 }' "$TMP/measured.tsv" 2>/dev/null)
[ "${CPU_HEAVY:-0}" -ge 1 ] && [ "${CPU_CHEAP:-x}" = 0 ] && [ "$RC" = 1 ] && grep -q "test_cpu.sh" <<< "$OUT" && ok \
    || bad "T10" "--measure: тяжёлый $CPU_HEAVY с (ждали ≥ 1), лёгкий $CPU_CHEAP (ждали 0), rc $RC (ждали 1): $OUT"
# T11: мутант без сравнения с порогом не отличает дорогого от дешёвого (нога T2 различает)
cost "$C" $'0\t35\t40\ttest_a.sh'
M="$TMP/mutant.sh"; sed 's/\$2+0 >= m \&\& !(\$4 in j)/0/' "$TOOL" > "$M"
RC=$(SUITE_COST_FILE="$C" COSTLY_JUSTIFIED="$R" SUITE_RUN_FULL_LOG="$TMP/no-log.tsv" TESTS_DIR="$TMP/tests" bash "$M" >/dev/null 2>&1; echo $?)
[ "$RC" = 0 ] && ok || bad "T11" "мутант без сравнения дал $RC — нога T2 не различает"
echo "costly tests: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
