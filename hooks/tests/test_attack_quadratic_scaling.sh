#!/usr/bin/env bash
# test_attack_quadratic_scaling.sh — АТАКА: время работы растёт квадратично от
# размера вставки.
#
# Накопитель `buf = buf line "\n"` в awk пересобирает всю строку на каждой строке
# входа. У awk из macOS (BWK awk 20200816) это копирование, а не дописывание:
# 5k строк — 0.08 с, 10k — 0.26 с, 20k — 0.98 с, 40k — 3.34 с (замер на месте,
# 45 байт в строке). Тот же вход через `awk '{print}'` — 0.07 с, то есть цена
# именно в накопителе.
#
# Хук исполняется на КАЖДОЙ реплике, а функция вызывается тремя потребителями
# (reformulation-tracker, itr-event-detector, intrusiveness-tracker) — задержка
# умножается на три.
#
# Тест не привязан к абсолютным секундам: он сравнивает N и 2N и требует, чтобы
# удвоение входа не давало больше чем ~2.5× времени.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/hook-input-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0

gen() {  # $1=число строк
    awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print "2026-08-26 21:00:00 INFO worker step done ok" }'
}

measure() {  # $1=число строк → лучшее из двух измерений (секунды) на stdout
    local txt; txt=$(gen "$1")
    local t best=""
    TIMEFORMAT='%R'
    for _ in 1 2; do
        t=$( { time { _out=$(user_own_speech "$txt"); } ; } 2>&1 )
        best=$(awk -v a="$best" -v b="$t" 'BEGIN { if (a == "" || b + 0 < a + 0) print b; else print a }')
    done
    printf '%s' "$best"
}

N=10000
T1=$(measure "$N")
T2=$(measure $((N * 2)))
RATIO=$(awk -v a="$T1" -v b="$T2" 'BEGIN { if (a <= 0) a = 0.001; printf "%.2f", b / a }')

echo "user_own_speech: ${N} строк → ${T1}s, $((N * 2)) строк → ${T2}s, рост ×${RATIO}"

if awk -v r="$RATIO" 'BEGIN { exit !(r <= 2.5) }'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [scaling is superlinear]: удвоение входа дало ×${RATIO} времени (порог 2.5)"
fi

echo ""
echo "attack quadratic-scaling: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
