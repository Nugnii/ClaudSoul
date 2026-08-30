#!/usr/bin/env bash
# test_yaml_lib.sh — характеризующий тест для общего yaml-lib.sh.
# Фиксирует каноническое поведение yaml_field (скаляры + quoted + bracketed list),
# чтобы дедупликация из bridge-health-digest и knowledge-audit-digest не меняла семантику.
# Изоляция: tmp-файлы, lib резолвится через YAML_LIB env (по умолчанию — исходник проекта).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
YAML_LIB="${YAML_LIB:-$HOOKS_DIR/yaml-lib.sh}"

[ -f "$YAML_LIB" ] || { echo "FAIL: $YAML_LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$YAML_LIB"

PASS=0
FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture frontmatter covering every field shape the digests actually read.
FX="$TMP/fixture.md"
cat > "$FX" <<'EOF'
---
name: test-fixture
status: active
quoted_dq: "foo bar"
quoted_sq: 'baz'
impact: 4
domain: [test]
layers: [L2, L3]
blocker: true
escalation_hint: "next defense layer needed"
status_in_body_guard: header
---

status_in_body_guard: body-value-must-not-be-read
domain: [should-not-be-read]
EOF

# --- scalar ---
assert_eq "$(yaml_field "$FX" status)" "active" "T1: bare scalar"
assert_eq "$(yaml_field "$FX" impact)" "4" "T2: numeric scalar"
assert_eq "$(yaml_field "$FX" blocker)" "true" "T3: boolean scalar"

# --- quoted (the reason quotes get stripped) ---
assert_eq "$(yaml_field "$FX" quoted_dq)" "foo bar" "T4: double-quoted value, quotes stripped"
assert_eq "$(yaml_field "$FX" quoted_sq)" "baz" "T5: single-quoted value, quotes stripped"
assert_eq "$(yaml_field "$FX" escalation_hint)" "next defense layer needed" "T6: quoted phrase"

# --- bracketed list (THE divergence point: canonical version strips brackets) ---
assert_eq "$(yaml_field "$FX" domain)" "test" "T7: single-item list, brackets stripped"
assert_eq "$(yaml_field "$FX" layers)" "L2, L3" "T8: multi-item list, brackets stripped"

# --- missing field → empty ---
assert_eq "$(yaml_field "$FX" nonexistent)" "" "T9: missing field yields empty"

# --- frontmatter boundary: body-only repeats must not be read (depth guard) ---
assert_eq "$(yaml_field "$FX" status_in_body_guard)" "header" "T10: only frontmatter read, body ignored"

# --- first match wins on duplicate key in frontmatter ---
DUP="$TMP/dup.md"
cat > "$DUP" <<'EOF'
---
status: first
status: second
---
Body
EOF
assert_eq "$(yaml_field "$DUP" status)" "first" "T11: first match wins"

# --- missing file → empty, no crash ---
assert_eq "$(yaml_field "$TMP/nope.md" status)" "" "T12: missing file yields empty, no crash"

echo ""
echo "yaml-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
