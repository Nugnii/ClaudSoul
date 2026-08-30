#!/usr/bin/env bash
# test_co_cognition_lib.sh — co-cognition-lib.sh (мост L2↔L7).
#
# Закрепляется:
#   - счёт по знаниевому ядру (entity-/fact-/relation- в знаменатель не входят);
#   - атрибуция impact не зависит от порядка полей во frontmatter (дефект пойман
#     до первого коммита: origin наследовался от предыдущего файла);
#   - нормализация кавычек триггера ("contradiction" и contradiction — один триггер;
#     живая база содержит оба написания);
#   - средний impact co-cognition против solo с одной десятой;
#   - измеренный ноль co-cognition отличим от «не измеряли» (пустое ядро).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/co-cognition-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
. "$LIB"

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
D="$TMP/lessons"; mkdir -p "$D"

# Ядро: 2 co-cognition (impact 5 и 4; триггеры question и "question" — кавычки),
# 1 solo (impact 2), 1 без origin, 1 trajectory_pivot.
# ВАЖНО: в first impact стоит РАНЬШЕ origin — регресс на порядок полей.
cat > "$D/case-a.md" <<'EOF'
---
impact: 5
origin: co-cognition
trigger_for_co_cognition: question
---
EOF
cat > "$D/case-b.md" <<'EOF'
---
origin: co-cognition
impact: 4
trigger_for_co_cognition: "question"
---
EOF
cat > "$D/pattern-c.md" <<'EOF'
---
origin: solo
impact: 2
---
EOF
cat > "$D/principle-d.md" <<'EOF'
---
impact: 3
---
EOF
cat > "$D/case-e.md" <<'EOF'
---
origin: trajectory_pivot
impact: 1
---
EOF
# Второй контур — не должен попасть в знаменатель.
cat > "$D/entity-x.md" <<'EOF'
---
origin: co-cognition
impact: 5
---
EOF

OUT=$(cocog_block "$D")
assert_contains "$OUT" "## Co-cognition health (L2↔L7)" "T1 заголовок"
assert_contains "$OUT" "**Ядро:** 5 (case+pattern+principle)" "T2 entity вне знаменателя"
assert_contains "$OUT" "co-cognition 2, trajectory_pivot 1, solo 1, без поля 1" "T3 корзины origin"
assert_contains "$OUT" "**co_cognition_ratio:** 40%" "T4 доля 2/5"
assert_contains "$OUT" "co-cognition 4.5 (n=2) против solo 2.0 (n=1)" "T5 средний impact, порядок полей не важен"
assert_contains "$OUT" "question ×2" "T6 кавычки триггера нормализованы"

# T7: измеренный ноль — ядро есть, co-cognition нет
D2="$TMP/zero"; mkdir -p "$D2"
printf -- '---\nimpact: 3\n---\n' > "$D2/case-z.md"
OUT2=$(cocog_block "$D2")
assert_contains "$OUT2" "co-cognition 0" "T7 ноль измерен"
assert_contains "$OUT2" "**co_cognition_ratio:** 0%" "T7 доля 0%"

# T8: «не измеряли» — ядра нет вовсе
D3="$TMP/empty"; mkdir -p "$D3"
assert_contains "$(cocog_block "$D3")" "Не измеряли: знаниевое ядро пусто" "T8 пустое ядро"

echo ""
echo "test_co_cognition_lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
