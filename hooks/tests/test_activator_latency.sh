#!/usr/bin/env bash
# СУДИТ: scripts/activator-latency.sh
# test_activator_latency.sh — замер стенного времени хука знаний различает: в пределе (0, числа названы), выше предела
# (1), не измерено (2: нет хука или базы знаний, хук упал или промолчал). Мера — МЕДИАНА трёх прогонов, предел растёт с
# нагрузкой НА ЯДРО. Рамка: хук — заглушка с задержкой по номеру прогона (KA_HOOK), база — каталог с одним файлом,
# нагрузка и ядра заданы (KA_LOAD, KA_NCPU), чтобы машина не решала исход.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/scripts/activator-latency.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
command -v perl >/dev/null 2>&1 || { echo "SKIP: нет perl"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lessons"; : > "$T/lessons/case-x.md"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho "{}"\n' > "$T/fast.sh"
# Задержка по номеру прогона: 0,05 / 1,0 / 3,0 с — медиана 1,0, минимум 0,05, максимум 3,0 (скептик opus, M4). Зазоры против
# пределов — не меньше 0,6 с: при 0,5 / 0,6 граница хода под нагрузкой 21 видела «Проверку» D1234 красной (7 ноября 2026).
printf '#!/usr/bin/env bash\ncat >/dev/null\nn=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "%s/n"\ncase $n in 1) sleep 0.05 ;; 2) sleep 1.0 ;; *) sleep 3.0 ;; esac\necho "{}"\n' "$T" "$T" > "$T/steps.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 127\n' > "$T/dead.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$T/mute.sh"
run() { OUT=$(env LESSONS_DIR="$T/lessons" KA_LOAD="${LOAD:-1}" KA_NCPU="${NCPU:-10}" "$@" bash "$S" 2>&1); RC=$?; }

# T1 — в пределе: 0 и строка с медианой, нагрузкой, ядрами и пределом.
LOAD=1 NCPU=10; run KA_HOOK="$T/fast.sh" KA_LIMIT=50
[ "$RC" = 0 ] && grep -q 'медиана .* с (прогоны: .*), нагрузка 1.00 на 10 ядер, предел 50.00 с' <<< "$OUT" && ok \
    || bad T1 "в пределе — ждали 0 и строку с числами: код $RC, «${OUT}»"
# T2 — медиана, а не минимум: предел 0,4 с при медиане 1,0 — выше (минимум 0,05 прошёл бы).
rm -f "$T/n"; LOAD=1 NCPU=10; run KA_HOOK="$T/steps.sh" KA_LIMIT=0.4
[ "$RC" = 1 ] && grep -q 'медиана 1\.' <<< "$OUT" && ok || bad T2 "медиана 1,0 при пределе 0,4 — ждали 1: код $RC, «${OUT}»"
# T3 — медиана, а не максимум: предел 2,0 с при медиане 1,0 — в пределе (максимум 3,0 не прошёл бы).
rm -f "$T/n"; LOAD=1 NCPU=10; run KA_HOOK="$T/steps.sh" KA_LIMIT=2.0
[ "$RC" = 0 ] && ok || bad T3 "медиана 1,0 при пределе 2,0 — ждали 0: код $RC, «${OUT}»"
# T4 — поправка на нагрузку на ядро: 20 на 10 ядер — предел вдвое (0,8 → 1,6), медиана 1,0 в пределе (без поправки — нет).
rm -f "$T/n"; LOAD=20 NCPU=10; run KA_HOOK="$T/steps.sh" KA_LIMIT=0.8
[ "$RC" = 0 ] && grep -q 'предел 1.60 с' <<< "$OUT" && ok || bad T4 "нагрузка 20 на 10 ядер — ждали предел 1,60 и 0: код $RC, «${OUT}»"
# T5 — нагрузка ниже числа ядер поправки не даёт, потолок поправки — вчетверо.
rm -f "$T/n"; LOAD=5 NCPU=10; run KA_HOOK="$T/steps.sh" KA_LIMIT=0.8
[ "$RC" = 1 ] && grep -q 'предел 0.80 с' <<< "$OUT" && ok || bad T5 "нагрузка 5 на 10 ядер — ждали предел 0,80 и 1: код $RC, «${OUT}»"
rm -f "$T/n"; LOAD=400 NCPU=10; run KA_HOOK="$T/steps.sh" KA_LIMIT=0.1
grep -q 'предел 0.40 с' <<< "$OUT" && ok || bad T5b "потолок поправки — вчетверо: «${OUT}»"
# T6 — упавший и промолчавший хук — не измерено, а не «быстро».
run KA_HOOK="$T/dead.sh"
[ "$RC" = 2 ] && grep -q 'не измерено' <<< "$OUT" && ok || bad T6 "хук упал — ждали 2: код $RC, «${OUT}»"
run KA_HOOK="$T/mute.sh"
[ "$RC" = 2 ] && ok || bad T6b "хук промолчал — ждали 2: код $RC, «${OUT}»"
# T7 — хука нет; базы нет либо она пуста: 2.
run KA_HOOK="$T/none.sh"
[ "$RC" = 2 ] && ok || bad T7 "нет хука — ждали 2: код $RC"
OUT=$(KA_HOOK="$T/fast.sh" LESSONS_DIR="$T/empty" bash "$S" 2>&1); RC=$?
[ "$RC" = 2 ] && grep -q 'базы знаний нет' <<< "$OUT" && ok || bad T7b "нет базы — ждали 2: код $RC, «${OUT}»"

echo "activator-latency: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
