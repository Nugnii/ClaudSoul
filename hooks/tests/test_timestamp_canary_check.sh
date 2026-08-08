#!/usr/bin/env bash
# test_timestamp_canary_check.sh — Stop-страж канарейки: молчит на здоровом
# ответе, алертит при пропаже/протухании таймштампа. Фикстурный транскрипт.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/timestamp-canary-check.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in: $haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

N=0
make_transcript() {
    N=$((N + 1))
    local f="$TMP/transcript-$N.jsonl"
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg t "$1" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    printf '%s' "$f"
}

run_with() {
    printf '{"session_id":"sid","transcript_path":"%s"}' "$1" | \
        TIMESTAMP_INJECT_PATH="${2:-$HOOKS_DIR/timestamp-inject.sh}" bash "$SCRIPT" 2>/dev/null
}

NOW_TS=$(date '+%Y-%m-%d %H:%M')

# --- T1: ответ начат свежим таймштампом → молчит ---
F=$(make_transcript "🕐 $NOW_TS CEST

Готово, тесты зелёные.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1: здоровый ответ — тишина"

# --- T2: ответ без таймштампа → алерт с systemMessage ---
F=$(make_transcript "Готово, тесты зелёные, коммит создан.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T2: пропажа детектирована"
assert_contains "$OUT" "systemMessage" "T2b: алерт виден собеседнику"

# --- T3: протухший таймштамп (сутки назад) → алерт ---
STALE=$(date -v-1d '+%Y-%m-%d %H:%M' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d %H:%M' 2>/dev/null)
F=$(make_transcript "🕐 $STALE CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "протухло" "T3: свежесть проверяется"

# --- T4: таймштамп не в первой строке → алерт (правило: НАЧИНАТЬ с него) ---
F=$(make_transcript "Готово.

🕐 $NOW_TS CEST")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T4: таймштамп не в начале = пропажа"

# --- T5: механизм инжекта не задеплоен → тишина (другой класс проблемы) ---
F=$(make_transcript "Готово без таймштампа.")
OUT=$(run_with "$F" "$TMP/no-such-injector.sh")
assert_empty "$OUT" "T5: без инжектора страж молчит"

# --- T6: нет transcript_path → тихий выход ---
OUT=$(printf '{"session_id":"sid"}' | bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T6: без транскрипта тихий выход"

# --- T7/T8: ход с промежуточными репликами перед tool-вызовами ---
# Проверяется ПОСЛЕДНИЙ текстовый блок (собственно ответ), а не первый:
# промежуточная narration таймштампа не несёт и ответом не считается.
make_transcript_multi() {
    N=$((N + 1))
    local f="$TMP/transcript-$N.jsonl"
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    local t
    for t in "$@"; do
        jq -nc --arg t "$t" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    done
    printf '%s' "$f"
}

F=$(make_transcript_multi "Смотрю детектор." "🕐 $NOW_TS CEST

Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T7: промежуточная реплика без таймштампа не даёт ложного алерта"

F=$(make_transcript_multi "🕐 $NOW_TS CEST

Смотрю детектор." "Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T8: таймштамп только в промежуточной — пропажа в ответе"

echo "test_timestamp_canary_check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
