#!/usr/bin/env bash
# test_run_all_idle_timeout.sh — сторож раннера судит о ПРОДВИЖЕНИИ, а не о стенных секундах.
#
# Предмет (D368). Стенной порог означал разное при разном числе потоков: под нагрузкой тест,
# зелёный поодиночке, убивался из-за соседей (замер 8 сентября 2026). Теперь отсчёт сбрасывает
# рост вывода теста. Три фикстуры на одном прогоне: говорящий дольше срока — выживает;
# молчащий — убит по сроку; говорящий дольше пятикратного потолка — убит по потолку
# (контрпример: без потолка «говорящий» бесконечный цикл был бы бессмертен).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tests"
cp "$DIR/run_all.sh" "$TMP/tests/"
cp "$DIR/../timeout-lib.sh" "$TMP/"   # раннер зовёт снятие дерева из библиотеки (D369)
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/tests/drift-check.sh"; chmod +x "$TMP/tests/drift-check.sh"
# Срок 3 с (пол тоже 3): говорящий печатает каждую секунду 6 с — стенной порог убил бы его,
# срок без продвижения — нет. Молчащий спит 6 с. Говорящий-бесконечный печатает 20 с при
# потолке 3 × 5 = 15 с.
printf '#!/usr/bin/env bash\nfor i in 1 2 3 4 5 6; do echo tick; sleep 1; done\nexit 0\n' > "$TMP/tests/test_talker.sh"
printf '#!/usr/bin/env bash\nsleep 6\necho done\nexit 0\n' > "$TMP/tests/test_silent.sh"
printf '#!/usr/bin/env bash\ni=0; while [ $i -lt 20 ]; do echo tick; sleep 1; i=$((i+1)); done\nexit 0\n' > "$TMP/tests/test_capped.sh"
chmod +x "$TMP/tests"/test_*.sh
export SUITE_RUN_LOG="$TMP/suite-run.tsv" SUITE_BASELINE_FILE="$TMP/baseline.tsv"
# Предмет этого теста — сторож ПЕРВОЙ фазы; повтор убитых в одиночку (D340) отключён явно,
# иначе «молчащий» и «говорящий-бесконечный» прошли бы при повторе и ушли бы из FAILED —
# у повтора свой прибор, test_run_all_rerun_starved.sh.
OUT=$(cd "$TMP/tests" && TEST_TIMEOUT=3 TEST_TIMEOUT_MIN=3 TEST_JOBS=3 TEST_RERUN_FACTOR=1 PROGRESS_EVERY=99 bash run_all.sh 2>&1)
FAILED=$(printf '%s\n' "$OUT" | grep '^FAILED:')

# T1: говорящий дольше срока ЖИВ — стенной порог 3 с убил бы его на 6-секундном тесте.
if ! grep -q 'test_talker.sh' <<< "$FAILED"; then ok
else bad "T1" "говорящий тест убит, хотя вывод рос: «${FAILED}»"; fi

# T2: молчащий убит по сроку и назван зависшим.
if grep -q 'test_silent.sh' <<< "$FAILED" && grep -q 'ЗАВИСЛИ.*test_silent.sh' <<< "$OUT"; then ok
else bad "T2" "молчащий тест не убит или не назван: «$(printf '%s\n' "$OUT" | grep -E '^FAILED|ЗАВИСЛИ' | tr '\n' ' ')»"; fi

# T3: КОНТРПРИМЕР — говорящий дольше потолка убит: продвижение не делает тест бессмертным.
if grep -q 'test_capped.sh' <<< "$FAILED" && grep -q 'ЗАВИСЛИ.*test_capped.sh' <<< "$OUT"; then ok
else bad "T3" "говорящий-бесконечный пережил потолок: «$(printf '%s\n' "$OUT" | grep -E '^FAILED|ЗАВИСЛИ' | tr '\n' ' ')»"; fi

# T4: код убитого — 137 в журнале (убит сторожем, а не упал), у живого — 0.
c_s=$(awk -F'\t' '$3=="test_silent.sh"{print $1}' "$SUITE_RUN_LOG"); c_t=$(awk -F'\t' '$3=="test_talker.sh"{print $1}' "$SUITE_RUN_LOG")
if [ "$c_s" = "137" ] && [ "$c_t" = "0" ]; then ok
else bad "T4" "коды в журнале: молчащий «${c_s}» (ждали 137), говорящий «${c_t}» (ждали 0)"; fi

# T5: сторож не оставляет сирот — после прогона нет живых процессов фикстур.
if ! pgrep -f "$TMP/tests/test_" >/dev/null 2>&1; then ok
else bad "T5" "после прогона остались процессы фикстур: $(pgrep -fl "$TMP/tests/test_" | head -2)"; fi

# T6: правило названо в раннере словом, по которому его найдёт «Проверка» D368.
if grep -q 'ПРОДВИЖЕНИ' "$DIR/run_all.sh"; then ok
else bad "T6" "в run_all.sh нет слова о продвижении — сторож снова стенной?"; fi

echo ""
echo "run_all idle timeout: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
