#!/usr/bin/env bash
# test_enrich_suggester.sh — enrich-suggester.sh coverage.
# Изоляция через STATE_DIR + tmp GLOBAL_LESSONS per test.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/enrich-suggester.sh"

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
export GLOBAL_LESSONS="$TMP/global-lessons"
mkdir -p "$STATE_DIR" "$GLOBAL_LESSONS"

# Helper: write entity file with given attrs mode
# modes: sparse_empty | sparse_one | rich | no_attrs_key
write_entity() {
    local path="$1" mode="$2"
    case "$mode" in
        sparse_empty)
            cat > "$path" <<'EOF'
---
name: Test Sparse
type: entity
entity_type: concept
attributes: {}
---

Test sparse entity.
EOF
            ;;
        sparse_one)
            cat > "$path" <<'EOF'
---
name: Test Sparse One
type: entity
entity_type: concept
attributes:
  foo: bar
---

Sparse with one attr.
EOF
            ;;
        rich)
            cat > "$path" <<'EOF'
---
name: Test Rich
type: entity
entity_type: concept
attributes:
  foo: bar
  baz: qux
  lorem: ipsum
  quux: quuz
---

Rich entity.
EOF
            ;;
        no_attrs_key)
            cat > "$path" <<'EOF'
---
name: Test NoAttrs
type: entity
entity_type: concept
---

No attributes key at all.
EOF
            ;;
    esac
}

run_with() {
    local sid="$1" prompt="$2"
    local payload
    payload=$(jq -cn --arg sid "$sid" --arg prompt "$prompt" \
        '{session_id: $sid, cwd: "/tmp", prompt: $prompt}')
    printf '%s' "$payload" | STATE_DIR="$STATE_DIR" GLOBAL_LESSONS="$GLOBAL_LESSONS" bash "$SCRIPT" 2>/dev/null
}

# ============================================================================
# T1: нет entity files → skip
# ============================================================================
OUT=$(run_with "sid1" "что дальше?")
assert_empty "$OUT" "T1: no entity files → skip"

# ============================================================================
# T2: rich entity (4 attrs) → skip
# ============================================================================
write_entity "$GLOBAL_LESSONS/entity-rich.md" rich
OUT=$(run_with "sid2" "что дальше?")
assert_empty "$OUT" "T2: rich entity (4 attrs) → skip"

# ============================================================================
# T3: sparse_empty (0 attrs) → fire
# ============================================================================
write_entity "$GLOBAL_LESSONS/entity-sparse.md" sparse_empty
OUT=$(run_with "sid3" "что дальше?")
assert_contains "$OUT" "Sparse entity" "T3a: sparse_empty → fire"
assert_contains "$OUT" "sparse" "T3b: sparse in inject"
assert_contains "$OUT" "0 attr" "T3c: count 0 в inject"

# ============================================================================
# T4: sparse_one (1 attr) — под порогом 3 → fire
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-sparse1.md" sparse_one
OUT=$(run_with "sid4" "continue")
assert_contains "$OUT" "sparse1" "T4a: sparse_one → fire"
assert_contains "$OUT" "1 attr" "T4b: count 1 в inject"

# ============================================================================
# T5: per-session dedup — тот же sparse-set → skip
# ============================================================================
OUT=$(run_with "sid4" "и дальше?")
assert_empty "$OUT" "T5: same session same sparse → dedup"

# ============================================================================
# T6: другая сессия — fire снова
# ============================================================================
OUT=$(run_with "sid6" "continue")
assert_contains "$OUT" "sparse1" "T6: cross-session independence"

# ============================================================================
# T7: prompt упоминает /enrich → skip
# ============================================================================
OUT=$(run_with "sid7" "запусти /enrich для foo")
assert_empty "$OUT" "T7: prompt mentions /enrich → skip"

OUT=$(run_with "sid7b" "обогати эту сущность")
assert_empty "$OUT" "T7b: prompt mentions обогати → skip"

# ============================================================================
# T8: custom threshold
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-rich.md" rich
payload=$(jq -cn --arg sid "sid8" --arg prompt "x" \
    '{session_id: $sid, cwd: "/tmp", prompt: $prompt}')
OUT=$(printf '%s' "$payload" | STATE_DIR="$STATE_DIR" GLOBAL_LESSONS="$GLOBAL_LESSONS" ENRICH_SPARSE_THRESHOLD=10 bash "$SCRIPT" 2>/dev/null)
assert_contains "$OUT" "rich" "T8: threshold 10 → rich (4 attrs) попадает в sparse"

# ============================================================================
# T9: no attributes key at all → treated as 0, fire
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-no-attrs.md" no_attrs_key
OUT=$(run_with "sid9" "x")
assert_contains "$OUT" "no-attrs" "T9: no attributes key → treated as 0"

# ============================================================================
# T10: mtime outside window → skip (touch file to old mtime)
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-old.md" sparse_empty
# Set mtime to 2 hours ago (outside default 30 min window)
touch -t $(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M) "$GLOBAL_LESSONS/entity-old.md" 2>/dev/null || touch -t "200001010000" "$GLOBAL_LESSONS/entity-old.md"
OUT=$(run_with "sid10" "x")
assert_empty "$OUT" "T10: old mtime → outside window → skip"

# ============================================================================
# T11: валидный JSON output
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-valid.md" sparse_empty
OUT=$(run_with "sid11" "x")
echo "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
    && { PASS=$((PASS+1)); } \
    || { FAIL=$((FAIL+1)); echo "FAIL [T11]: invalid JSON or wrong hookEventName: $OUT"; }

# ============================================================================
# T12: несколько sparse → все в inject
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-alpha.md" sparse_empty
write_entity "$GLOBAL_LESSONS/entity-beta.md" sparse_one
OUT=$(run_with "sid12" "x")
assert_contains "$OUT" "alpha" "T12a: alpha в inject"
assert_contains "$OUT" "beta" "T12b: beta в inject"

# ============================================================================
# T13: один sparse + один rich → только sparse
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
write_entity "$GLOBAL_LESSONS/entity-good.md" rich
write_entity "$GLOBAL_LESSONS/entity-bad.md" sparse_empty
OUT=$(run_with "sid13" "x")
assert_contains "$OUT" "bad" "T13a: bad (sparse) в inject"
echo "$OUT" | grep -Fq "good " \
    && { FAIL=$((FAIL+1)); echo "FAIL [T13b]: good (rich) попал в inject"; } \
    || PASS=$((PASS+1))

# ============================================================================
# T14: empty/garbage input → silent
# ============================================================================
rm -f "$GLOBAL_LESSONS"/entity-*.md
OUT=$(printf '' | STATE_DIR="$STATE_DIR" GLOBAL_LESSONS="$GLOBAL_LESSONS" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T14a: empty input → empty output"

OUT=$(printf 'not-json' | STATE_DIR="$STATE_DIR" GLOBAL_LESSONS="$GLOBAL_LESSONS" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T14b: garbage input → empty output"

# ============================================================================
# T15: GLOBAL_LESSONS не существует → silent
# ============================================================================
OUT=$(run_with_missing() {
    local payload
    payload=$(jq -cn '{session_id: "sid15", cwd: "/tmp", prompt: "x"}')
    printf '%s' "$payload" | STATE_DIR="$STATE_DIR" GLOBAL_LESSONS="$TMP/nonexistent" bash "$SCRIPT" 2>/dev/null
}; run_with_missing)
assert_empty "$OUT" "T15: missing GLOBAL_LESSONS dir → silent"

echo ""
echo "=================================="
echo "enrich-suggester: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
