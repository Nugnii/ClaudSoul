#!/usr/bin/env bash
# test_attack_r3_quadratic_gsub.sh — АТАКА: вырезание чужой речи квадратично по ДЛИНЕ
# СТРОКИ, и одна длинная строка с кавычками вешает хук на секунды.
#
# Раунд 1 (атака 7) закрыл квадратичность по ЧИСЛУ СТРОК: накопление `buf = buf line`
# заменено на массив. Второй квадрат остался в той же функции и на строке ниже:
# `gsub(/"[^"]*"/, " ", line)` перестраивает строку на каждой замене, поэтому цена
# растёт как квадрат числа кавычковых пар В ОДНОЙ СТРОКЕ. Замер на этой машине:
#
#   одна строка, пары кавычек:   250 КБ — 208 мс | 500 КБ — 715 мс | 1 МБ — 2644 мс | 2 МБ — 10135 мс
#   одна строка, без кавычек:    250 КБ —  65 мс | 500 КБ — 113 мс | 1 МБ —  209 мс | 2 МБ —   413 мс
#
# Удвоение входа даёт ×3.6 времени вместо ×2. Форма входа — не синтетика: свёрнутый
# в одну строку JSON, строка CSV, кусок собранного бандла, дамп ответа API. Всё это
# вставляют в реплику именно целиком и именно одной строкой.
#
# Цена умножается на три: функцию на каждой реплике зовут reformulation-tracker,
# itr-event-detector и intrusiveness-tracker (через itr_compute_state). 1 МБ вставки
# = около 8 секунд задержки перед ответом, 2 МБ = около 30.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

now_ms() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time;print(int(time.time()*1000))'
    elif command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'print int(time()*1000)'
    else
        echo ""
    fi
}
if [ -z "$(now_ms)" ]; then
    echo "FAIL [timer]: нет ни python3, ни perl — замерить нечем, зелёный был бы пустым"
    exit 1
fi

# Одна длинная строка из пар кавычек (свёрнутый JSON выглядит так же).
mk_quoted() { awk -v n="$1" 'BEGIN{ for (i = 0; i < n; i++) printf "\"ab\"" }'; }
# Та же длина без единой кавычки — контроль на «дело не в объёме».
mk_plain()  { awk -v n="$1" 'BEGIN{ for (i = 0; i < n; i++) printf "abcd" }'; }

# Минимум из двух прогонов — шум машины срезается, а квадрат никуда не девается.
measure() {  # $1 = текст → печатает миллисекунды
    local best="" s e d i
    for i in 1 2; do
        s=$(now_ms)
        user_own_speech "$1" >/dev/null
        e=$(now_ms)
        d=$((e - s))
        if [ -z "$best" ] || [ "$d" -lt "$best" ]; then best="$d"; fi
    done
    printf '%s' "$best"
}

HALF="вставил дамп
$(mk_quoted 125000)"     # ~500 КБ
FULL="вставил дамп
$(mk_quoted 250000)"     # ~1 МБ
PLAIN="вставил дамп
$(mk_plain 250000)"      # ~1 МБ, кавычек нет

MS_HALF=$(measure "$HALF")
MS_FULL=$(measure "$FULL")
MS_PLAIN=$(measure "$PLAIN")

echo "замер: 500КБ+кавычки=${MS_HALF}мс  1МБ+кавычки=${MS_FULL}мс  1МБ без кавычек=${MS_PLAIN}мс"

# t0 — контроль: тот же объём без кавычек обрабатывается линейно и быстро
if [ "$MS_PLAIN" -lt 1500 ]; then ok
else bad "t0 plain 1MB baseline" "даже без кавычек ${MS_PLAIN} мс — замер сделан на загруженной машине, вердикты ниже недостоверны"; fi

# t1 — АТАКА: тот же объём с кавычками не укладывается в бюджет хука
if [ "$MS_FULL" -lt 1500 ]; then ok
else bad "t1 quoted 1MB too slow" "${MS_FULL} мс на одну вставку в одном хуке (без кавычек — ${MS_PLAIN} мс)"; fi

# t2 — АТАКА: удвоение входа обязано удваивать время, а не утраивать
#      (порог 2.5 при линейном ожидании 2.0 — запас на шум замера)
RATIO_X10=$(( MS_FULL * 10 / (MS_HALF > 0 ? MS_HALF : 1) ))
if [ "$RATIO_X10" -le 25 ]; then ok
else bad "t2 superlinear scaling" "удвоение входа дало ×$((RATIO_X10 / 10)).$((RATIO_X10 % 10)) времени (${MS_HALF} → ${MS_FULL} мс)"; fi

echo ""
echo "attack r3 quadratic-gsub: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
