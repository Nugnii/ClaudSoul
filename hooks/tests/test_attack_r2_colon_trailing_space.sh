#!/usr/bin/env bash
# test_attack_r2_colon_trailing_space.sh — АТАКА: хвостовой пробел после двоеточия
# выключает стража зачина-подписи.
#
# Прошлый раунд закрыл ровно этот вход, но только для одного невидимого байта:
# `tr -d '\r'` снял CR из CRLF. Шаблон остался прежним — `case "$_uos_first" in *:)`,
# то есть требует, чтобы строка КОНЧАЛАСЬ двоеточием. Любой другой невидимый хвост
# ведёт себя как CR вёл до починки: пробел, табуляция, NBSP (U+00A0), zero-width
# space (U+200B). Пробел после двоеточия — не экзотика, а самый обычный след
# копирования и привычки набора.
#
# Итог тот же, что у закрытой атаки: пересылка целиком уходит потребителям как
# собственная речь собеседника, чужие маркеры коррекции порождают BACKWARD.
# Один и тот же текст даёт разный вердикт из-за байта, которого не видно.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
TMP=$(mktemp -d)
mkdir -p "$TMP/state"

HDR="из соседней сессии:"
BODY=$(awk 'BEGIN { for (i = 0; i < 12; i++) print "рецензент пишет что тут не совсем верно сделано и надо иначе." }')

check() {  # $1=имя $2=хвост первой строки
    local txt own
    txt="${HDR}${2}
${BODY}"
    own=$(user_own_speech "$txt")
    if grep -qF "не совсем" <<< "$own"; then
        FAIL=$((FAIL + 1))
        echo "FAIL [$1]: чужой маркер протёк как собственная речь (${#own} символов вместо зачина)"
    else
        PASS=$((PASS + 1))
    fi
}

# t0 — контроль: чистое двоеточие страж ловит
check "t0 контроль: голое двоеточие" ""
# t1..t4 — АТАКА: невидимый хвост выключает стража
check "t1 хвостовой пробел" " "
check "t2 хвостовая табуляция" "$(printf '\t')"
check "t3 хвостовой NBSP" "$(printf '\xc2\xa0')"
check "t4 хвостовой zero-width space" "$(printf '\xe2\x80\x8b')"

# t5 — сквозной: хук выдаёт BACKWARD на чужом тексте
if command -v jq >/dev/null 2>&1; then
    out=$(jq -n --arg s "r2c" --arg p "${HDR} 
${BODY}" '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>&1)
    if grep -qF "BACKWARD" <<< "$out"; then
        FAIL=$((FAIL + 1))
        echo "FAIL [t5 сквозной]: пересылка с хвостовым пробелом дала BACKWARD"
    else PASS=$((PASS + 1)); fi
else
    echo "SKIP t5: jq недоступен"
fi

echo ""
echo "attack r2 colon-trailing-space: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
