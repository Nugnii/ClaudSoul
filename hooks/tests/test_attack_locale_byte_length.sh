#!/usr/bin/env bash
# test_attack_locale_byte_length.sh — АТАКА: длина в user_own_speech считается
# в БАЙТАХ, когда локаль процесса не UTF-8.
#
# Зачин-подпись гейтится двумя длинами: `[ "${#1}" -ge 500 ]` и `[ "${#_uos_first}" -le 100 ]`.
# В bash `${#var}` — символы при UTF-8-локали и БАЙТЫ при `LC_ALL=C` (и при полностью
# пустом окружении локали, что штатно для процессов, запущенных не из терминала).
# Кириллица — 2 байта на символ, значит потолок «100» превращается примерно в 50
# символов: русский зачин пересылки его пробивает, страж не срабатывает, и тело
# чужого письма целиком уходит потребителям как собственная речь собеседника.
# Второй порог едет в другую сторону: «≥ 500» становится ≈ 250 кириллических
# символов, то есть отсечение включается там, где по замыслу ещё рано.
#
# Результат один и тот же вход даёт разный вердикт в зависимости от окружения.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/hook-input-lib.sh"
HOOK="$(cd "$(dirname "$0")/.." && pwd)/reformulation-tracker.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }

PASS=0
FAIL=0

TMP=$(mktemp -d)
mkdir -p "$TMP/state"

# 68 символов / 125 байт — обычный русский зачин пересылки.
HDR="из соседней рабочей сессии агента переслано, посмотри что там пишут:"
BODY=$(awk 'BEGIN { for (i = 0; i < 12; i++) print "рецензент считает что подход не совсем верный и стоит переделать." }')
TXT="$HDR
$BODY"

speech_in_locale() {  # $1=значение LC_ALL ("" — окружение без локали вовсе) $2=текст
    if [ -z "$1" ]; then
        env -u LANG -u LC_ALL -u LC_CTYPE bash -c 'source "$0"; user_own_speech "$1"' "$LIB" "$2"
    else
        LC_ALL="$1" bash -c 'source "$0"; user_own_speech "$1"' "$LIB" "$2"
    fi
}

assert_stripped() {  # $1=локаль $2=имя
    local got
    got=$(speech_in_locale "$1" "$TXT")
    if grep -qF "не совсем" <<< "$got"; then
        FAIL=$((FAIL + 1))
        echo "FAIL [$2]: чужой маркер «не совсем» остался в собственной речи (${#got} байт вывода)"
    else
        PASS=$((PASS + 1))
    fi
}

# t1 — контроль: в UTF-8-локали страж работает, тело пересылки отсечено
assert_stripped "C.UTF-8" "t1 handoff stripped under C.UTF-8"
# t2 — та же строка под LC_ALL=C: 125 байт > 100, страж выключается
assert_stripped "C" "t2 handoff stripped under LC_ALL=C"
# t3 — окружение без локали вовсе (запуск не из терминала): те же байты
assert_stripped "" "t3 handoff stripped with no locale in env"

# t4 — вердикт обязан не зависеть от локали
a=$(speech_in_locale "C.UTF-8" "$TXT")
b=$(speech_in_locale "C" "$TXT")
if [ "$a" = "$b" ]; then PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [t4 locale-independent verdict]: C.UTF-8 дал ${#a} байт, C дал ${#b} байт"
fi

# t5 — сквозной эффект: под LC_ALL=C хук объявляет коррекцию, которой не было
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    out=$(jq -n --arg p "$TXT" '{session_id:"atk-loc",prompt:$p,transcript_path:""}' \
        | LC_ALL=C STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
    if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
        FAIL=$((FAIL + 1))
        echo "FAIL [t5 no false BACKWARD under LC_ALL=C]: хук записал коррекцию по чужому тексту"
    else
        PASS=$((PASS + 1))
    fi
fi

rm -rf "$TMP"
echo ""
echo "attack locale-byte-length: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
