#!/usr/bin/env bash
# СУДИТ: hooks/portable-lib.sh
# test_iso_epoch_lines.sh — iso_epoch_lines отвечает на каждую строку так же, как iso_epoch на ЭТУ строку.
# en: iso_epoch_lines answers every line exactly as iso_epoch would for that line, keeping the line count.
#
# Повод (D1000, 17 октября 2026). Жнецы опровержений звали iso_epoch внутри цикла «провалы × показы»:
# 217 251 пара, по два процесса date и sed на пару, 257 с из 267 с границы хода. iso_epoch_lines разбирает
# метку ОДИН раз, а каноническую UTC-форму — одним процессом jq на все строки сразу. Быстрый путь
# допустим, только пока он не отвечает ничем, чего не ответил бы iso_epoch: его тождество и проверяется
# здесь — на корпусе форм, где быстрый путь легко соврёт (несуществующая дата: jq и BSD date нормализуют
# её в 2 марта, GNU date отвечает нулём; до 1970 года три реализации расходятся; доли; смещения; пробелы;
# CRLF), и тем, что строки не съезжают: потребитель сцепляет ответы с метками ПО НОМЕРУ строки.
#
# Проверяется:
#   T1  тождество по одной строке на каждой форме корпуса (один вызов — одна метка);
#   T2  тождество в ОДНОМ вызове на всём корпусе, в двух часовых поясах (местное время читает машина);
#   T3  число строк сохраняется на любой форме ввода, пустой ввод даёт пустой вывод;
#   T4  каноническая форма не стоит процессов (подменные date и sed считают вызовы), прочая — стоит;
#   T5  без jq и со сломанным jq ответ тот же — медленнее, но тот же;
#   T6  константы эпохи, известные независимо от date и jq;
#   T7  под set -euo pipefail молчит и возвращает 0; из zsh отвечает так же (библиотеку источают и из него).
#
# Предел: Linux/GNU date здесь не гоняется на машине разработки; тождество опирается на то, что тест
# сравнивает с iso_epoch ТОЙ ЖЕ машины, а не с зашитыми числами (кроме T6 — там канонические даты после 1970).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/portable-lib.sh"
# shellcheck source=/dev/null
source "$LIB"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Корпус форм. Каждая строка — одна метка (перевод строки внутри метки не бывает: строки делит read).
CORPUS=(
    '2026-09-01T10:00:00Z'                      # каноническая UTC — единственная форма быстрого пути
    '2026-09-01T10:00:00.5Z'                    # доли секунды (срезаются)
    '2026-09-01T10:00:00.123456789Z'
    '2026-09-01T10:00:00.Z'                     # точка без цифр
    '2024-02-29T23:59:59Z'                      # високосный день существует
    '2000-02-29T00:00:00Z'
    '2026-02-30T10:00:00Z'                      # дня нет: jq и BSD date нормализуют, GNU date даёт ноль
    '2026-02-29T10:00:00Z'
    '2100-02-29T00:00:00Z'
    '2026-04-31T08:00:00.5Z'
    '2026-13-01T00:00:00Z'
    '2026-00-10T00:00:00Z'
    '2026-01-00T00:00:00Z'
    '2026-01-01T24:00:00Z'
    '2026-01-01T10:00:60Z'                      # секунда координации
    '2026-01-01T10:60:00Z'
    '2026-01-01T25:00:00Z'
    '1970-01-01T00:00:00Z'                      # ноль эпохи
    '1970-01-01T00:00:01Z'
    '1969-12-31T23:59:59Z'                      # до эпохи: jq, BSD date и glibc расходятся
    '0001-01-01T00:00:00Z'
    '9999-12-31T23:59:59Z'
    '2038-01-19T03:14:08Z'                      # за пределом 32 бит
    '2026-09-01T10:00:00+03:00'                 # смещения
    '2026-09-01T10:00:00-0500'
    '2026-09-01T10:00:00+0000'
    '2026-09-01T10:00:00.5+03:00'
    '2026-09-01T10:00:00'                       # местное время без зоны
    '2026-09-01T10:00:00.250'
    '2026-03-08T02:30:00'                       # в Нью-Йорке этого времени нет (переход на летнее)
    '2026-09-01'                                # голая дата
    ''                                          # пустая строка
    ' '
    '   '
    ' 2026-09-01T10:00:00Z'                     # пробелы по краям
    '2026-09-01T10:00:00Z '
    $'2026-09-01T10:00:00Z\r'                   # CRLF
    $'2026-09-01T10:00:00Z\t'
    $'\t2026-09-01T10:00:00Z'
    $'2026-09-01T10:00:00.5Z\r'
    '2026-09-01T10:00:00z'
    'garbage'
    'null'
    '12345'
    '-1'
    '-n'
    '-e'
    '*'
    'Z'
    'T'
    '2026'
    '2026-09'
    '2026-9-1T1:2:3Z'
    '２０２６-09-01T10:00:00Z'                   # полноширинные цифры: [0-9] их не берёт
    '2026-09-01T10:00:00Z2026-09-01T10:00:00Z'
    '"2026-09-01T10:00:00Z"'
    '2026-09-01T10:00:00Z\'
    '2026-09-01T10:00:00Z;'
    '$(date)'
    '`date`'
    '2026-09-01T10:00:00.'"$(printf '%0500d' 7)"'Z'   # длинные доли
    "$(printf 'x%.0s' $(seq 1 3000))"           # длинный мусор
)
NC=${#CORPUS[@]}

# Формы, на которые сам iso_epoch отвечает ЧАСАМИ СУТОК ИЗ ЧАСОВ МАШИНЫ (нашёл этот тест 17 октября 2026):
# BSD `date -j -f "%Y-%m-%d"` читает префикс строки, хвост молча отбрасывает, а неуказанные поля берёт
# из текущего времени — `2026-09-01 10:00:00` и `2026-09-01T10` отвечают «1 сентября, сейчас-часы-минуты»,
# и два вызова подряд расходятся на секунды. Тождество «равно» тут не определено: у соседа нет единственного
# ответа. Корпус их не содержит; проверяется только, что iso_epoch_lines ОТДАЁТ их iso_epoch (запасной путь,
# ответ в тех же сутках), а не придумывает своё. Чинить iso_epoch — отдельный предмет, не этот тест.
CLOCKY=('2026-09-01 10:00:00' '2026-09-01T10' '2026-09-01T10:00')

# Ответы iso_epoch на корпус (ground truth) — по одной метке, в часовом поясе по умолчанию и в Нью-Йорке.
declare -a WANT_DEF WANT_NY
for ((i = 0; i < NC; i++)); do
    WANT_DEF[i]=$(iso_epoch "${CORPUS[i]}")
    WANT_NY[i]=$(TZ=America/New_York iso_epoch "${CORPUS[i]}")
done
printf '%s\n' "${CORPUS[@]}" > "$TMP/corpus.txt"

# --- T1: одна метка — один вызов: ответ тот же, что у iso_epoch --------------------------------
for ((i = 0; i < NC; i++)); do
    got=$(iso_epoch_lines <<<"${CORPUS[i]}")
    if [ "$got" = "${WANT_DEF[i]}" ]; then ok
    else bad "T1 #$i" "метка $(printf '%q' "${CORPUS[i]}"): iso_epoch_lines=[$got] iso_epoch=[${WANT_DEF[i]}]"; fi
done

# T1b: формы, на которые iso_epoch отвечает по часам машины, — быстрым путём они не берутся (date
# вызван), а ответ лежит в тех же сутках, что и ответ iso_epoch. GNU date форму `2026-09-01T10` не
# разбирает вовсе, и iso_epoch отдаёт 0 (раннер CI, 18 октября 2026) — тогда и iso_epoch_lines обязан
# отдать 0, а не придумать своё.
for ((i = 0; i < ${#CLOCKY[@]}; i++)); do
    got=$(iso_epoch_lines <<<"${CLOCKY[i]}"); want=$(iso_epoch "${CLOCKY[i]}")
    d=$((got - want)); [ "$d" -lt 0 ] && d=$((-d))
    if [ "$want" = 0 ] && [ "$got" = 0 ]; then ok
    elif [ "$got" != 0 ] && [ "$want" != 0 ] && [ "$d" -lt 86400 ]; then ok
    else bad "T1b #$i" "метка $(printf '%q' "${CLOCKY[i]}"): iso_epoch_lines=[$got] iso_epoch=[$want]"; fi
done

# --- T2: весь корпус одним вызовом — те же ответы в том же порядке, в двух часовых поясах ---------
for k in 0 1; do
    if [ "$k" = 0 ]; then
        iso_epoch_lines < "$TMP/corpus.txt" > "$TMP/got.$k" 2> "$TMP/err.$k"
    else
        TZ=America/New_York iso_epoch_lines < "$TMP/corpus.txt" > "$TMP/got.$k" 2> "$TMP/err.$k"
    fi
    n=$(wc -l < "$TMP/got.$k" | tr -d ' ')
    [ "$n" = "$NC" ] && ok || bad "T2 пояс $k" "строк на выходе $n, на входе $NC"
    i=0; mism=0
    while IFS= read -r line; do
        if [ "$k" = 0 ]; then want="${WANT_DEF[i]:-?}"; else want="${WANT_NY[i]:-?}"; fi
        if [ "$line" != "$want" ]; then
            mism=$((mism + 1)); bad "T2 пояс $k #$i" "метка $(printf '%q' "${CORPUS[i]:-?}"): пакет=[$line] iso_epoch=[$want]"
        fi
        i=$((i + 1))
    done < "$TMP/got.$k"
    [ "$mism" -eq 0 ] && ok
    [ ! -s "$TMP/err.$k" ] && ok || bad "T2 пояс $k stderr" "в stderr: $(head -c 200 "$TMP/err.$k")"
done

# --- T3: число строк сохраняется на любой форме ввода -------------------------------------------
# Строка — то, что читает read: хвостовой неоконченной строке тоже положен ответ. Пустой ввод — пустой вывод.
chk_shape() {  # <имя> <ожидаемое_число_строк> <ожидаемый_вывод> <printf-формат> [аргументы…]
    local name="$1" want_n="$2" want_out="$3" rc n
    shift 3
    # shellcheck disable=SC2059
    printf "$@" | iso_epoch_lines > "$TMP/shape.got"; rc=$?
    # shellcheck disable=SC2059
    printf "$want_out" > "$TMP/shape.want"
    n=$(wc -l < "$TMP/shape.got" | tr -d ' ')
    [ "$rc" = 0 ] || { bad "T3 $name" "код возврата $rc"; return; }
    [ "$n" = "$want_n" ] || { bad "T3 $name" "строк $n, ожидалось $want_n"; return; }
    cmp -s "$TMP/shape.got" "$TMP/shape.want" && ok || bad "T3 $name" "вывод разошёлся с ожидаемым"
}
# Пустой ввод: подстановка команды срезала бы пустой вывод, поэтому он проверяется отдельно, по байтам.
n=$(printf '' | iso_epoch_lines | wc -c | tr -d ' ')
[ "$n" = 0 ] && ok || bad "T3 пустой ввод" "вывод не пуст: $n байт"
n=$(iso_epoch_lines < /dev/null | wc -c | tr -d ' ')
[ "$n" = 0 ] && ok || bad "T3 /dev/null" "вывод не пуст: $n байт"
chk_shape "одна метка с переводом"        1 "1788256800\n"            '%s\n' '2026-09-01T10:00:00Z'
chk_shape "одна метка без перевода"       1 "1788256800\n"            '%s'   '2026-09-01T10:00:00Z'
chk_shape "один перевод строки"           1 "0\n"                     '\n'
chk_shape "три пустые строки"             3 "0\n0\n0\n"               '\n\n\n'
chk_shape "пустая в начале"               2 "0\n1788256800\n"         '\n%s\n' '2026-09-01T10:00:00Z'
chk_shape "пустые в конце"                3 "1788256800\n0\n0\n"      '%s\n\n\n' '2026-09-01T10:00:00Z'
chk_shape "пустая в середине"             3 "1788256800\n0\n1788256801\n" '%s\n\n%s\n' '2026-09-01T10:00:00Z' '2026-09-01T10:00:01Z'
chk_shape "хвост без перевода"            2 "1788256800\n0\n"         '%s\ngarbage' '2026-09-01T10:00:00Z'
chk_shape "мусор между каноническими"     3 "1788256800\n0\n1788256801\n" '%s\ngarbage\n%s\n' '2026-09-01T10:00:00Z' '2026-09-01T10:00:01Z'
chk_shape "порядок не меняется"           2 "1788256801\n1788256800\n" '%s\n%s\n' '2026-09-01T10:00:01Z' '2026-09-01T10:00:00Z'
# Крупный ввод: 2000 строк через одну пустую — пустые лежат и в середине, и в конце.
awk 'BEGIN { for (i = 0; i < 2000; i++) { printf "2026-09-01T10:%02d:%02dZ\n", int(i / 60) % 60, i % 60; if (i % 2) print "" } }' > "$TMP/big.in"
awk 'BEGIN { for (i = 0; i < 2000; i++) { print 1788256800 + (int(i / 60) % 60) * 60 + i % 60; if (i % 2) print 0 } }' > "$TMP/big.want"
iso_epoch_lines < "$TMP/big.in" > "$TMP/big.got" 2>/dev/null
cmp -s "$TMP/big.got" "$TMP/big.want" && ok || bad "T3 крупный" "вывод разошёлся с ожидаемым: $(diff "$TMP/big.got" "$TMP/big.want" | head -3 | tr '\n' ' ')"

# --- T4: каноническая форма не стоит процессов ---------------------------------------------------
# Подмена date и sed считает вызовы: быстрый путь обязан обходиться без них, остальное — нет. Счёт процессов
# не зависит от скорости машины, в отличие от секундомера (на GNU date медленный путь стоит единицы
# миллисекунд на метку, и порог по времени его бы не отличил).
if command -v jq >/dev/null 2>&1; then
    SHIM="$TMP/shim"; mkdir -p "$SHIM"
    for tool in date sed; do
        real=$(command -v "$tool")
        printf '#!/bin/sh\necho x >> "%s/calls.%s"\nexec "%s" "$@"\n' "$TMP" "$tool" "$real" > "$SHIM/$tool"
        chmod +x "$SHIM/$tool"
    done
    # Каждая третья метка с долями секунды: доли тоже берёт быстрый путь (iso_epoch срезает их sed-ом).
    awk 'BEGIN { for (i = 0; i < 3600; i++) printf "2026-09-01T10:%02d:%02d%sZ\n", int(i / 60), i % 60, (i % 3 == 0 ? ".250" : "") }' > "$TMP/canon.in"
    awk 'BEGIN { for (i = 0; i < 3600; i++) print 1788256800 + i }' > "$TMP/canon.want"
    : > "$TMP/calls.date"; : > "$TMP/calls.sed"
    ( PATH="$SHIM:$PATH"; hash -r; iso_epoch_lines < "$TMP/canon.in" > "$TMP/canon.got" 2>/dev/null )
    cmp -s "$TMP/canon.got" "$TMP/canon.want" && ok || bad "T4 значения" "3600 канонических меток: ответы разошлись с ожидаемыми"
    nd=$(wc -l < "$TMP/calls.date" | tr -d ' '); ns=$(wc -l < "$TMP/calls.sed" | tr -d ' ')
    [ "$nd" = 0 ] && [ "$ns" = 0 ] && ok || bad "T4 процессы" "3600 канонических меток стоили $nd вызовов date и $ns вызовов sed (ожидалось 0 и 0)"
    # Контроль подмены: метка местного времени быстрым путём не берётся, и подмена это видит.
    : > "$TMP/calls.date"
    ( PATH="$SHIM:$PATH"; hash -r; iso_epoch_lines <<<"2026-09-01T10:00:00" > /dev/null 2>&1 )
    nd=$(wc -l < "$TMP/calls.date" | tr -d ' ')
    [ "$nd" -ge 1 ] && ok || bad "T4 контроль" "подмена date не увидела разбор местного времени — счёт процессов ничего не доказывает"
    # Несуществующая дата и дата до 1970 тоже идут запасным путём, а не быстрым.
    for odd in '2026-02-30T10:00:00Z' '1969-12-31T23:59:59Z'; do
        : > "$TMP/calls.date"
        ( PATH="$SHIM:$PATH"; hash -r; iso_epoch_lines <<<"$odd" > /dev/null 2>&1 )
        nd=$(wc -l < "$TMP/calls.date" | tr -d ' ')
        [ "$nd" -ge 1 ] && ok || bad "T4 $odd" "метка ушла быстрым путём (вызовов date: $nd), а iso_epoch обязан ответить сам"
    done
fi

# --- T5: без jq и со сломанным jq ответ тот же -------------------------------------------------
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for tool in date sed cat; do ln -s "$(command -v "$tool")" "$NOJQ/$tool"; done
( PATH="$NOJQ"; hash -r; iso_epoch_lines < "$TMP/corpus.txt" > "$TMP/got.nojq" 2>/dev/null )
BADJQ="$TMP/badjq"; mkdir -p "$BADJQ"
printf '#!/bin/sh\necho "jq: error: сломан" >&2\nexit 5\n' > "$BADJQ/jq"; chmod +x "$BADJQ/jq"
( PATH="$BADJQ:$PATH"; hash -r; iso_epoch_lines < "$TMP/corpus.txt" > "$TMP/got.badjq" 2>/dev/null )
# Лживый jq: на каждую строку отвечает мусором и дописывает лишние строки — ответ не цифры, значит спрашивать iso_epoch.
LIEJQ="$TMP/liejq"; mkdir -p "$LIEJQ"
printf '#!/bin/sh\nsed "s/.*/oops/"\necho extra1\necho extra2\n' > "$LIEJQ/jq"; chmod +x "$LIEJQ/jq"
( PATH="$LIEJQ:$PATH"; hash -r; iso_epoch_lines < "$TMP/corpus.txt" > "$TMP/got.liejq" 2>/dev/null )
# Эталон без jq (D1322): то же число, что `iso_epoch` с jq (WANT_DEF), — кроме метки «…Z», которую оба `date` ЭТОЙ рамки
# отвергают (9999 год у uutils 0.10.0): её без jq не разбирает никто, честный ответ — 0. Эталон «iso_epoch той же рамки»
# был тавтологией: мутант «без jq — 0 на всём» проходил (скептик opus D1322, M1).
_date_refuses() {  # <PATH рамки> <метка> → 0, если оба `date` рамки метку отвергают
    local ts="$2"; case "$ts" in *Z) ;; *) return 1 ;; esac
    ts=$(printf '%s' "$ts" | sed 's/\.[0-9]*Z$/Z/')
    ( PATH="$1"; hash -r; ! date -u -d "$ts" +%s >/dev/null 2>&1 && ! date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s >/dev/null 2>&1 )
}
_want_in() { local i; for i in "${!CORPUS[@]}"; do
    if _date_refuses "$1" "${CORPUS[i]}"; then echo 0; else printf '%s\n' "${WANT_DEF[i]:-?}"; fi; done; }
_want_in "$NOJQ" > "$TMP/want.nojq"; _want_in "$BADJQ:$PATH" > "$TMP/want.badjq"; _want_in "$LIEJQ:$PATH" > "$TMP/want.liejq"
for v in nojq badjq liejq; do
    n=$(wc -l < "$TMP/got.$v" | tr -d ' ')
    [ "$n" = "$NC" ] || { bad "T5 $v" "строк на выходе $n, на входе $NC"; continue; }
    i=0; mism=0
    while IFS= read -r line && IFS= read -r want <&3; do
        [ "$line" = "$want" ] || { mism=$((mism + 1)); bad "T5 $v #$i" "метка $(printf '%q' "${CORPUS[i]:-?}"): ответ=[$line] iso_epoch=[$want]"; }
        i=$((i + 1))
    done < "$TMP/got.$v" 3< "$TMP/want.$v"
    [ "$i" = "$NC" ] && [ "$mism" -eq 0 ] && ok || { [ "$i" = "$NC" ] || bad "T5 $v" "сверено $i строк из $NC — эталон короче ответа"; }
done

# --- T6: константы эпохи, известные независимо от date и jq -------------------------------------
while IFS=' ' read -r ts want; do
    got=$(iso_epoch_lines <<<"$ts")
    [ "$got" = "$want" ] && ok || bad "T6 $ts" "получено [$got], ожидалось [$want]"
done <<'EOF'
2026-09-01T10:00:00Z 1788256800
2001-09-09T01:46:40Z 1000000000
2038-01-19T03:14:08Z 2147483648
2000-02-29T12:00:00Z 951825600
1970-01-01T00:00:01Z 1
2026-09-01T10:00:00.999Z 1788256800
EOF

# --- T7: под строгими флагами хука и из zsh -----------------------------------------------------
OUT=$(bash -c 'set -euo pipefail; source "$1"; printf "%s\n" garbage 2026-09-01T10:00:00Z "" | iso_epoch_lines; echo "конец rc=$?"' _ "$LIB" 2> "$TMP/err.strict")
[ "$OUT" = "$(printf '0\n1788256800\n0\nконец rc=0')" ] && [ ! -s "$TMP/err.strict" ] && ok \
    || bad "T7 строгий режим" "вывод $(printf '%q' "$OUT"), stderr: $(head -c 200 "$TMP/err.strict")"
if command -v zsh >/dev/null 2>&1; then
    OUT=$(zsh -c 'source "$1"; printf "%s\n" garbage 2026-09-01T10:00:00Z 2026-02-30T10:00:00Z "" 2026-09-01T10:00:00.5Z | iso_epoch_lines' _ "$LIB" 2>&1)
    W2=$(iso_epoch '2026-02-30T10:00:00Z')
    [ "$OUT" = "$(printf '0\n1788256800\n%s\n0\n1788256800' "$W2")" ] && ok || bad "T7 zsh" "вывод $(printf '%q' "$OUT")"
fi

echo "iso-epoch-lines: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
