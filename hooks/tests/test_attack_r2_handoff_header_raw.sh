#!/usr/bin/env bash
# test_attack_r2_handoff_header_raw.sh — АТАКА: ветка зачина-подписи печатает строку
# СЫРОЙ, в обход вырезания чужой речи внутри строки.
#
# В функции два независимых стража, и они стоят на взаимоисключающих путях:
#   1) зачин-подпись — `printf '%s\n' "$_uos_first"; return 0` — выходит СРАЗУ;
#   2) вырезание чужой речи в строке (gsub по "..." и `...`) — живёт в awk НИЖЕ,
#      то есть на пути, до которого первая ветка не доходит.
# Значит дыра каждого стража ровно там, где срабатывает другой: стоит пересылке
# перевалить за 500 символов, и заголовок с чужой прямой речью в кавычках уходит
# потребителям нетронутым — хотя тот же заголовок в коротком turn'е чистится.
#
# Форма заголовка обыденная: «он ответил "не совсем так":» + приложенное письмо.
# Итог — reformulation-tracker пишет «Пользователь КОРРЕКТИРУЕТ» на реплику, где
# собеседник ПЕРЕСКАЗЫВАЕТ чужие слова. Ложные BACKWARD дополнительно копятся в
# cascading-events-<sid>.jsonl, а три записи там поднимают класс B состояния
# distressed — ложный сигнал не остаётся в границах одного хода.

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

HDR='он ответил "не совсем так":'
BODY=$(awk 'BEGIN { for (i = 0; i < 12; i++) print "тело пересланного письма строка номер и ещё немного текста для длины." }')
LONG="${HDR}
${BODY}"
SHORT="${HDR} коротко"

# t0 — контроль: в коротком turn'е чужая речь в кавычках вырезается
own=$(user_own_speech "$SHORT")
if grep -qF "не совсем" <<< "$own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [t0 контроль: gsub обязан вырезать чужую речь в короткой реплике]"
else PASS=$((PASS + 1)); fi

# t1 — АТАКА: тот же заголовок в длинном turn'е печатается сырым
own=$(user_own_speech "$LONG")
if grep -qF "не совсем" <<< "$own"; then
    FAIL=$((FAIL + 1))
    echo "FAIL [t1 заголовок зачина печатается в обход gsub]: получено '${own}'"
else PASS=$((PASS + 1)); fi

# t2 — то же для backtick-цитаты
own=$(user_own_speech 'он написал `не совсем то`:
'"${BODY}")
if grep -qF "не совсем" <<< "$own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [t2 backtick-цитата в заголовке зачина не вырезана]: '${own}'"
else PASS=$((PASS + 1)); fi

# t3 — сквозной: хук выдаёт BACKWARD на пересказе чужих слов
if command -v jq >/dev/null 2>&1; then
    out=$(jq -n --arg s "r2h" --arg p "$LONG" '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>&1)
    if grep -qF "BACKWARD" <<< "$out"; then
        FAIL=$((FAIL + 1))
        echo "FAIL [t3 сквозной]: пересказ чужих слов классифицирован как коррекция собеседника"
    else PASS=$((PASS + 1)); fi
else
    echo "SKIP t3: jq недоступен"
fi

echo ""
echo "attack r2 handoff-header-raw: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
