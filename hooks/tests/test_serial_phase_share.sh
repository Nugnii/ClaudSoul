#!/usr/bin/env bash
# СУДИТ: scripts/serial-phase-share.sh
# test_serial_phase_share.sh — свидетель замера доли последовательной фазы (D363).
# Результат: раннер печатает фазу каждого теста режимом --phases; замер считает долю по этой
#            печати, отвечает 1 выше порога и 0 ниже, 2 без раннера; правило фазы у замера не своё.
# Проверка результата: bash hooks/tests/test_serial_phase_share.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TOOL="$ROOT/scripts/serial-phase-share.sh"
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
mkdir -p "$TMP/tests"
cp "$DIR/run_all.sh" "$TMP/tests/"; cp "$DIR/../timeout-lib.sh" "$TMP/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/tests/drift-check.sh"
# Восемь параллельных, два последовательных по правилу раннера: коммит без своего репозитория и
# запись в боевой каталог состояния без своего STATE_DIR. Обе формы собираются из байтов (\x63 —
# «c»), потому что правило читает ТЕКСТ теста: свидетель, процитировавший форму буквально, сам
# уходил в последовательную фазу — так было при первой сборке 13 сентября 2026 (68 из 504).
for i in 1 2 3 4 5 6 7 8; do printf '#!/usr/bin/env bash\necho ok\nexit 0\n' > "$TMP/tests/test_p$i.sh"; done
printf '#!/usr/bin/env bash\ngit \x63ommit -qm x 2>/dev/null; exit 0\n' > "$TMP/tests/test_s1.sh"
printf '#!/usr/bin/env bash\necho x > "/opt/x/hooks/\x73tate/probe"; exit 0\n' > "$TMP/tests/test_s2.sh"
chmod +x "$TMP/tests"/*.sh
# T1: --phases печатает фазу каждого теста и ничего не прогоняет
PH=$(cd "$TMP/tests" && bash run_all.sh --phases 2>/dev/null)
[ "$(printf '%s\n' "$PH" | grep -c .)" = 10 ] && ok || bad "T1" "--phases напечатал не 10 строк: $PH"
grep -qE $'^serial\ttest_s1.sh$' <<< "$PH" && grep -qE $'^serial\ttest_s2.sh$' <<< "$PH" && ok || bad "T1b" "последовательные не опознаны: $PH"
grep -qE $'^parallel\ttest_p1.sh$' <<< "$PH" && ok || bad "T1c" "параллельный не опознан: $PH"
grep -q "Hook test files" <<< "$PH" && bad "T1d" "--phases прогнал тесты" || ok
# T2: замер — 2 из 10 = 20%: порог 15 → находка (1), порог 25 → 0; базис даёт долю времени
printf '3\ttest_s1.sh\n1\ttest_p1.sh\n' > "$TMP/baseline.tsv"
OUT=$(STATE_DIR="$TMP/state" TESTS_DIR="$TMP/tests" SUITE_BASELINE_FILE="$TMP/baseline.tsv" SERIAL_SHARE_MAX=15 bash "$TOOL" 2>&1); RC=$?
[ "$RC" = 1 ] && ok || bad "T2" "20% при пороге 15 — ожидался 1, получен $RC: $OUT"
grep -q "тестов 2 из 10 (20%)" <<< "$OUT" && ok || bad "T2b" "доля не названа: $OUT"
grep -q "последовательные 3 с из 4 с (75%)" <<< "$OUT" && ok || bad "T2c" "доля времени по базису не названа: $OUT"
OUT=$(STATE_DIR="$TMP/state" TESTS_DIR="$TMP/tests" SUITE_BASELINE_FILE="$TMP/baseline.tsv" SERIAL_SHARE_MAX=25 bash "$TOOL" 2>&1); RC=$?
[ "$RC" = 0 ] && ok || bad "T3" "20% при пороге 25 — ожидался 0, получен $RC"
# T4: без раннера — 2, не ноль
RC=$(STATE_DIR="$TMP/state" TESTS_DIR="$TMP/none" bash "$TOOL" >/dev/null 2>&1; echo $?)
[ "$RC" = 2 ] && ok || bad "T4" "без раннера ожидался 2, получен $RC"
# T5: правило фазы у замера НЕ своё: мутант раннера, считающий всё параллельным, даёт 0 последовательных
sed 's/^needs_serial() {.*/needs_serial() { return 1/' "$DIR/run_all.sh" > "$TMP/tests/run_all.sh"
OUT=$(STATE_DIR="$TMP/state" TESTS_DIR="$TMP/tests" SUITE_BASELINE_FILE="$TMP/baseline.tsv" SERIAL_SHARE_MAX=15 bash "$TOOL" 2>&1); RC=$?
grep -q "тестов 0 из 10" <<< "$OUT" && [ "$RC" = 0 ] && ok || bad "T5" "замер держит своё правило фазы, а не читает у раннера: $OUT"
# T11 — ТЕСТ, ЧЬЁ ВРЕМЯ МЕРИТ ВЫЗЫВАЕМЫЙ, идёт последовательно. Признак выше видит
# СОБСТВЕННУЮ функцию измерения; внутренний прогон со сторожем меряет время сам, и под
# восемью потоками он убивает другую фикстуру — нога краснеет не по своей причине
# (14 сентября 2026: два падения за ночь при зелёном одиночном прогоне).
# Функция берётся У ВЛАДЕЛЬЦА: вырезается из раннера, а не переписывается здесь.
awk '/^needs_serial\(\) \{/,/^\}/' "$DIR/run_all.sh" > "$TMP/needs_serial.sh"
# shellcheck source=/dev/null
. "$TMP/needs_serial.sh"
for _t in test_run_all_idle_timeout.sh test_run_all_rerun_starved.sh test_run_all_parallel.sh; do
    if needs_serial "$DIR/$_t"; then ok
    else bad T11 "$_t не попал в последовательную фазу, хотя судит сторожа"; fi
done
# Контроль: тест, зовущий прогон, но судящий ВЫБОР, в фазу не попадает — иначе признак
# забрал бы всех и перестал различать.
if needs_serial "$DIR/test_run_all_changed.sh"; then
    bad T11б "test_run_all_changed забран в фазу, хотя времени не судит"
else ok; fi

echo "serial phase share: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
