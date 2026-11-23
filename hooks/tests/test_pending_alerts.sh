#!/usr/bin/env bash
# test_pending_alerts.sh — тесты pending-alerts-surface.sh (видимый канал алертов).
# Покрытие: показ очереди через additionalContext, очистка после показа,
# тишина при пустой/отсутствующей очереди, валидность JSON.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pending-alerts-surface.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
assert_contains(){ case "$1" in *"$2"*) ok "$3";; *) no "$3";; esac; }
assert_empty(){ [ -z "$1" ] && ok "$2" || no "$2"; }
assert_silent(){ { [ -z "$1" ] && [ "$2" = 0 ]; } && ok "$3" || no "$3"; }

command -v jq >/dev/null 2>&1 || { echo "jq required for tests"; exit 2; }

TMP=$(mktemp -d)
export CLAUDSOUL_STATE_DIR="$TMP"
QUEUE="$TMP/pending-alerts.txt"

# T1-T3: непустая очередь → emit additionalContext с обоими алертами
printf '%s\n' '⚠️ В сессии были ошибки — рассмотри /learn.' '🧱 пора /compile' > "$QUEUE"
OUT=$(printf '{"prompt":"hi"}' | bash "$HOOK")
echo "$OUT" | jq -e '.hookSpecificOutput.hookEventName=="UserPromptSubmit"' >/dev/null 2>&1 \
  && ok "T1 hookEventName=UserPromptSubmit" || no "T1 hookEventName"
CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
assert_contains "$CTX" "были ошибки" "T2 additionalContext содержит алерт ошибок"
assert_contains "$CTX" "пора /compile" "T3 additionalContext содержит нудж compile"

# T4: очередь очищена после показа (показ ровно один раз)
[ ! -s "$QUEUE" ] && ok "T4 очередь очищена после показа" || no "T4 очередь не очищена"

# T5: повторный вызов на пустой очереди → тишина
OUT2=$(printf '{"prompt":"hi"}' | bash "$HOOK")
assert_empty "$OUT2" "T5 пустая очередь → тишина"

# T6: нет файла очереди → тишина, exit 0
rm -f "$QUEUE"
OUT3=$(printf '{}' | bash "$HOOK"); rc=$?
assert_silent "$OUT3" "$rc" "T6 нет очереди → тишина, exit 0"

# T7: выход — валидный JSON
printf 'один алерт\n' > "$QUEUE"
printf '{}' | bash "$HOOK" | jq -e . >/dev/null 2>&1 && ok "T7 выход — валидный JSON" || no "T7 невалидный JSON"

rm -rf "$TMP"
echo ""
echo "  RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
exit $?
