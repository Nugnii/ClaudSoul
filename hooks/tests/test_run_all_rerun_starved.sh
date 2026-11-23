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

# ── D482: повтор в одиночку получает и УПАВШИЙ, а не только убитый ──────────────────────
# «Нагрузку» разыгрывает метка: первый прогон падает кодом 141 (как SIGPIPE под соседями) и
# ставит метку, повтор её видит и проходит. Сломанный падает кодом 4 всегда.
T2=$(mktemp -d)
mkdir -p "$T2/tests"
cp "$DIR/run_all.sh" "$T2/tests/"; cp "$DIR/../timeout-lib.sh" "$T2/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T2/tests/drift-check.sh"; chmod +x "$T2/tests/drift-check.sh"
printf '#!/usr/bin/env bash\nif [ ! -f "%s/flaky" ]; then touch "%s/flaky"; echo "PASS [L1]: ok"; echo "FAIL [L7 нога]: стог"; for i in $(seq 30); do echo "s$i"; done; echo "FAIL [L9]: вторая"; echo "PASS=1 FAIL=2"; echo "===="; echo "хвост: труба оборвана"; echo "===="; exit 141; fi\necho ok\nexit 0\n' "$T2" "$T2" > "$T2/tests/test_flaky.sh"
printf '#!/usr/bin/env bash\necho "сломан по делу"\nexit 4\n' > "$T2/tests/test_broken.sh"
printf '#!/usr/bin/env bash\necho ok\nexit 0\n' > "$T2/tests/test_fine.sh"
chmod +x "$T2/tests"/test_*.sh
run2() { (cd "$T2/tests" && SUITE_RUN_LOG="$T2/suite-run.tsv" SUITE_BASELINE_FILE="$T2/baseline.tsv" \
    TEST_TIMEOUT=30 TEST_TIMEOUT_MIN=30 TEST_JOBS=2 TEST_RERUN_FACTOR=4 PROGRESS_EVERY=99 "$@" bash run_all.sh 2>&1); }
OUT2=$(run2 env); RC2=$?
FLAKY=$(printf '%s\n' "$OUT2" | awk '/^УПАЛИ ТОЛЬКО ПОД НАГРУЗКОЙ/ { f = 1; print; next } f && /^  / { print; next } f { exit }')
FAILED2=$(printf '%s\n' "$OUT2" | grep '^FAILED:')
if grep -qE 'test_flaky.sh: код 141 за [0-9?]+ с при соседях 1, в одиночку зелёный за [0-9?]+ с' <<< "$FLAKY"; then ok
else bad "D482a" "упавший только в прогоне не назван своей строкой с кодом и соседями: $OUT2"; fi
if grep -q 'хвост: труба оборвана' <<< "$FLAKY"; then ok; else bad "D482b" "хвост первого падения не сохранён: $FLAKY"; fi
# Строка ноги стоит выше многострочного стога (D1189): хвост её не берёт, отчёт обязан назвать её сам. Нога ПЕРВАЯ:
# выше неё зелёная строка, стог 30 строк, ниже вторая нога и итог `PASS=1 FAIL=2` — мутанты `tail -6`, «последняя
# строка с FAIL», `head -1` краснят (скептик D1189, M1); рамка `====` в хвосте дважды — повтор хвоста не снимается (L1).
if grep -q 'FAIL \[L7 нога\]' <<< "$FLAKY"; then ok; else bad "D1189" "первая упавшая нога не названа: $FLAKY"; fi
[ "$(grep -c '^ *====$' <<< "$FLAKY")" = 2 ] && ok || bad "D1189b" "повтор хвоста снят вместе с повтором строки FAIL: $FLAKY"
if ! grep -q 'test_flaky.sh' <<< "$FAILED2"; then ok; else bad "D482c" "упавший только под нагрузкой попал в провалы: $FAILED2"; fi
if grep -q 'test_broken.sh' <<< "$FAILED2" && grep -q 'test_broken.sh (код 4)' <<< "$OUT2" && ! grep -q 'test_broken.sh' <<< "$FLAKY"; then ok
else bad "D482d" "упавший и в одиночку не остался провалом с кодом 4: $FAILED2"; fi
if grep -q 'Hook test files: 2/3 passed' <<< "$OUT2" && [ "$RC2" -ne 0 ]; then ok
else bad "D482e" "итог не 2/3 или код 0 при настоящем провале: $(grep 'Hook test files' <<< "$OUT2") rc=$RC2"; fi
codes2=$(awk -F'\t' '$3 == "test_flaky.sh" { printf "%s ", $1 }' "$T2/suite-run.tsv")
[ "$codes2" = "141 0 " ] && ok || bad "D482f" "журнал попыток «${codes2}», ждали «141 0 »"
# Предел повторов: TEST_RERUN_MAX=0 — упавшие не повторяются и названы пропущенными поимённо.
rm -f "$T2/flaky" "$T2/baseline.tsv"
OUT3=$(run2 env TEST_RERUN_MAX=0)
if grep -q '^ПОВТОР В ОДИНОЧКУ ПРОПУЩЕН.*test_flaky.sh' <<< "$OUT3" && grep -q '^FAILED:.*test_flaky.sh' <<< "$OUT3"; then ok
else bad "D482g" "предел повторов не соблюдён или пропуск не назван: $(grep -E '^FAILED|ПРОПУЩЕН' <<< "$OUT3" | tr '\n' ' ')"; fi
echo ""
echo "run_all rerun starved: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
