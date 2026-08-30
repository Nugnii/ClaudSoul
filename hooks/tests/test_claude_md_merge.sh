#!/usr/bin/env bash
# test_claude_md_merge.sh — v1.7.4: marker-based merge для install.sh::CLAUDE.md.
# 4 случая: (1) маркеры есть → replace between, (2) legacy без маркеров → переписать,
# (3) пользовательское без признаков → append, (4) файла нет → создать.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_ROOT/lib/claude-md-merge.sh"

[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }

# shellcheck source=../../lib/claude-md-merge.sh
source "$LIB"

PASS=0
FAIL=0
assert_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF "$needle" "$file" 2>/dev/null; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in $file"; cat "$file" | head -20; fi
}
assert_not_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF "$needle" "$file" 2>/dev/null; then
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' should NOT be in $file"
    else PASS=$((PASS + 1)); fi
}
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected='$expected' actual='$actual'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

MASTER="$TMP/master.md"
cat > "$MASTER" <<'EOF'
# Master Rules v9.9

Self-Learning system rules — Master content here.

Some other rule.
EOF

# === T1: target отсутствует → создаётся с маркерами ===
TARGET="$TMP/case1.md"
sync_claude_md "$TARGET" "$MASTER"
assert_eq "$?" "0" "T1: sync_claude_md returns 0"
assert_contains "$TARGET" "$CLAUDE_MD_MARKER_START" "T1: marker_start present"
assert_contains "$TARGET" "$CLAUDE_MD_MARKER_END" "T1: marker_end present"
assert_contains "$TARGET" "Master Rules v9.9" "T1: master content present"
assert_contains "$TARGET" "Some other rule." "T1: master rule preserved"

# === T2: target с маркерами → replace between, preserve outside ===
TARGET="$TMP/case2.md"
cat > "$TARGET" <<EOF
# User personal preamble

User custom rule before markers.

$CLAUDE_MD_MARKER_START
# OLD MASTER CONTENT v0.1
Some stale ClaudSoul rules.
$CLAUDE_MD_MARKER_END

User custom rule after markers.
EOF
sync_claude_md "$TARGET" "$MASTER"
assert_contains "$TARGET" "User personal preamble" "T2: outside-marker preamble preserved"
assert_contains "$TARGET" "User custom rule before markers." "T2: user content before markers preserved"
assert_contains "$TARGET" "User custom rule after markers." "T2: user content after markers preserved"
assert_contains "$TARGET" "Master Rules v9.9" "T2: new master content injected"
assert_not_contains "$TARGET" "OLD MASTER CONTENT v0.1" "T2: old master content removed"
assert_not_contains "$TARGET" "Some stale ClaudSoul rules." "T2: stale rules removed"
# Backup создан
BAK_COUNT=$(ls "$TMP"/case2.md.bak.* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$BAK_COUNT" "1" "T2: backup file created"

# === T3: legacy ClaudSoul без маркеров → переписать целиком ===
TARGET="$TMP/case3.md"
cat > "$TARGET" <<'EOF'
# Old ClaudSoul rules

Self-Learning v0 — legacy install.

Some old rule.
EOF
sync_claude_md "$TARGET" "$MASTER"
assert_contains "$TARGET" "$CLAUDE_MD_MARKER_START" "T3: markers added"
assert_contains "$TARGET" "Master Rules v9.9" "T3: master content injected"
assert_not_contains "$TARGET" "Self-Learning v0" "T3: legacy content replaced"
BAK_COUNT=$(ls "$TMP"/case3.md.bak.* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$BAK_COUNT" "1" "T3: backup file created"

# === T4: пользовательское без признаков ClaudSoul → append блок в конец ===
TARGET="$TMP/case4.md"
cat > "$TARGET" <<'EOF'
# User's personal CLAUDE.md

User has his own rules here.

Nothing about ClaudSoul.
EOF
sync_claude_md "$TARGET" "$MASTER"
assert_contains "$TARGET" "User has his own rules here." "T4: user content preserved"
assert_contains "$TARGET" "$CLAUDE_MD_MARKER_START" "T4: managed block appended with marker"
assert_contains "$TARGET" "Master Rules v9.9" "T4: master content appended"
# Маркер должен быть ПОСЛЕ user content
USER_LINE=$(grep -n "User has his own rules" "$TARGET" | cut -d: -f1)
MARKER_LINE=$(grep -n -F "$CLAUDE_MD_MARKER_START" "$TARGET" | cut -d: -f1)
if [ "$USER_LINE" -lt "$MARKER_LINE" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T4: user content before marker]: USER_LINE=$USER_LINE MARKER_LINE=$MARKER_LINE"; fi
BAK_COUNT=$(ls "$TMP"/case4.md.bak.* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$BAK_COUNT" "1" "T4: backup file created"

# === T5: idempotency — двойной вызов на T1 не дублирует контент ===
TARGET="$TMP/case5.md"
sync_claude_md "$TARGET" "$MASTER"
sync_claude_md "$TARGET" "$MASTER"
START_COUNT=$(grep -cF "$CLAUDE_MD_MARKER_START" "$TARGET" 2>/dev/null)
END_COUNT=$(grep -cF "$CLAUDE_MD_MARKER_END" "$TARGET" 2>/dev/null)
assert_eq "$START_COUNT" "1" "T5: marker_start не дублируется"
assert_eq "$END_COUNT" "1" "T5: marker_end не дублируется"
MASTER_COUNT=$(grep -cF "Master Rules v9.9" "$TARGET" 2>/dev/null)
assert_eq "$MASTER_COUNT" "1" "T5: master content не дублируется"

# === T6: master file отсутствует → return 1 ===
TARGET="$TMP/case6.md"
sync_claude_md "$TARGET" "/tmp/does-not-exist-$$.md" 2>/dev/null
RC=$?
assert_eq "$RC" "1" "T6: missing master returns 1"
[ ! -f "$TARGET" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T6: target should not be created when master missing]"; }

# === Итоги ===
TOTAL=$((PASS + FAIL))
echo
echo "claude-md-merge tests: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] && echo "All tests passed." || echo "Tests failed: $FAIL"
exit $((FAIL > 0 ? 1 : 0))
