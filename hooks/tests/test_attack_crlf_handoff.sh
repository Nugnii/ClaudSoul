#!/usr/bin/env bash
# test_attack_crlf_handoff.sh — АТАКА: перевод строки CRLF выключает стража зачина.
#
# Страж пересылки опознаёт зачин по шаблону `case "$_uos_first" in *:)`. Если текст
# пришёл с виндовыми переводами строк, первая строка кончается на `:\r`, шаблон `*:`
# не совпадает, и вся пересылка уходит потребителям как собственная речь собеседника.
# Ни один из последующих фильтров (```, `>`, `##`, таблица) чистую пересылку без
# markdown не ловит — именно её и должен был поймать зачин.
#
# Ровно тот же текст с LF отсекается правильно: вердикт зависит от невидимого байта.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/hook-input-lib.sh"
HOOK="$(cd "$(dirname "$0")/.." && pwd)/reformulation-tracker.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0

TMP=$(mktemp -d)
mkdir -p "$TMP/state"

HDR="из соседней сессии:"
BODY=$(awk 'BEGIN { for (i = 0; i < 12; i++) print "рецензент пишет что тут не совсем верно сделано и надо иначе." }')
LF_TXT="$HDR
$BODY"
CRLF_TXT=$(printf '%s\r\n%s' "$HDR" "$(printf '%s' "$BODY" | sed -e 's/$/\r/')")

# t1 — контроль: с LF тело пересылки отсекается
if grep -qF "не совсем" <<< "$(user_own_speech "$LF_TXT")"; then
    FAIL=$((FAIL + 1)); echo "FAIL [t1 LF control]: тело пересылки не отсечено"
else PASS=$((PASS + 1)); fi

# t2 — с CRLF тот же текст обязан вести себя так же
own=$(user_own_speech "$CRLF_TXT")
if grep -qF "не совсем" <<< "$own"; then
    FAIL=$((FAIL + 1))
    echo "FAIL [t2 CRLF handoff stripped]: чужой маркер прошёл, вывод ${#own} символов вместо зачина"
else PASS=$((PASS + 1)); fi

# t3 — сквозной эффект: хук объявляет коррекцию по чужому тексту
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    out=$(jq -n --arg p "$CRLF_TXT" '{session_id:"atk-crlf",prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
    if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
        FAIL=$((FAIL + 1))
        echo "FAIL [t3 no false BACKWARD on CRLF handoff]: хук записал коррекцию по чужому тексту"
    else PASS=$((PASS + 1)); fi
fi

rm -rf "$TMP"
echo ""
echo "attack crlf-handoff: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
