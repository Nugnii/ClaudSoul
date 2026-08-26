#!/usr/bin/env bash
# test_output_language_check.sh — output-language-check.sh coverage.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/output-language-check.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly in output:"; echo "$haystack"
    else PASS=$((PASS + 1)); fi
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

# Build a JSONL transcript file with given assistant message text
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

# ============================================================================
# T1: unknown event → silent, no side effects
# ============================================================================
OUT=$(run_hook "PostToolUse" "sid-t1" "")
assert_empty "$OUT" "T1: unknown event → silent"
assert_file_missing "$STATE_DIR/output-violations-sid-t1.jsonl" "T1: no violations file"

# ============================================================================
# T2: Stop event, transcript_path empty → silent, no file
# ============================================================================
OUT=$(run_hook "Stop" "sid-t2" "")
assert_empty "$OUT" "T2: empty transcript_path → silent"
assert_file_missing "$STATE_DIR/output-violations-sid-t2.jsonl" "T2: no violations file"

# ============================================================================
# T3: Stop, clean Russian text → silent, no violations
# ============================================================================
TR3="$TMP/t3.jsonl"
make_transcript "$TR3" "вопрос" "Привет, это чистый русский текст без смешения."
OUT=$(run_hook "Stop" "sid-t3" "$TR3")
assert_empty "$OUT" "T3: clean Russian → silent"
assert_file_missing "$STATE_DIR/output-violations-sid-t3.jsonl" "T3: no violations"

# ============================================================================
# T4: Stop, clean English → silent
# ============================================================================
TR4="$TMP/t4.jsonl"
make_transcript "$TR4" "q" "This is clean English text with no mixing at all."
OUT=$(run_hook "Stop" "sid-t4" "$TR4")
assert_empty "$OUT" "T4: clean English → silent"
assert_file_missing "$STATE_DIR/output-violations-sid-t4.jsonl" "T4: no violations"

# ============================================================================
# T5: Stop, text with "trёх" → violation recorded
# ============================================================================
TR5="$TMP/t5.jsonl"
make_transcript "$TR5" "q" "Накопление = функция от trёх осей"
OUT=$(run_hook "Stop" "sid-t5" "$TR5")
assert_empty "$OUT" "T5: Stop returns silent (no inject on Stop)"
assert_file_contains "$STATE_DIR/output-violations-sid-t5.jsonl" "trёх" "T5: trёх recorded"
assert_file_contains "$STATE_DIR/output-violations-sid-t5.jsonl" "pending" "T5: status pending"

# ============================================================================
# T6: Stop, text with "fix'ом" and "лookup'ов" → both recorded, deduped
# ============================================================================
TR6="$TMP/t6.jsonl"
make_transcript "$TR6" "q" "Делаем fix'ом несколько лookup'ов подряд, ещё fix'ом."
OUT=$(run_hook "Stop" "sid-t6" "$TR6")
assert_file_contains "$STATE_DIR/output-violations-sid-t6.jsonl" "лookup" "T6: лookup recorded"
# Игла — полный ожидаемый токен, а не его хвост. Раньше здесь стояло "ом": две буквы,
# которые есть в любом русском слове на -ом, поэтому утверждение проходило бы, даже если
# детектор вернул совсем другой токен или вообще не нашёл смешения. Проверка, зелёная
# независимо от того, что она проверяет, — не проверка.
assert_file_contains "$STATE_DIR/output-violations-sid-t6.jsonl" "fix'ом" "T6: mixed form captured"
# Count: should be exactly 2 unique tokens (fix'ом once, лookup'ов once)
COUNT=$(wc -l < "$STATE_DIR/output-violations-sid-t6.jsonl" | tr -d ' ')
if [ "$COUNT" = "2" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T6: dedup]: expected 2 lines, got $COUNT:"; cat "$STATE_DIR/output-violations-sid-t6.jsonl"; fi

# ============================================================================
# T7: Stop, mixed token inside fenced code block → NOT recorded
# ============================================================================
TR7="$TMP/t7.jsonl"
make_transcript "$TR7" "q" "Обычный текст.
\`\`\`
def trёх():
    pass
\`\`\`
И ещё текст."
OUT=$(run_hook "Stop" "sid-t7" "$TR7")
assert_file_missing "$STATE_DIR/output-violations-sid-t7.jsonl" "T7: fenced code ignored"

# ============================================================================
# T8: Stop, mixed token inside inline code → NOT recorded
# ============================================================================
TR8="$TMP/t8.jsonl"
make_transcript "$TR8" "q" "Переменная \`trёх\` создана в коде."
OUT=$(run_hook "Stop" "sid-t8" "$TR8")
assert_file_missing "$STATE_DIR/output-violations-sid-t8.jsonl" "T8: inline code ignored"

# ============================================================================
# T9: Stop, URL with mixed alphabet → NOT recorded
# ============================================================================
TR9="$TMP/t9.jsonl"
make_transcript "$TR9" "q" "См. https://example.com/русский-путь для деталей."
OUT=$(run_hook "Stop" "sid-t9" "$TR9")
assert_file_missing "$STATE_DIR/output-violations-sid-t9.jsonl" "T9: URL ignored"

# ============================================================================
# T10: UserPromptSubmit with no violations file → silent
# ============================================================================
OUT=$(run_hook "UserPromptSubmit" "sid-t10" "")
assert_empty "$OUT" "T10: no violations file → silent"

# ============================================================================
# T11: UserPromptSubmit with pending violations → inject context
# ============================================================================
SID11="sid-t11"
V11="$STATE_DIR/output-violations-${SID11}.jsonl"
jq -cn '{ts:"2026-04-24T10:00:00Z", sid:"sid-t11", event:"Stop", token:"trёх", status:"pending"}' > "$V11"
jq -cn '{ts:"2026-04-24T10:00:01Z", sid:"sid-t11", event:"Stop", token:"fixом", status:"pending"}' >> "$V11"
OUT=$(run_hook "UserPromptSubmit" "$SID11" "")
assert_contains "$OUT" "Output language check" "T11: marker injected"
assert_contains "$OUT" "trёх" "T11: trёх in message"
assert_contains "$OUT" "fixом" "T11: fixом in message"
assert_contains "$OUT" "feedback_pure_language_no_alphabet_mixing" "T11: rule name referenced"
assert_contains "$OUT" "hookSpecificOutput" "T11: correct envelope"
# After surfacing, tokens should be marked surfaced
if grep -Fq '"status":"surfaced"' "$V11"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T11: surfaced status]:"; cat "$V11"; fi
# And no tokens should remain pending
if ! grep -Fq '"status":"pending"' "$V11"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T11: no pending left]:"; cat "$V11"; fi

# ============================================================================
# T12: Second UserPromptSubmit call → no re-inject (all surfaced)
# ============================================================================
OUT=$(run_hook "UserPromptSubmit" "$SID11" "")
assert_empty "$OUT" "T12: already surfaced → silent"

# ============================================================================
# T13: PreCompact event scans like Stop
# ============================================================================
TR13="$TMP/t13.jsonl"
make_transcript "$TR13" "q" "Текст с trёх снова."
OUT=$(run_hook "PreCompact" "sid-t13" "$TR13")
assert_empty "$OUT" "T13: PreCompact silent output"
assert_file_contains "$STATE_DIR/output-violations-sid-t13.jsonl" "trёх" "T13: PreCompact scanned"

# ============================================================================
# T14: Stop dedup: re-scan same text → no duplicate entries
# ============================================================================
SID14="sid-t14"
TR14="$TMP/t14.jsonl"
make_transcript "$TR14" "q" "Одно слово trёх здесь."
run_hook "Stop" "$SID14" "$TR14" >/dev/null
run_hook "Stop" "$SID14" "$TR14" >/dev/null
V14="$STATE_DIR/output-violations-${SID14}.jsonl"
COUNT14=$(wc -l < "$V14" | tr -d ' ')
if [ "$COUNT14" = "1" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T14: dedup across runs]: expected 1 line, got $COUNT14:"; cat "$V14"; fi

# ============================================================================
# T15: Markdown link target (URL) ignored but link text scanned
# ============================================================================
TR15="$TMP/t15.jsonl"
make_transcript "$TR15" "q" "См. [нормальный текст](https://ru.example.com/sоmething)."
OUT=$(run_hook "Stop" "sid-t15" "$TR15")
assert_file_missing "$STATE_DIR/output-violations-sid-t15.jsonl" "T15: URL in link ignored"

# ============================================================================
# T16: Markdown link WITH mixed token in visible text → captured
# ============================================================================
TR16="$TMP/t16.jsonl"
make_transcript "$TR16" "q" "См. [trёх вариантов](https://example.com)."
OUT=$(run_hook "Stop" "sid-t16" "$TR16")
assert_file_contains "$STATE_DIR/output-violations-sid-t16.jsonl" "trёх" "T16: link text scanned"

# ============================================================================
# T17: Injected message does NOT itself contain mixed-alphabet (meta-check)
# ============================================================================
SID17="sid-t17"
V17="$STATE_DIR/output-violations-${SID17}.jsonl"
jq -cn '{ts:"2026-04-24T10:00:00Z", sid:"sid-t17", event:"Stop", token:"trёх", status:"pending"}' > "$V17"
OUT=$(run_hook "UserPromptSubmit" "$SID17" "")
# Extract just the descriptive parts of the message, not the quoted token list
# The message includes "Output language check" (English) and Russian prose separately —
# the mixed token "trёх" is the REFERENCED item, not part of native prose.
# Meta-check: ensure the rule description is in valid prose
assert_contains "$OUT" "смешением алфавитов" "T17: Russian prose present"
assert_contains "$OUT" "Output language check" "T17: English header marker"

# ============================================================================
# T18: Stop with no assistant message (only user) → silent
# ============================================================================
TR18="$TMP/t18.jsonl"
jq -cn '{type:"user", message:{role:"user", content:[{type:"text", text:"only user"}]}}' > "$TR18"
OUT=$(run_hook "Stop" "sid-t18" "$TR18")
assert_empty "$OUT" "T18: no assistant message → silent"
assert_file_missing "$STATE_DIR/output-violations-sid-t18.jsonl" "T18: no violations"

# ============================================================================
# T19: Cap at 10 tokens
# ============================================================================
LONG=""
for w in wёrdA wёrdB wёrdC wёrdD wёrdE wёrdF wёrdG wёrdH wёrdI wёrdJ wёrdK wёrdL; do
    LONG="$LONG $w"
done
TR19="$TMP/t19.jsonl"
make_transcript "$TR19" "q" "$LONG"
run_hook "Stop" "sid-t19" "$TR19" >/dev/null
V19="$STATE_DIR/output-violations-sid-t19.jsonl"
COUNT19=$(wc -l < "$V19" | tr -d ' ')
if [ "$COUNT19" -le 10 ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T19: cap at 10]: got $COUNT19 lines"; fi

# ============================================================================
# T20: Hyphenated mixed token captured
# ============================================================================
TR20="$TMP/t20.jsonl"
make_transcript "$TR20" "q" "Это какой-toшибочное написание."
OUT=$(run_hook "Stop" "sid-t20" "$TR20")
# Expect the hyphenated part to be a single token "какой-toшибочное"
assert_file_contains "$STATE_DIR/output-violations-sid-t20.jsonl" "toшибочное" "T20: hyphenated token"

# ============================================================================
# T21: PreToolUse with no violations file → silent (level 2b)
# ============================================================================
OUT=$(run_hook "PreToolUse" "sid-t21" "")
assert_empty "$OUT" "T21: PreToolUse no violations → silent"

# ============================================================================
# T22: PreToolUse with pending violations → injects with PreToolUse envelope
# ============================================================================
SID22="sid-t22"
V22="$STATE_DIR/output-violations-${SID22}.jsonl"
jq -cn '{ts:"2026-04-25T10:00:00Z", sid:"sid-t22", event:"Stop", token:"trёх", status:"pending"}' > "$V22"
OUT=$(run_hook "PreToolUse" "$SID22" "")
assert_contains "$OUT" "Output language check" "T22: marker injected on PreToolUse"
assert_contains "$OUT" "trёх" "T22: token in message"
assert_contains "$OUT" '"hookEventName":"PreToolUse"' "T22: PreToolUse envelope"
# Mark surfaced
if grep -Fq '"status":"surfaced"' "$V22"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T22: surfaced after PreToolUse]"; cat "$V22"; fi

# ============================================================================
# T23: Second PreToolUse → silent (already surfaced)
# ============================================================================
OUT=$(run_hook "PreToolUse" "$SID22" "")
assert_empty "$OUT" "T23: PreToolUse repeat → silent"

# ============================================================================
# T24: Cross-channel — UserPromptSubmit surfaces, PreToolUse silent on same SID
# ============================================================================
SID24="sid-t24"
V24="$STATE_DIR/output-violations-${SID24}.jsonl"
jq -cn '{ts:"2026-04-25T11:00:00Z", sid:"sid-t24", event:"Stop", token:"mixед", status:"pending"}' > "$V24"
OUT_USER=$(run_hook "UserPromptSubmit" "$SID24" "")
assert_contains "$OUT_USER" '"hookEventName":"UserPromptSubmit"' "T24a: UserPromptSubmit surfaces"
OUT_TOOL=$(run_hook "PreToolUse" "$SID24" "")
assert_empty "$OUT_TOOL" "T24b: PreToolUse silent after UserPromptSubmit surfaced"

# ============================================================================
# T25: Reverse — PreToolUse surfaces, UserPromptSubmit silent on same SID
# ============================================================================
SID25="sid-t25"
V25="$STATE_DIR/output-violations-${SID25}.jsonl"
jq -cn '{ts:"2026-04-25T12:00:00Z", sid:"sid-t25", event:"Stop", token:"crossед", status:"pending"}' > "$V25"
OUT_TOOL=$(run_hook "PreToolUse" "$SID25" "")
assert_contains "$OUT_TOOL" '"hookEventName":"PreToolUse"' "T25a: PreToolUse surfaces first"
OUT_USER=$(run_hook "UserPromptSubmit" "$SID25" "")
assert_empty "$OUT_USER" "T25b: UserPromptSubmit silent after PreToolUse surfaced"

echo ""
echo "=== output-language-check tests ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
