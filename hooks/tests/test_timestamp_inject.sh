#!/usr/bin/env bash
# test_timestamp_inject.sh — инжект времени: формат, валидный JSON, живучесть.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/timestamp-inject.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_empty() {
    if [ -z "$1" ]; then ok; else bad "$2" "expected empty, got: $1"; fi
}
assert_contains() {
    if grep -qE "$2" <<< "$1"; then ok; else bad "$3" "не найдено «$2» в: $1"; fi
}

# --- T1: обычный вызов → валидный JSON с additionalContext ---
OUT=$(printf '{"session_id":"sid1","user_prompt":"привет"}' | bash "$SCRIPT" 2>/dev/null)
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    && ok || bad "T1" "нет additionalContext: $OUT"

# --- T2: таймштамп в формате YYYY-MM-DD HH:MM + маркер 🕐 ---
CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
assert_contains "$CTX" '🕐 [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' "T2"

# --- T3: инжектированное время — реальное (совпадает с date до минуты либо соседней) ---
NOW_MIN=$(date '+%Y-%m-%d %H:%M')
PREV_MIN=$(date -v-1M '+%Y-%m-%d %H:%M' 2>/dev/null || date -d '1 minute ago' '+%Y-%m-%d %H:%M' 2>/dev/null)
{ grep -qF "$NOW_MIN" <<< "$CTX" || grep -qF "${PREV_MIN:-$NOW_MIN}" <<< "$CTX"; } \
    && ok || bad "T3" "время инжекта ($CTX) не совпало с системным ($NOW_MIN)"

# --- T6: инжект НАЗЫВАЕТ единицу — блок хода, и запрещает повтор (12 сентября 2026) ---
# Повод измерен на себе: текст говорил «начни ответ этим таймштампом», а правило требует
# ПЕРВЫЙ текстовый блок хода. Две единицы у одного требования, и исполнялась та, что
# приходит чаще, — за три хода одной сессии страж насчитал 7, 13 и 6 шапок при одном
# инжекте на ход. Без этой ноги формулировка уплывёт обратно молча: она живёт в строке
# кода, которую никто не сверял.
assert_contains "$CTX" 'ПЕРВЫЙ текстовый блок хода' "T6"
assert_contains "$CTX" 'не повторять' "T6b"

# --- T4: пустой stdin → не падает, JSON валиден ---
OUT=$(printf '' | bash "$SCRIPT" 2>/dev/null); RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | jq empty >/dev/null 2>&1 \
    && ok || bad "T4" "rc=$RC out=$OUT"

# --- T5: тишина при деградации — без jq хук молчит, не падает ---
NOBIN=$(mktemp -d)
OUT=$(printf '{"user_prompt":"x"}' | env PATH="$NOBIN" /bin/bash "$SCRIPT" 2>/dev/null); RC=$?
rmdir "$NOBIN" 2>/dev/null || true
assert_empty "$OUT" "T5: без jq — тишина"
if [ "$RC" -eq 0 ]; then ok; else bad "T5b" "rc=$RC, ожидался 0"; fi

echo "test_timestamp_inject: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
