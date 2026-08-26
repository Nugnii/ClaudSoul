#!/usr/bin/env bash
# test_inquiry_gap.sh — вопрос ≠ поручение: срабатывание на короткий вскрывающий
# вопрос, тишина на поручениях, вставках, системных уведомлениях и в distressed.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/inquiry-gap.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0; FAIL=0
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: '$2' not in: $1"; fi
}
assert_empty() {
    if [ -z "$1" ] || [ "$1" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: expected empty, got: $1"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

run_with() {
    printf '{"session_id":"%s","user_prompt":%s}' "$1" "$(printf '%s' "$2" | jq -Rs .)" | \
        STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null
}

# --- T1: короткий вскрывающий вопрос → fire с порядком ответ→разбор→слово ---
OUT=$(run_with s1 "как это работает? мне постоянно нужно помнить идёт фаза или нет?")
assert_contains "$OUT" "вопрос, не поручение" "T1: вопрос детектирован"
assert_contains "$OUT" "почему этого нет" "T1b: требование разбора"
assert_contains "$OUT" "после явного слова" "T1c: стройка только после слова"

# --- T2: поручение → silent ---
OUT=$(run_with s2 "делай")
assert_empty "$OUT" "T2: поручение игнорируется"
OUT=$(run_with s2 "почини парсер и добавь тест")
assert_empty "$OUT" "T2b: императив без вопроса игнорируется"

# --- T3: вопросительное слово без «?» → silent (узкий сигнал) ---
OUT=$(run_with s3 "расскажи как это работает")
assert_empty "$OUT" "T3: без знака вопроса тихо"

# --- T4: длинное сообщение с «?» внутри вставки → silent ---
LONG=$(printf 'вот лог ошибки: %0.s-' $(seq 1 90); printf ' why? '; printf '%0.s-' $(seq 1 350))
OUT=$(run_with s4 "$LONG")
assert_empty "$OUT" "T4: вопрос внутри длинной вставки игнорируется"

# --- T5: системное уведомление → silent ---
OUT=$(run_with s5 "[SYSTEM NOTIFICATION - NOT USER INPUT] как это работает?")
assert_empty "$OUT" "T5: системный текст игнорируется"

# --- T6: distressed → silent (AP2) ---
printf '{"state_axis":"distressed"}' > "$STATE_DIR/intrusiveness-s6.json"
OUT=$(run_with s6 "почему это не работает?")
assert_empty "$OUT" "T6: distressed глушит инжект"

# --- T7: повторный вопрос в той же сессии → снова fire (постоянный механизм) ---
OUT=$(run_with s1 "зачем тут второй маркер?")
assert_contains "$OUT" "вопрос, не поручение" "T7: без throttle"

# --- T8: без session_id → тихий выход ---
OUT=$(printf '{"user_prompt":"почему нет?"}' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T8: без session_id тихо"

echo "test_inquiry_gap: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
