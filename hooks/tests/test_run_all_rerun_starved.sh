#!/usr/bin/env bash
# test_run_all_rerun_starved.sh — раннер различает «тесту не хватило времени» и «тест завис» (D340, R6).
#
# Результат: убитый сторожем тест повторяется в одиночку с кратным сроком; прошедший назван своей
#            строкой «НЕ ХВАТИЛО ВРЕМЕНИ» с временем и числом соседей и в провалы не входит; убитый
#            снова — «ЗАВИСЛИ»; упавший при повторе иным кодом — провал с этим кодом.
# Проверка результата: bash hooks/tests/test_run_all_rerun_starved.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
mkdir -p "$TMP/tests"
cp "$DIR/run_all.sh" "$TMP/tests/"
cp "$DIR/../timeout-lib.sh" "$TMP/"   # раннер зовёт снятие дерева из библиотеки (D369)
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/tests/drift-check.sh"; chmod +x "$TMP/tests/drift-check.sh"
# Срок 3 с, повтор в 4 раза (12 с): медленный исправный спит 8 с и молчит — под сроком убит, в
# одиночку успевает; зависший спит 100 с; «упавший по делу» первый раз висит, второй — падает кодом 3.
printf '#!/usr/bin/env bash\nsleep 8\necho done\nexit 0\n' > "$TMP/tests/test_slow.sh"
printf '#!/usr/bin/env bash\nsleep 100\n' > "$TMP/tests/test_hang.sh"
printf '#!/usr/bin/env bash\nif [ ! -f "%s/marker" ]; then touch "%s/marker"; sleep 100; fi\necho "падаю по делу"; exit 3\n' "$TMP" "$TMP" > "$TMP/tests/test_bad_after.sh"
printf '#!/usr/bin/env bash\necho ok\nexit 0\n' > "$TMP/tests/test_fine.sh"
chmod +x "$TMP/tests"/test_*.sh
export SUITE_RUN_LOG="$TMP/suite-run.tsv" SUITE_BASELINE_FILE="$TMP/baseline.tsv"
OUT=$(cd "$TMP/tests" && TEST_TIMEOUT=3 TEST_TIMEOUT_MIN=3 TEST_JOBS=2 TEST_RERUN_FACTOR=4 PROGRESS_EVERY=99 bash run_all.sh 2>&1); RC=$?
FAILED=$(printf '%s\n' "$OUT" | grep '^FAILED:')
HUNG=$(printf '%s\n' "$OUT" | grep '^ЗАВИСЛИ')
STARVED=$(printf '%s\n' "$OUT" | awk '/^НЕ ХВАТИЛО ВРЕМЕНИ/ { f = 1; print; next } f && /^  / { print; next } f { exit }')
if grep -q 'test_slow.sh' <<< "$STARVED"; then ok; else bad "T1" "медленный исправный не назван в «НЕ ХВАТИЛО ВРЕМЕНИ»: $OUT"; fi
if grep -qE 'test_slow.sh: первый прогон [0-9]+ с при соседях 1 .* в одиночку зелёный за [0-9]+ с' <<< "$STARVED"; then ok
else bad "T1b" "строка без времени и числа соседей: $STARVED"; fi
if ! grep -q 'test_slow.sh' <<< "$FAILED" && ! grep -q 'test_slow.sh' <<< "$HUNG"; then ok
else bad "T1c" "медленный исправный попал в провалы или зависшие: $FAILED | $HUNG"; fi
if grep -q 'test_hang.sh' <<< "$HUNG" && grep -q 'test_hang.sh' <<< "$FAILED"; then ok
else bad "T2" "зависший не назван зависшим: $HUNG | $FAILED"; fi
if ! grep -q 'test_hang.sh' <<< "$STARVED"; then ok; else bad "T2b" "зависший выдан за «не хватило времени»"; fi
if grep -q 'test_bad_after.sh' <<< "$FAILED" && grep -q 'test_bad_after.sh (код 3)' <<< "$OUT" && ! grep -q 'test_bad_after.sh' <<< "$HUNG"; then ok
else bad "T3" "упавший при повторе не назван провалом с кодом 3: $(printf '%s\n' "$OUT" | grep -E 'bad_after' | tr '\n' ' ')"; fi
[ "$RC" -ne 0 ] && ok || bad "T4" "набор с зависшим тестом вернул 0"
if grep -qE 'Hook test files: 2/4 passed' <<< "$OUT"; then ok; else bad "T4b" "счёт итога не 2/4: $(grep 'Hook test files' <<< "$OUT")"; fi
codes=$(awk -F'\t' '$3 == "test_slow.sh" { printf "%s ", $1 }' "$SUITE_RUN_LOG")
[ "$codes" = "137 0 " ] && ok || bad "T5" "журнал попыток медленного: «${codes}», ждали «137 0 »"
# Базис первого прогона снимается: иначе персональные сроки второго прогона выросли бы из
# него, и «прежнее поведение» сравнивалось бы не при тех же условиях.
rm -f "$TMP/baseline.tsv"
OUT1=$(cd "$TMP/tests" && rm -f "$TMP/marker" && TEST_TIMEOUT=3 TEST_TIMEOUT_MIN=3 TEST_JOBS=2 TEST_RERUN_FACTOR=1 PROGRESS_EVERY=99 bash run_all.sh 2>&1)
if grep -q 'ЗАВИСЛИ.*test_slow.sh' <<< "$OUT1" && ! grep -q 'НЕ ХВАТИЛО' <<< "$OUT1"; then ok
else bad "T6" "при отключённом повторе поведение не прежнее: $(grep -E 'ЗАВИСЛИ|НЕ ХВАТИЛО' <<< "$OUT1" | tr '\n' ' ')"; fi
if ! pgrep -f "$TMP/tests/test_" >/dev/null 2>&1; then ok; else bad "T7" "остались процессы фикстур"; fi
echo ""
echo "run_all rerun starved: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
