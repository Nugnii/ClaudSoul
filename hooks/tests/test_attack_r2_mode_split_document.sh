#!/usr/bin/env bash
# test_attack_r2_mode_split_document.sh — АТАКА: один и тот же turn получает
# противоположные вердикты у двух потребителей из-за режима strict/soft.
#
# Режим soft снимает признак вставленного ДОКУМЕНТА (заголовки `##`, разделитель
# таблицы). Комментарий в коде объясняет это замером: «на канале сигналов состояния
# strict и soft дают одно и то же число срабатываний (29 из 33)... признак там не
# ловит ничего сверх зачина и цитат». Вход ниже — контрпример: пересланный отчёт
# длиннее 500 символов, БЕЗ зачина-подписи и БЕЗ цитат, с одними заголовками `##`.
#
# Результат на одной и той же реплике:
#   reformulation-tracker / itr-event-detector (strict) → «собственной речи нет вовсе»;
#   intrusiveness-classify-lib (soft)                   → «собеседник в состоянии stuck».
# Turn одновременно не является речью собеседника и является его буксованием. Второе
# читает 4D gate и режет вмешательства на весь ход по словам, которых собеседник не писал.
#
# Это НЕ шапка D89: там короткая вставка с зачином-двоеточием, здесь ≥ 500 символов,
# двоеточия в первой строке нет, а признак документа в turn'е ЕСТЬ и strict его видит.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
ITR="$HOOKS_DIR/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
[ -f "$ITR" ] || { echo "FAIL: $ITR not found"; exit 1; }

TMP=$(mktemp -d)
export ITR_STATE_DIR="$TMP"
# shellcheck source=/dev/null
source "$LIB"
# shellcheck source=/dev/null
source "$ITR"

PASS=0
FAIL=0

DOC="# Отчёт прогона

## Результат

Сборка не работает, опять та же ошибка, ещё раз запускали — тот же результат.
$(awk 'BEGIN { for (i = 0; i < 12; i++) print "тело пересланного отчёта строка номер и ещё немного текста для длины." }')"

LEN=$(printf '%s' "$DOC" | LC_ALL=C.UTF-8 wc -m | tr -d '[:space:]')
[ "${LEN:-0}" -ge 500 ] || { echo "FAIL: фикстура короче 500 символов ($LEN) — тест не о том"; exit 1; }

STRICT=$(user_own_speech "$DOC")
SOFT=$(user_own_speech "$DOC" soft)
STATE=$(itr_compute_state "" "$DOC" | cut -d'|' -f1)

# t0 — контроль: strict опознаёт документ и молчит
if [ -z "$STRICT" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [t0 контроль: strict обязан опознать документ]: '${STRICT:0:60}'"; fi

# t1 — АТАКА: soft отдаёт тот же документ целиком
if [ -z "$SOFT" ]; then PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [t1 soft пропускает документ, который strict опознал]: ${#SOFT} символов, начало '${SOFT:0:40}'"
fi

# t2 — АТАКА: расхождение доходит до состояния
if [ -z "$STRICT" ] && [ "$STATE" = "stuck" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [t2 противоречие потребителей]: strict='речи нет', а состояние '$STATE' — по тому же тексту"
else PASS=$((PASS + 1)); fi

# t3 — граница: своя жалоба с приложенным размеченным куском обязана остаться слышимой
#      (ради этого soft и заведён — чинить нельзя простым возвратом strict везде)
OWN_WITH_DOC="опять не работает, третий раз

## лог

сборка падает"
got=$(itr_compute_state "" "$OWN_WITH_DOC" | cut -d'|' -f1)
if [ "$got" = "stuck" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [t3 граница: своя жалоба + размеченный кусок]: ожидалось stuck, получено '$got'"; fi

rm -rf "$TMP"
echo ""
echo "attack r2 mode-split-document: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
