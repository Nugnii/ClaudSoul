#!/usr/bin/env bash
# test_fix_level_check.sh — fix-level-check.sh coverage.
#
# Хук закрывает заявку на эскалацию pattern-inside-out-blindness: детект
# пост-инцидентных текстовых фиксов («надо вынести урок», «будем осторожнее»)
# в собственном ответе агента, инжект напоминания про уровни embedded-ness.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/fix-level-check.sh"

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

assert_file_contains() {
    local file="$1" needle="$2" label="$3"
    [ -f "$file" ] || { FAIL=$((FAIL + 1)); echo "FAIL [$label]: file $file missing"; return; }
    if grep -Fq "$needle" "$file"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in $file:"; cat "$file"; fi
}

assert_file_missing() {
    local file="$1" label="$2"
    if [ ! -f "$file" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: file $file should not exist but does:"; cat "$file"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$HOME/.claude/hooks/state"
STATE_DIR="$HOME/.claude/hooks/state"

make_transcript() {
    local path="$1" user_text="$2" assistant_text="$3"
    {
        jq -cn --arg t "$user_text" \
            '{type:"user", message:{role:"user", content:[{type:"text", text:$t}]}}'
        jq -cn --arg t "$assistant_text" \
            '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}'
    } > "$path"
}

run_hook() {
    local event="$1" sid="$2" transcript="${3:-}"
    local payload
    payload=$(jq -cn \
        --arg event "$event" --arg sid "$sid" --arg tp "$transcript" \
        '{hook_event_name: $event, session_id: $sid, transcript_path: $tp}')
    printf '%s' "$payload" | bash "$SCRIPT" 2>/dev/null
}

# T1: незнакомое событие → тишина, без побочных файлов
OUT=$(run_hook "PostToolUse" "sid-t1" "")
assert_empty "$OUT" "T1: unknown event silent"
assert_file_missing "$STATE_DIR/fix-level-sid-t1.jsonl" "T1: no state file"

# T2: Stop без расшифровки → тишина
OUT=$(run_hook "Stop" "sid-t2" "")
assert_empty "$OUT" "T2: empty transcript silent"
assert_file_missing "$STATE_DIR/fix-level-sid-t2.jsonl" "T2: no state file"

# T3: чистый ответ без фраз-фиксов → тишина
TR="$TMP/t3.jsonl"
make_transcript "$TR" "вопрос" "Починил гонку в парсере, тесты зелёные, коммит собран."
OUT=$(run_hook "Stop" "sid-t3" "$TR")
assert_empty "$OUT" "T3: clean answer silent"
assert_file_missing "$STATE_DIR/fix-level-sid-t3.jsonl" "T3: no detections"

# T4: пост-инцидентная фраза-фикс → записана в pending
TR="$TMP/t4.jsonl"
make_transcript "$TR" "почему упало?" "Ошибка моя: пропустил проверку. Надо вынести урок и не повторять."
OUT=$(run_hook "Stop" "sid-t4" "$TR")
assert_empty "$OUT" "T4: Stop returns silent (no inject on Stop)"
assert_file_contains "$STATE_DIR/fix-level-sid-t4.jsonl" "надо вынести урок" "T4: phrase persisted"
assert_file_contains "$STATE_DIR/fix-level-sid-t4.jsonl" '"status":"pending"' "T4: pending status"

# T5: инжект на UserPromptSubmit + перевод в surfaced
OUT=$(run_hook "UserPromptSubmit" "sid-t4" "")
assert_contains "$OUT" "Fix-level check" "T5: reminder injected"
assert_contains "$OUT" "надо вынести урок" "T5: phrase named"
assert_contains "$OUT" "principle-knowledge-in-the-world" "T5: principle referenced"
assert_file_contains "$STATE_DIR/fix-level-sid-t4.jsonl" '"status":"surfaced"' "T5: marked surfaced"

# T6: повторный инжект не происходит
OUT=$(run_hook "UserPromptSubmit" "sid-t4" "")
assert_empty "$OUT" "T6: no re-inject after surfaced"

# T7: фраза + названный механизм → подавление (фикс уже не текстовый)
TR="$TMP/t7.jsonl"
make_transcript "$TR" "q" "Будем осторожнее: заведу хук с детекцией этого класса и тест к нему."
OUT=$(run_hook "Stop" "sid-t7" "$TR")
assert_empty "$OUT" "T7: mechanism named — silent"
assert_file_missing "$STATE_DIR/fix-level-sid-t7.jsonl" "T7: no detection with mechanism"

# T8: пометка model-generated → подавление (источник уже размечен)
TR="$TMP/t8.jsonl"
make_transcript "$TR" "q" "Учту на будущее (model-generated observation, not system-derived)."
OUT=$(run_hook "Stop" "sid-t8" "$TR")
assert_empty "$OUT" "T8: labeled output silent"
assert_file_missing "$STATE_DIR/fix-level-sid-t8.jsonl" "T8: no detection when labeled"

# T9: свёртка регистра кириллицы — «Будем осторожнее» с заглавной ловится
TR="$TMP/t9.jsonl"
make_transcript "$TR" "q" "Разобрался. Будем осторожнее в следующий раз."
OUT=$(run_hook "Stop" "sid-t9" "$TR")
assert_file_contains "$STATE_DIR/fix-level-sid-t9.jsonl" "будем осторожнее" "T9: capitalized phrase folded and caught"

# T10: дедуп — та же фраза во втором скане не дублируется
OUT=$(run_hook "Stop" "sid-t9" "$TR")
N=$(grep -c "будем осторожнее" "$STATE_DIR/fix-level-sid-t9.jsonl" 2>/dev/null || echo 0)
if [ "$N" = "1" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T10]: expected 1 record, got $N"; fi

# T11: канал PreToolUse тоже отдаёт инжект
TR="$TMP/t11.jsonl"
make_transcript "$TR" "q" "Пропустил кейс, учту на будущее."
run_hook "Stop" "sid-t11" "$TR" >/dev/null
OUT=$(run_hook "PreToolUse" "sid-t11" "")
assert_contains "$OUT" "Fix-level check" "T11: PreToolUse channel injects"
assert_contains "$OUT" '"hookEventName":"PreToolUse"' "T11: envelope names event"

# T12: несколько фраз в одном ответе — все в списке инжекта
TR="$TMP/t12.jsonl"
make_transcript "$TR" "q" "Надо запомнить: нужен чеклист перед релизом."
run_hook "Stop" "sid-t12" "$TR" >/dev/null
OUT=$(run_hook "UserPromptSubmit" "sid-t12" "")
assert_contains "$OUT" "надо запомнить" "T12: first phrase listed"
assert_contains "$OUT" "нужен чеклист" "T12: second phrase listed"

echo "test_fix_level_check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
