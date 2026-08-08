#!/usr/bin/env bash
# test_narrative_compose.sh — unit tests for narrative-compose-lib.sh.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/narrative-compose-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck disable=SC1090
source "$LIB"

PASS=0
FAIL=0
assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]"; echo "  expected: $expected"; echo "  actual:   $actual"; fi
}
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: «$needle» not in output"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then FAIL=$((FAIL + 1)); echo "FAIL [$label]: «$needle» unexpectedly in output"
    else PASS=$((PASS + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_compose() {
    COMPOSE_OUT=$(narrative_compose "$@" 2>&1); COMPOSE_EC=$?
}

# --- Test 1: missing project root ---
run_compose "$TMP/nope" 3 14 "$TMP"
assert_eq "1" "$COMPOSE_EC" "T1: missing project root → exit 1"

# --- Test 2: missing SESSION.md ---
mkdir -p "$TMP/p2"
run_compose "$TMP/p2" 3 14 "$TMP/p2/lessons"
assert_eq "1" "$COMPOSE_EC" "T2: missing SESSION.md → exit 1"

# --- Test 3: <2 SESSION entries → exit 2 ---
mkdir -p "$TMP/p3" "$TMP/p3/lessons"
cat > "$TMP/p3/SESSION.md" <<'EOF'
# Session Log
## 2026-04-22 — single entry
Body.
EOF
run_compose "$TMP/p3" 3 14 "$TMP/p3/lessons"
assert_eq "2" "$COMPOSE_EC" "T3: <2 entries → exit 2"

# --- Test 4: 2+ entries but no git/cases → exit 2 ---
mkdir -p "$TMP/p4" "$TMP/p4/lessons"
cat > "$TMP/p4/SESSION.md" <<'EOF'
# Session Log
## 2026-04-20 — alpha
A.
## 2026-04-22 — beta
B.
EOF
run_compose "$TMP/p4" 3 14 "$TMP/p4/lessons"
assert_eq "2" "$COMPOSE_EC" "T4: no commits + no cases → exit 2"

# --- Test 5: 2+ entries + 1 case → OK, output contains «Where we are» ---
mkdir -p "$TMP/p5" "$TMP/p5/lessons"
cat > "$TMP/p5/SESSION.md" <<'EOF'
# Session Log
## 2026-04-20 — first
A.
## 2026-04-22 — second
B.
EOF
touch "$TMP/p5/lessons/case-2026-04-22-foo.md"
run_compose "$TMP/p5" 3 14 "$TMP/p5/lessons"
assert_eq "0" "$COMPOSE_EC" "T5: valid history → exit 0"
assert_contains "$COMPOSE_OUT" "Where we are" "T5: header present"
assert_contains "$COMPOSE_OUT" "second" "T5: last title reflected"
assert_contains "$COMPOSE_OUT" "Knowledge delta" "T5: knowledge delta line present"
# Имя файла в «Свежие» строится через сортировку по mtime — без этой проверки поломка
# file_mtime проходит незамеченной: счётчик «1 case» считается независимо, строка остаётся.
assert_contains "$COMPOSE_OUT" "case-2026-04-22-foo.md" "T5: свежий case назван (покрывает file_mtime)"

# --- Test 6: git log is read when .git exists ---
mkdir -p "$TMP/p6" "$TMP/p6/lessons"
cat > "$TMP/p6/SESSION.md" <<'EOF'
# Session Log
## 2026-04-20 — first
A.
## 2026-04-22 — second
B.
EOF
(cd "$TMP/p6" && git init -q && git config user.email t@t && git config user.name T && touch README && git add README && git commit -q -m "feat: init")
run_compose "$TMP/p6" 3 14 "$TMP/p6/lessons"
OUT="$COMPOSE_OUT"
assert_eq "0" "$COMPOSE_EC" "T6: git+SESSION → exit 0"
assert_contains "$OUT" "Коммиты в окне" "T6: git summary present"
assert_contains "$OUT" "feat:1" "T6: feat count present"

# --- Test 7: trace line present (lists sessions + commits) ---
assert_contains "$OUT" "_Trace:_" "T7: trace section header"
assert_contains "$OUT" "sessions:" "T7: sessions in trace"
assert_contains "$OUT" "commits:" "T7: commits in trace"

# --- Test 8: entries=2 — output reflects only 2 entries ---
mkdir -p "$TMP/p8" "$TMP/p8/lessons"
cat > "$TMP/p8/SESSION.md" <<'EOF'
# Session Log
## 2026-04-18 — one
A.
## 2026-04-20 — two
B.
## 2026-04-22 — three
C.
EOF
touch "$TMP/p8/lessons/case-2026-04-22-bar.md"
run_compose "$TMP/p8" 2 14 "$TMP/p8/lessons"
OUT="$COMPOSE_OUT"
assert_contains "$OUT" "2 сессий" "T8: entries=2 reflected in count"
assert_contains "$OUT" "three" "T8: last title reflected"
assert_not_contains "$OUT" "one" "T8: oldest entry excluded when entries=2"

echo ""
echo "Narrative compose tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
