#!/usr/bin/env bash
# test_activity_flush.sh — v1.5.2-alpha: проверка activity_flush library.
# Тестирует парсинг transcript, aggregate counts, file extraction, git commit snapshot.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/activity-flush-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not found in output"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly present"
    else PASS=$((PASS + 1)); fi
}
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: basic tool_use aggregation ---
TRANSCRIPT1="$TMP/t1.jsonl"
CWD1="$TMP/p1"
mkdir -p "$CWD1"
cat > "$TRANSCRIPT1" <<'JSONL'
{"message":{"role":"user","content":[{"type":"text","text":"go"}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a.py"}}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a.py"}}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/b.sh"}}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
JSONL
activity_flush "sid-1-abcdefgh" "$TRANSCRIPT1" "$CWD1"
rc=$?
assert_eq "$rc" "0" "T1: return 0 on success"
OUT=$(cat "$CWD1/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "session sid-1-ab" "T1: session id prefix (8 chars) present"
assert_contains "$OUT" "Tool calls: 4" "T1: total tool count"
assert_contains "$OUT" "Bash:1" "T1: Bash count"
assert_contains "$OUT" "Edit:2" "T1: Edit count"
assert_contains "$OUT" "Read:1" "T1: Read count"
assert_contains "$OUT" "Files touched: a.py b.sh" "T1: basenames only (a.py b.sh in order)"

# --- Test 2: empty transcript (no tool_use) → no write ---
TRANSCRIPT2="$TMP/t2.jsonl"
CWD2="$TMP/p2"
mkdir -p "$CWD2"
cat > "$TRANSCRIPT2" <<'JSONL'
{"message":{"role":"user","content":[{"type":"text","text":"hi"}]}}
{"message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}
JSONL
activity_flush "sid-2" "$TRANSCRIPT2" "$CWD2"
rc=$?
assert_eq "$rc" "0" "T2: returns 0 even with no tools"
# File should not exist (no activity to record)
if [ -f "$CWD2/.claude-docs/session-activity.md" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [T2]: archive should not be written when no tool_use"
else
    PASS=$((PASS + 1))
fi

# --- Test 3: missing transcript → return 1 ---
activity_flush "sid-3" "$TMP/nonexistent.jsonl" "$TMP"
rc=$?
assert_eq "$rc" "1" "T3: missing transcript returns 1"

# --- Test 4: missing session_id → return 2 ---
activity_flush "" "$TRANSCRIPT1" "$CWD1"
rc=$?
assert_eq "$rc" "2" "T4: missing sid returns 2"

# --- Test 5: missing cwd → return 1 ---
activity_flush "sid-5" "$TRANSCRIPT1" "$TMP/nonexistent-dir"
rc=$?
assert_eq "$rc" "1" "T5: missing cwd returns 1"

# --- Test 6: MultiEdit file extraction ---
TRANSCRIPT6="$TMP/t6.jsonl"
CWD6="$TMP/p6"
mkdir -p "$CWD6"
cat > "$TRANSCRIPT6" <<'JSONL'
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"MultiEdit","input":{"file_path":"/multi.ts"}}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/fresh.md"}}]}}
JSONL
activity_flush "sid-6" "$TRANSCRIPT6" "$CWD6"
OUT=$(cat "$CWD6/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "MultiEdit:1" "T6: MultiEdit counted"
assert_contains "$OUT" "Write:1" "T6: Write counted"
assert_contains "$OUT" "multi.ts" "T6: MultiEdit file extracted"
assert_contains "$OUT" "fresh.md" "T6: Write file extracted"

# --- Test 7: идемпотентность — second call appends new block, doesn't overwrite ---
activity_flush "sid-1-abcdefgh" "$TRANSCRIPT1" "$CWD1"
BLOCK_COUNT=$(grep -c "^## " "$CWD1/.claude-docs/session-activity.md")
assert_eq "$BLOCK_COUNT" "2" "T7: second call appends second block"

# --- Test 8: git commits (if .git exists) ---
CWD8="$TMP/p8"
mkdir -p "$CWD8"
(
    cd "$CWD8"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    echo "a" > a.txt
    git add a.txt
    git commit -q -m "initial commit"
) 2>/dev/null
activity_flush "sid-8" "$TRANSCRIPT1" "$CWD8"
OUT=$(cat "$CWD8/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "Commits:" "T8: git commits section present when repo exists"

# --- Test 9: duplicate file_paths are deduplicated ---
TRANSCRIPT9="$TMP/t9.jsonl"
CWD9="$TMP/p9"
mkdir -p "$CWD9"
cat > "$TRANSCRIPT9" <<'JSONL'
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/same.py"}}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/same.py"}}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/same.py"}}]}}
JSONL
activity_flush "sid-9" "$TRANSCRIPT9" "$CWD9"
OUT=$(cat "$CWD9/.claude-docs/session-activity.md" 2>/dev/null)
# "same.py" should appear once in "Files touched: same.py\n" line
FILES_LINE=$(grep "Files touched:" "$CWD9/.claude-docs/session-activity.md")
SAME_COUNT=$(echo "$FILES_LINE" | tr ' ' '\n' | grep -c "^same\.py$")
assert_eq "$SAME_COUNT" "1" "T9: duplicate file_paths deduplicated"
assert_contains "$OUT" "Edit:3" "T9: Edit count still 3 despite same file"

# --- Test 10: user prompt captured (Фаза 2 substrate) ---
TRANSCRIPT10="$TMP/t10.jsonl"
CWD10="$TMP/p10"
mkdir -p "$CWD10"
cat > "$TRANSCRIPT10" <<'JSONL'
{"message":{"role":"user","content":[{"type":"text","text":"fix the auth redirect bug"}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/auth.ts"}}]}}
JSONL
activity_flush "sid-10" "$TRANSCRIPT10" "$CWD10"
OUT=$(cat "$CWD10/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "Prompts (1):" "T10: prompt count present"
assert_contains "$OUT" "fix the auth redirect bug" "T10: prompt text captured"

# --- Test 11: hook-injected boilerplate block filtered, real prompt kept ---
TRANSCRIPT11="$TMP/t11.jsonl"
CWD11="$TMP/p11"
mkdir -p "$CWD11"
cat > "$TRANSCRIPT11" <<'JSONL'
{"message":{"role":"user","content":[{"type":"text","text":"<system-reminder>injected hook context blah</system-reminder>"},{"type":"text","text":"real user question here"}]}}
{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
JSONL
activity_flush "sid-11" "$TRANSCRIPT11" "$CWD11"
OUT=$(cat "$CWD11/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "real user question here" "T11: real prompt kept"
assert_not_contains "$OUT" "injected hook context" "T11: injected boilerplate block dropped"

# --- Test 12: long prompt truncated with elision marker ---
TRANSCRIPT12="$TMP/t12.jsonl"
CWD12="$TMP/p12"
mkdir -p "$CWD12"
LONGPROMPT=$(printf 'A%.0s' $(seq 1 250))
jq -cn --arg t "$LONGPROMPT" '{message:{role:"user",content:[{type:"text",text:$t}]}}' > "$TRANSCRIPT12"
jq -cn '{message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:"/x.md"}}]}}' >> "$TRANSCRIPT12"
activity_flush "sid-12" "$TRANSCRIPT12" "$CWD12"
OUT=$(cat "$CWD12/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "…<+" "T12: long prompt truncated with elision marker"

# --- T13: секреты в промпте редактируются до записи (D61) ---
TRANSCRIPT13="$TMP/t13.jsonl"
CWD13="$TMP/p13"
mkdir -p "$CWD13"
# Фейковый sk-ключ собирается конкатенацией: сплошной паттерн в исходнике
# ронял бы гейт публикации (forbidden.txt не отличает фейк от настоящего).
FAKE_SK="sk-""ABCDEFGHIJKLMNOP1234"
jq -nc --arg t "вот токен hf_abcdefghijklmnopqrstuvwxyz1234 и ключ $FAKE_SK для деплоя" \
    '{message:{role:"user",content:[{type:"text",text:$t}]}}' > "$TRANSCRIPT13"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"echo hi"}}]}}' >> "$TRANSCRIPT13"
activity_flush "sid-13" "$TRANSCRIPT13" "$CWD13"
OUT=$(cat "$CWD13/.claude-docs/session-activity.md" 2>/dev/null)
assert_contains "$OUT" "[REDACTED-hf]" "T13: hf-токен заменён маркером"
assert_contains "$OUT" "[REDACTED-sk]" "T13b: sk-ключ заменён маркером"
assert_not_contains "$OUT" "hf_abcdefghijklmnopqrstuvwxyz1234" "T13c: сырой hf-токен не записан"
assert_not_contains "$OUT" "$FAKE_SK" "T13d: сырой sk-ключ не записан"

echo ""
echo "Activity flush tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
