#!/usr/bin/env bash
set -u
# СУДИТ: scripts/measurement-due.sh hooks/tests/run_all.sh
# probe_D1218 — дверь вложенного прогона бегуна замеров судит РЕЕСТР: набор, запущенный командой замера, судит бегуна на
#   своей фикстуре (тест исполняет его строки), а вложенный прогон того же реестра встаёт на двери — кольцо «замер →
#   набор → тест → замер» не идёт глубже одного уровня. Рамка настоящая: бегун исполняет строку реестра, строка — копию
#   `run_all.sh` с двумя тестами-зондами; дважды, `TEST_JOBS=1` и `TEST_JOBS=2` (параллельная и последовательная фазы).
#   0 — оба зонда верны в обеих фазах; 1 — тест бегуна встал на чужой двери либо кольцо прошло глубже;
#   2 — нет бегуна, раннера или их библиотек, контроль (зонд без замера исполняет бегуна) не прошёл.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
RUN="$PWD/scripts/measurement-due.sh"
for f in "$RUN" hooks/tests/run_all.sh hooks/timeout-lib.sh hooks/portable-lib.sh; do [ -f "$f" ] || exit 2; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
W=$(cd "$W" && pwd -P)
mkdir -p "$W/t/hooks/tests" && cp hooks/tests/run_all.sh "$W/t/hooks/tests/" && cp hooks/timeout-lib.sh hooks/portable-lib.sh "$W/t/hooks/" || exit 2
printf 'zin\t1\techo ВНУТРИ\tзонд\n' > "$W/own.tsv"
# Зонд-предмет: бегун на СВОЁМ реестре обязан исполнить строку и под командой замера.
printf '%s\n' '#!/usr/bin/env bash' \
    "env MEASUREMENT_REGISTRY=\"$W/own.tsv\" STATE_DIR=\"$W/s.own.\$J\" bash \"$RUN\" run >/dev/null 2>&1" \
    "grep -q ВНУТРИ \"$W/s.own.\$J/measurement-runs/zin.out\" 2>/dev/null || { echo 'PASS: 0  FAIL: 1'; exit 1; }" \
    "echo 'PASS: 1  FAIL: 0'" > "$W/t/hooks/tests/test_zond_own.sh"
# Зонд-кольцо: бегун на реестре замера (унаследован) обязан встать на двери; счётчик глубины — в строке реестра.
printf '%s\n' '#!/usr/bin/env bash' "bash \"$RUN\" run >/dev/null 2>&1" "echo 'PASS: 1  FAIL: 0'" > "$W/t/hooks/tests/test_zond_ring.sh"
# Контроль рамки: вне замера зонд-предмет исполняет бегуна.
J=ctl bash "$W/t/hooks/tests/test_zond_own.sh" >/dev/null 2>&1 || { echo "рамка: бегун на своём реестре не исполнил строку"; exit 2; }
bad=0
for j in 1 2; do
    printf 'zsuite\t1\tn=$(cat %s/d.%s 2>/dev/null || echo 0); [ "$n" -ge 2 ] && exit 0; echo $((n + 1)) > %s/d.%s; J=%s TEST_JOBS=%s bash %s/t/hooks/tests/run_all.sh\tзонд\n' \
        "$W" "$j" "$W" "$j" "$j" "$j" "$W" > "$W/m.$j.tsv"
    env MEASUREMENT_REGISTRY="$W/m.$j.tsv" STATE_DIR="$W/s.m.$j" bash "$RUN" run >/dev/null 2>&1
    [ -s "$W/d.$j" ] || { echo "рамка: бегун не исполнил строку набора (TEST_JOBS=$j)"; exit 2; }
    grep -q ВНУТРИ "$W/s.own.$j/measurement-runs/zin.out" 2>/dev/null \
        || { echo "TEST_JOBS=$j: тест бегуна на своём реестре встал на двери замера"; bad=1; }
    [ "$(cat "$W/d.$j")" = 1 ] || { echo "TEST_JOBS=$j: кольцо замер → набор → замер прошло глубже (уровней $(cat "$W/d.$j"))"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 1
echo "дверь судит реестр: тест бегуна исполняется под замером, кольцо стоит на двери"
exit 0
