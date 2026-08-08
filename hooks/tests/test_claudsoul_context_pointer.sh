#!/usr/bin/env bash
# test_claudsoul_context_pointer.sh — v1.6.8: ClaudSoul mention detector.
# Изоляция через STATE_DIR + CLAUDSOUL_PROJECT_PATH + CLAUDSOUL_TEST_PWD.
# v1.6.8: T16-T22 — path-based recall (global-lessons/, principle-*.md, etc.)

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/claudsoul-context-pointer.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
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

# Fixture project with synthetic CLAUDE.md
FAKE_PROJECT="$TMP/fake-project"
mkdir -p "$FAKE_PROJECT"
cat > "$FAKE_PROJECT/CLAUDE.md" <<'EOF'
# ClaudSoul — CLAUDE.md (test fixture)

## 1. О проекте
Test fixture.

## 5. Текущий статус

| Компонент | Статус | Версия |
|-----------|--------|--------|
| Test row 1 | works | v0.0.1 |
| Test row 2 | works | v0.0.2 |
| Test row 3 | works | v0.0.3 |

## 6. После статуса
Должен быть исключён из инжекта.
EOF

# Default cwd: outside project (use $TMP itself)
DEFAULT_PWD="$TMP"

run_with() {
    local sid="$1" prompt="$2" pwd_override="${3:-$DEFAULT_PWD}"
    printf '{"session_id":"%s","user_prompt":%s}' "$sid" "$(printf '%s' "$prompt" | jq -Rs .)" | \
        STATE_DIR="$STATE_DIR" \
        CLAUDSOUL_PROJECT_PATH="$FAKE_PROJECT" \
        CLAUDSOUL_TEST_PWD="$pwd_override" \
        bash "$SCRIPT" 2>/dev/null
}

# --- T1: prompt с "ClaudSoul" → fires ---
OUT=$(run_with "sid-t1" "Расскажи про ClaudSoul архитектуру")
assert_contains "$OUT" "ClaudSoul project state pointer" "T1: ClaudSoul mention fires"
assert_contains "$OUT" "Test row 1" "T1b: status section в инжекте"

# --- T2: prompt с "клод соул" (cyrillic) → fires ---
OUT=$(run_with "sid-t2" "что у меня в системе клод соул сейчас работает")
assert_contains "$OUT" "ClaudSoul project state pointer" "T2: cyrillic клод соул fires"

# --- T3: prompt с "claud-soul" (hyphen) → fires ---
OUT=$(run_with "sid-t3" "Я тут размышляю про claud-soul и его hooks")
assert_contains "$OUT" "ClaudSoul project state pointer" "T3: claud-soul hyphen fires"

# --- T4: prompt с "claud soul" (space) → fires ---
OUT=$(run_with "sid-t4" "А что в claud soul новенького?")
assert_contains "$OUT" "ClaudSoul project state pointer" "T4: claud soul space fires"

# --- T5: prompt без ClaudSoul → silent ---
OUT=$(run_with "sid-t5" "Расскажи про погоду в Варшаве сегодня")
assert_empty "$OUT" "T5: prompt без ClaudSoul → silent"

# --- T6: cwd внутри проекта → silent ---
OUT=$(run_with "sid-t6" "Что в ClaudSoul" "$FAKE_PROJECT")
assert_empty "$OUT" "T6: cwd внутри проекта → silent"

# --- T7: cwd в подпапке проекта → silent ---
mkdir -p "$FAKE_PROJECT/subdir"
OUT=$(run_with "sid-t7" "ClaudSoul вопрос" "$FAKE_PROJECT/subdir")
assert_empty "$OUT" "T7: cwd в подпапке проекта → silent"

# --- T8: per-session dedup — второй вызов → silent ---
SID_DEDUP="sid-t8-dedup"
OUT1=$(run_with "$SID_DEDUP" "ClaudSoul первый раз")
assert_contains "$OUT1" "ClaudSoul project state pointer" "T8a: первый вызов → fires"
OUT2=$(run_with "$SID_DEDUP" "ClaudSoul второй раз")
assert_empty "$OUT2" "T8b: повторный вызов → silent (dedup)"

# --- T9: empty session_id → silent ---
OUT=$(printf '{"session_id":"","user_prompt":"ClaudSoul вопрос"}' | \
    STATE_DIR="$STATE_DIR" \
    CLAUDSOUL_PROJECT_PATH="$FAKE_PROJECT" \
    CLAUDSOUL_TEST_PWD="$DEFAULT_PWD" \
    bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T9: empty session_id → silent"

# --- T10: empty user_prompt → silent ---
OUT=$(printf '{"session_id":"sid-t10","user_prompt":""}' | \
    STATE_DIR="$STATE_DIR" \
    CLAUDSOUL_PROJECT_PATH="$FAKE_PROJECT" \
    CLAUDSOUL_TEST_PWD="$DEFAULT_PWD" \
    bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T10: empty user_prompt → silent"

# --- T11: project CLAUDE.md missing → silent ---
OUT=$(printf '{"session_id":"sid-t11","user_prompt":"ClaudSoul"}' | \
    STATE_DIR="$STATE_DIR" \
    CLAUDSOUL_PROJECT_PATH="$TMP/non-existent-dir" \
    CLAUDSOUL_TEST_PWD="$DEFAULT_PWD" \
    bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T11: project CLAUDE.md отсутствует → silent"

# --- T12: case-insensitive match (UPPER) → fires ---
OUT=$(run_with "sid-t12" "Поговорим про CLAUDSOUL вообще")
assert_contains "$OUT" "ClaudSoul project state pointer" "T12: uppercase CLAUDSOUL fires"

# --- T13: упоминание Claude (без Soul) → silent ---
OUT=$(run_with "sid-t13" "У меня есть Claude Code и я хочу спросить общий вопрос")
assert_empty "$OUT" "T13: 'Claude' без Soul → silent (не false positive)"

# --- T14: section после "## 5" не должна попасть в инжект ---
OUT=$(run_with "sid-t14" "ClaudSoul спецификация")
echo "$OUT" | grep -Fq "После статуса" && {
    FAIL=$((FAIL + 1)); echo "FAIL [T14]: section after ## 5 leaked into inject"
} || PASS=$((PASS + 1))

# --- T15: hookEventName в envelope ---
OUT=$(run_with "sid-t15" "ClaudSoul envelope check")
assert_contains "$OUT" '"hookEventName": "UserPromptSubmit"' "T15: правильный hookEventName"

# --- T16: path с явным "ClaudSoul" в нём → fires (substring catches it) ---
OUT=$(run_with "sid-t16" "Прочитай @~/My Project/ClaudSoul/hooks/error-tracker.sh")
assert_contains "$OUT" "ClaudSoul project state pointer" "T16: path с ClaudSoul в нём fires"

# --- T17 (v1.6.8 path-based): prompt с "global-lessons" path → fires ---
OUT=$(run_with "sid-t17" "Посмотри ~/.claude/global-lessons/ — что там накопилось")
assert_contains "$OUT" "ClaudSoul project state pointer" "T17: global-lessons path fires (path-based)"

# --- T18 (v1.6.8 filename-based): principle-*.md → fires ---
OUT=$(run_with "sid-t18" "Открой principle-knowledge-in-the-world.md и расскажи о нём")
assert_contains "$OUT" "ClaudSoul project state pointer" "T18: principle-*.md filename fires"

# --- T19 (v1.6.8 filename-based): pattern-*.md → fires ---
OUT=$(run_with "sid-t19" "Что в pattern-inside-out-blindness.md написано?")
assert_contains "$OUT" "ClaudSoul project state pointer" "T19: pattern-*.md filename fires"

# --- T20 (v1.6.8 filename-based): entity-*.md → fires ---
OUT=$(run_with "sid-t20" "Прочитай entity-john-doe.md")
assert_contains "$OUT" "ClaudSoul project state pointer" "T20: entity-*.md filename fires"

# --- T21 (v1.6.8 false-positive guard): "principle of X" без -*.md → silent ---
OUT=$(run_with "sid-t21" "Apply principle of least privilege to this design")
assert_empty "$OUT" "T21: 'principle of...' без -*.md паттерна → silent"

# --- T22 (v1.6.8 false-positive guard): pattern в общем смысле → silent ---
OUT=$(run_with "sid-t22" "Use the singleton pattern for this database connection")
assert_empty "$OUT" "T22: 'pattern' в общем смысле → silent"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
