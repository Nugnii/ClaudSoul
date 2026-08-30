#!/usr/bin/env bash
# test_attack_r3_typographic_quotes.sh — АТАКА: вырезание чужой прямой речи знает
# только ASCII-кавычку ("), поэтому русские «ёлочки» и типографские “лапки” проносят
# чужой маркер наружу нетронутым.
#
# В функции стоит `gsub(/"[^"]*"/, " ", line)` — он поставлен раундом 1 (атака 6) ровно
# под форму «он ответил "не совсем так", но по-моему всё верно»: маркер принадлежит
# третьему лицу, реплика собеседника — согласие. Набор символов у стража один: 0x22.
#
# Собеседник пишет по-русски. Русская раскладка macOS (и подстановка кавычек почти в любом
# редакторе, мессенджере и вебе) даёт «ёлочки» U+00AB/U+00BB, копирование из веба — “лапки”
# U+201C/U+201D. ASCII-кавычку в русском тексте надо ещё постараться набрать. То есть страж
# закрывает форму, которая у этого собеседника как раз редкая, и пропускает обе частые.
#
# Итог тот же, что у закрытой атаки раунда 1: reformulation-tracker пишет «Пользователь
# КОРРЕКТИРУЕТ» на реплику, где собеседник ПЕРЕСКАЗЫВАЕТ чужие слова и с ними не
# соглашается. Ложные BACKWARD копятся в cascading-events-<sid>.jsonl, а три записи там
# поднимают класс B состояния distressed — ошибка не остаётся в границах одного хода.

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

assert_stripped() {  # $1=текст $2=маркер, которого быть НЕ должно $3=имя
    local got; got=$(user_own_speech "$1")
    if grep -qF "$2" <<< "$got"; then
        bad "$3" "чужой маркер '$2' остался в собственной речи: ${got:0:80}"
    else ok; fi
}

# t0 — контроль: ASCII-кавычка вырезается, страж раунда 1 на месте
assert_stripped 'он ответил "это не совсем так", но по-моему всё верно' \
    "не совсем" "t0 ascii quote stripped"

# t1 — АТАКА: те же слова в «ёлочках» проходят насквозь
assert_stripped 'он ответил «это не совсем так», но по-моему всё верно' \
    "не совсем" "t1 guillemets leak"

# t2 — АТАКА: типографские “лапки” (копирование из веба) — то же самое
assert_stripped 'он ответил “это не совсем так”, но по-моему всё верно' \
    "не совсем" "t2 curly quotes leak"

# t3 — АТАКА: одинарные ‘лапки’
assert_stripped 'он ответил ‘это не совсем так’, но по-моему всё верно' \
    "не совсем" "t3 single curly quotes leak"

# t4 — та же дыра на оси состояния: чужая жалоба в «ёлочках» поднимает stuck
ITR_LIB="$HOOKS_DIR/intrusiveness-state-lib.sh"
if [ -f "$ITR_LIB" ]; then
    TMP=$(mktemp -d)
    export ITR_STATE_DIR="$TMP"
    export STATE_DIR="$TMP"
    # shellcheck source=/dev/null
    source "$ITR_LIB" 2>/dev/null || true
    if command -v itr_compute_state >/dev/null 2>&1; then
        st=$(itr_compute_state "" 'коллега жалуется «опять не работает сборка», а у меня всё собирается' 2>/dev/null)
        case "$st" in
            stuck*) bad "t4 state from foreign guillemets" "чужая жалоба дала состояние: $st" ;;
            *) ok ;;
        esac
    fi
fi

# t5 — сквозной: хук объявляет коррекцию на пересказе чужих слов
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    TMP2=$(mktemp -d); mkdir -p "$TMP2/state"
    out=$(jq -nc --arg s r3q1 --arg p 'он ответил «это не совсем так», но по-моему всё верно' \
        '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP2/state" bash "$HOOK" 2>/dev/null)
    if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
        bad "t5 hook fires BACKWARD on retold foreign speech" "хук объявил коррекцию"
    else ok; fi
fi

echo ""
echo "attack r3 typographic-quotes: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
