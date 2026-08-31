#!/usr/bin/env bash
# test_attack_quoted_marker_leaks.sh — АТАКА: чужая речь В СТРОКЕ (обычные кавычки)
# по-прежнему считается коррекцией собеседника.
#
# `user_own_speech` режет только ПОСТРОЧНО: ``` — ограда, `>` — цитата, `##` — заголовок.
# Пересказ чужих слов внутри одного предложения — «он ответил "не совсем так", но
# по-моему всё верно» — остаётся целиком, маркер `не совсем` совпадает, и хук пишет
# «Пользователь КОРРЕКТИРУЕТ» на реплику, которая как раз СОГЛАШАЕТСЯ.
#
# Тот же текст с ёлочками молчит — но не потому, что функция что-то отсекла:
# `pad_words` заменяет пробелами только ASCII-пунктуацию, «ёлочка» приклеена к слову
# и мешает совпадению. Защита случайна и держится на форме кавычек, а не на авторстве.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
TMP=$(mktemp -d)
mkdir -p "$TMP/state"

run() {  # $1=prompt $2=sid
    jq -n --arg s "$2" --arg p "$1" '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

ASCII='он ответил "не совсем так", но по-моему всё верно'
GUILL='он ответил «не совсем так», но по-моему всё верно'

# t1 — библиотека обязана убрать чужие слова из собственной речи
own=$(user_own_speech "$ASCII")
if grep -qF "не совсем" <<< "$own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [t1 inline quote stripped]: чужой маркер остался: $own"
else PASS=$((PASS + 1)); fi

# t2 — сквозной эффект: согласие объявлено коррекцией
out=$(run "$ASCII" "atk-q1")
if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
    FAIL=$((FAIL + 1)); echo "FAIL [t2 no false BACKWARD on quoted foreign speech]: хук записал коррекцию"
else PASS=$((PASS + 1)); fi

# t3 — форма кавычек не должна менять вердикт
a=$(run "$ASCII" "atk-q2" | grep -c "КОРРЕКТИРУЕТ" || true)
b=$(run "$GUILL" "atk-q3" | grep -c "КОРРЕКТИРУЕТ" || true)
if [ "$a" = "$b" ]; then PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [t3 verdict independent of quote glyph]: \" → $a срабатываний, « → $b"
fi

# t4 — контроль: настоящая коррекция собеседника обязана гореть
out=$(run "нет, не совсем то, я про другое" "atk-q4")
if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [t4 real correction still fires (control)]"; fi

rm -rf "$TMP"
echo ""
echo "attack quoted-marker-leaks: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
