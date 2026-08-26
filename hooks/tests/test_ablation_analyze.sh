#!/usr/bin/env bash
# test_ablation_analyze.sh — парный анализ: числовая фикстура, посчитанная руками.
# b=5 (Full+/Van-), c=1, n=20: p = 2*P(X<=1|n=6,p=.5) = 14/64 = 0.21875;
# Δ̂ = 4/20 = 0.2; Agresti–Min: d'=4/22≈0.1818, se'=sqrt(7-16/22)/22≈0.11384,
# CI ≈ [-0.0413, 0.4050] → нижняя граница < 0 при Δ̂=δ → «неразрешающий».

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/ablation/pair-analyze.py"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 20 пар: 5×(1,0), 1×(0,1), 10×(1,1), 4×(0,0); страта surface — первые 8.
python3 - "$TMP/pairs.jsonl" << 'EOF'
import json, sys
pairs = [(1,0)]*5 + [(0,1)]*1 + [(1,1)]*10 + [(0,0)]*4
with open(sys.argv[1], "w") as f:
    for i, (full, van) in enumerate(pairs):
        f.write(json.dumps({"task_id": f"t-{i}", "full": full, "vanilla": van,
                            "stratum_surface": i < 8}) + "\n")
EOF

OUT=$(python3 "$SCRIPT" "$TMP/pairs.jsonl")

# --- T1: дискордантная таблица ---
assert_contains "$OUT" '"full_plus_vanilla_minus": 5' "T1: b=5"
assert_contains "$OUT" '"full_minus_vanilla_plus": 1' "T1b: c=1"

# --- T2: Δ̂ и CI (ручной расчёт) ---
assert_contains "$OUT" '"delta_hat": 0.2' "T2: Δ̂=0.2"
assert_contains "$OUT" '-0.0413' "T2b: нижняя граница CI"
assert_contains "$OUT" '0.4049' "T2c: верхняя граница CI"

# --- T3: exact McNemar p = 0.21875 ---
assert_contains "$OUT" '"mcnemar_exact_p": 0.21875' "T3: p ручного расчёта"

# --- T4: правило решения — неразрешающий (Δ̂=δ, но нижняя < 0) ---
assert_contains "$OUT" '"outcome": "неразрешающий"' "T4: классификация"

# --- T5: страта считается отдельно (8 пар: b=5,c=1 → Δ̂=0.5) ---
assert_contains "$OUT" '"pairs": 8' "T5: объём страты"

# --- T6: пустой вход не падает ---
: > "$TMP/empty.jsonl"
OUT=$(python3 "$SCRIPT" "$TMP/empty.jsonl") && ok || bad "T6" "упал на пустом входе"
assert_contains "$OUT" "нет данных" "T6b: явный вердикт при нуле пар"

echo "test_ablation_analyze: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
