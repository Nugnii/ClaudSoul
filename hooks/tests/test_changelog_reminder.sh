#!/usr/bin/env bash
# test_changelog_reminder.sh — тест напоминания о CHANGELOG при изменениях кода.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/changelog-reminder.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

assert_contains() { if printf '%s' "$1" | grep -qF "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2'"; fi; }
assert_empty()    { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалось пусто, '${1:0:60}'"; fi; }

REPO="$TMP/repo"
mkdir -p "$REPO/hooks" "$REPO/docs"
cd "$REPO"
git init -q; git config user.email t@t; git config user.name t
echo "# changelog" > CHANGELOG.md
echo "x" > hooks/feature.sh
echo "d" > docs/note.md
git add CHANGELOG.md; git commit -qm init

run_hook() {  # $1 = state subdir
    cd "$REPO"
    printf '{"session_id":"test-cl","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | env \
        STATE_DIR="$TMP/$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
}

# T1: код staged, CHANGELOG нет → напоминание
git reset -q; git add hooks/feature.sh
assert_contains "$(run_hook s1)" "CHANGELOG" "T1: код без CHANGELOG → напоминание"

# T2: код + CHANGELOG staged → тихо
git reset -q; echo "change" >> CHANGELOG.md; git add hooks/feature.sh CHANGELOG.md
assert_empty "$(run_hook s2)" "T2: CHANGELOG в staged → тихо"
git checkout -q CHANGELOG.md 2>/dev/null || true

# T3: только docs staged (нет кода) → тихо
git reset -q; git add docs/note.md
assert_empty "$(run_hook s3)" "T3: только docs → тихо"

# T4: throttle — тот же diff кода дважды → второй раз тихо
git reset -q; git add hooks/feature.sh
assert_contains "$(run_hook s4)" "CHANGELOG" "T4a: первый раз напоминает"
assert_empty   "$(run_hook s4)" "T4b: throttle — второй раз тихо"

# T5: не-коммит → тихо
cd "$REPO"
OUT=$(printf '{"session_id":"test-cl","tool_name":"Bash","tool_input":{"command":"ls -la"}}' | env STATE_DIR="$TMP/s5" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T5: не-коммит игнорируется"

echo ""
echo "changelog-reminder tests: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
