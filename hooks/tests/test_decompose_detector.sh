#!/usr/bin/env bash
# test_decompose_detector.sh — v1.5.4-alpha: multi-step detection.
# Изоляция через STATE_DIR env var.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/decompose-detector.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

run_with() {
    local sid="$1" prompt="$2"
    printf '{"session_id":"%s","user_prompt":%s}' "$sid" "$(printf '%s' "$prompt" | jq -Rs .)" | \
        STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null
}

# --- T1: короткий prompt → skip (<100 chars) ---
OUT=$(run_with "sid1" "сделай X и Y")
assert_empty "$OUT" "T1: короткий prompt игнорируется"

# --- T2: long prompt без шагов → skip ---
LONG_NO_STEPS="Это длинный текст без явных признаков шагов. Просто одно большое задание на обсуждение какой-то темы без перечислений и без списков. Рассуждение общее."
OUT=$(run_with "sid2" "$LONG_NO_STEPS")
assert_empty "$OUT" "T2: long prompt без шагов игнорируется"

# --- T3: 4+ нумерованных шага → fire ---
NUMBERED="Нужно сделать большой рефакторинг:
1. Прочитать модуль auth
2. Переписать middleware
3. Обновить тесты
4. Проверить интеграции
5. Запустить CI"
OUT=$(run_with "sid3" "$NUMBERED")
assert_contains "$OUT" "Multi-step detected" "T3: 4+ нумерованных шагов fire"
assert_contains "$OUT" "/decompose" "T3b: упомянут скилл"

# --- T4: 4+ буллета → fire ---
BULLETS="План рефакторинга большой:
- сначала прочитать
- потом переписать
- затем проверить
- и наконец запустить тесты"
OUT=$(run_with "sid4" "$BULLETS")
assert_contains "$OUT" "Multi-step detected" "T4: 4+ буллетов fire (+коннекторы усиливают)"

# --- T5: коннекторы без списка → fire ---
CONNECTORS="Сначала прочитай файл. Затем переделай логику. Потом запусти тесты. После этого закоммить результат. И далее запушь на origin."
OUT=$(run_with "sid5" "$CONNECTORS")
assert_contains "$OUT" "Multi-step detected" "T5: 4+ коннекторов fire"

# --- T6: уже упомянут /decompose → skip ---
MENTIONED="У меня задача большая. 1. одно 2. два 3. три 4. четыре. Может стоит /decompose применить сначала?"
OUT=$(run_with "sid6" "$MENTIONED")
assert_empty "$OUT" "T6: /decompose уже упомянут — skip"

# --- T7: упомянут «разбей» → skip ---
RAZBEI="У меня список: 1. одно 2. два 3. три 4. четыре 5. пять. Разбей это пожалуйста на этапы."
OUT=$(run_with "sid7" "$RAZBEI")
assert_empty "$OUT" "T7: «разбей» уже упомянут — skip"

# --- T7b: «Разбей» с заглавной + 4 нумерованных шага → skip ---
# Без T7b guard 2 на кириллице не проверен: в T7 список в одну строку, шаги не считаются,
# и skip получается по нулю сигналов, а не по сработавшему guard.
RAZBEI_CAPS="Разбей эту большую задачу на понятные этапы, пожалуйста:
1. прочитать модуль
2. переписать логику
3. обновить тесты
4. запустить проверки"
OUT=$(run_with "sid7b" "$RAZBEI_CAPS")
assert_empty "$OUT" "T7b: «Разбей» с заглавной — skip"

# --- T8: per-session dedup — второй раз не fire ---
OUT1=$(run_with "sid8" "$NUMBERED")
assert_contains "$OUT1" "Multi-step detected" "T8a: первый fire"
OUT2=$(run_with "sid8" "$NUMBERED")
assert_empty "$OUT2" "T8b: второй раз в той же сессии — skip (dedup)"

# --- T9: разные сессии — каждая fire отдельно ---
OUT=$(run_with "sid9-a" "$NUMBERED")
assert_contains "$OUT" "Multi-step detected" "T9a: sid9-a fire"
OUT=$(run_with "sid9-b" "$NUMBERED")
assert_contains "$OUT" "Multi-step detected" "T9b: sid9-b fire (разные сессии независимы)"

# --- T10: state=focus → skip ---
STATE_FILE_F="$STATE_DIR/intrusiveness-sid10.json"
printf '{"state_axis":"focus"}' > "$STATE_FILE_F"
OUT=$(run_with "sid10" "$NUMBERED")
assert_empty "$OUT" "T10: state=focus — skip"

# --- T11: state=stuck → skip ---
STATE_FILE_S="$STATE_DIR/intrusiveness-sid11.json"
printf '{"state_axis":"stuck"}' > "$STATE_FILE_S"
OUT=$(run_with "sid11" "$NUMBERED")
assert_empty "$OUT" "T11: state=stuck — skip"

# --- T12: state=idle → fire ---
STATE_FILE_I="$STATE_DIR/intrusiveness-sid12.json"
printf '{"state_axis":"idle"}' > "$STATE_FILE_I"
OUT=$(run_with "sid12" "$NUMBERED")
assert_contains "$OUT" "Multi-step detected" "T12: state=idle — fire"

# --- T13: state=exploration → fire ---
STATE_FILE_E="$STATE_DIR/intrusiveness-sid13.json"
printf '{"state_axis":"exploration"}' > "$STATE_FILE_E"
OUT=$(run_with "sid13" "$NUMBERED")
assert_contains "$OUT" "Multi-step detected" "T13: state=exploration — fire"

# --- T14: пустой prompt → skip ---
OUT=$(printf '{"session_id":"sid14","user_prompt":""}' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T14: пустой prompt — skip"

# --- T15: отсутствует session_id → skip ---
OUT=$(printf '{"user_prompt":"%s"}' "$NUMBERED" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T15: нет session_id — skip"

# --- T16: порог настраиваемый через DECOMPOSE_THRESHOLD ---
THREE_STEPS="План такой:
1. первое
2. второе
3. третье
И нужно это сделать аккуратно чтобы не сломать существующий код."
OUT=$(DECOMPOSE_THRESHOLD=3 run_with "sid16" "$THREE_STEPS")
assert_contains "$OUT" "Multi-step detected" "T16: порог 3 — 3 шагов достаточно"

# --- T17: порог по умолчанию 4 — 3 шагов НЕ достаточно ---
OUT=$(run_with "sid17" "$THREE_STEPS")
assert_empty "$OUT" "T17: 3 шагов < порога 4 — skip"

# --- T18: output — валидный JSON ---
OUT=$(run_with "sid18" "$NUMBERED")
echo "$OUT" | jq -e . >/dev/null 2>&1 && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T18]: output не валидный JSON"; echo "$OUT"; }

# --- T19: output содержит hookSpecificOutput.additionalContext ---
OUT=$(run_with "sid19" "$NUMBERED")
HAS_CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [ -n "$HAS_CTX" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T19]: hookSpecificOutput.additionalContext отсутствует"; fi

# --- T20: hookEventName = UserPromptSubmit ---
OUT=$(run_with "sid20" "$NUMBERED")
EVT=$(echo "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
if [ "$EVT" = "UserPromptSubmit" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T20]: hookEventName = '$EVT'"; fi

# --- Router: ветка решений → /grilling (v1.x) ---
VAGUE="Хочу спроектировать новый модуль синхронизации, но не уверен как лучше его сделать и какой вариант хранилища выбрать. Стоит ли вообще, продумай архитектуру и как организовать."

# --- T21: расплывчатый/решения → /grilling ---
OUT=$(run_with "sid21" "$VAGUE")
assert_contains "$OUT" "/grilling" "T21: открытые решения → grilling"
assert_contains "$OUT" "Открытые решения" "T21b: заголовок ветки решений"

# --- T22: взаимоисключение — ветка решений НЕ содержит decompose-подсказку ---
if grep -Fq "Multi-step detected" <<< "$OUT"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T22]: grilling-вывод содержит и decompose-подсказку (двойной инжект)"
else PASS=$((PASS + 1)); fi

# --- T23: смешанный, шагов больше решений → /decompose (перевес шагов) ---
MIXED="Большой рефакторинг:
1. Прочитать модуль auth
2. Переписать middleware
3. Обновить тесты
4. Проверить интеграции
Но не уверен, с какого начать."
OUT=$(run_with "sid23" "$MIXED")
assert_contains "$OUT" "/decompose" "T23: шагов > решений → decompose"
if grep -Fq "/grilling" <<< "$OUT"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T23b]: decompose-вывод содержит и grilling (двойной инжект)"
else PASS=$((PASS + 1)); fi

# --- T24: упомянут «грилинг» → skip (guard 2 расширение) ---
# Скилл зовётся `grilling`, но в речи остаётся «грилинг» — guard обязан узнавать оба
# написания, иначе после переименования покрытым остался бы один путь из двух.
GRILL_MENTIONED="$VAGUE Может стоит грилинг применить сначала?"
OUT=$(run_with "sid24" "$GRILL_MENTIONED")
assert_empty "$OUT" "T24: «грилинг» уже упомянут — skip"

# --- T24b: упомянут «grilling» латиницей → тот же skip ---
GRILL_LAT="$VAGUE Может стоит /grilling применить сначала?"
OUT=$(run_with "sid24b" "$GRILL_LAT")
assert_empty "$OUT" "T24b: «grilling» латиницей уже упомянут — skip"

# --- T24c/T24d: назван adversary → рекомендации грилинга быть не должно ---
# Список guard 2 ведётся по ИМЕНАМ инструментов. До 28 августа 2026 там стоял только
# триггер «прожар», а имени противника не было ни в одном написании: «прогони adversary»
# получало совет вызвать то, что уже названо. Проверяются оба написания — скилл зовётся
# латиницей, собеседник говорит по-русски.
ADV_LAT="$VAGUE Может стоит adversary прогнать сначала?"
OUT=$(run_with "sid24c" "$ADV_LAT")
assert_empty "$OUT" "T24c: «adversary» уже упомянут — skip"

ADV_RU="$VAGUE Может стоит противника прогнать сначала?"
OUT=$(run_with "sid24d" "$ADV_RU")
assert_empty "$OUT" "T24d: «противник» уже упомянут — skip"

# --- T25: порог решений настраивается через GRILL_THRESHOLD ---
ONE_DECISION="Есть идея нового модуля синхронизации данных, но пока совсем не уверен, как лучше её реализовать в текущей архитектуре проекта, нужен твой совет по подходу."
OUT=$(GRILL_THRESHOLD=1 run_with "sid25" "$ONE_DECISION")
assert_contains "$OUT" "/grilling" "T25: порог решений 1 — одного сигнала достаточно"

echo ""
echo "decompose-detector tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
