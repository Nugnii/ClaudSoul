#!/usr/bin/env bash
# test_ablation_analyze.sh — анализ троек: числовые фикстуры, посчитанные руками.
# Версия 1.4: три контраста (Δ_all, Δ_structure, Δ_memory) и иерархический гейт.
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

# --- T6a: без плеча core контраст структуры честно пуст, гейт закрыт ---
assert_contains "$OUT" '"contrast": "full − core"' "T6a: контраст структуры назван"
assert_contains "$OUT" '"outcome": "нет данных"' "T6a2: нет core — нет чисел, а не нули"
assert_contains "$OUT" '"gate": "закрыт"' "T6a3: неразрешившийся Δ_all закрывает гейт"
assert_contains "$OUT" '"reading": "исследовательское"' "T6a4: прочтение понижено"

# --- T6: пустой вход не падает ---
: > "$TMP/empty.jsonl"
OUT=$(python3 "$SCRIPT" "$TMP/empty.jsonl") && ok || bad "T6" "упал на пустом входе"
assert_contains "$OUT" "нет данных" "T6b: явный вердикт при нуле пар"

# --- T7: тройка полностью — три контраста, ручной расчёт ---
# 5x(1,0,0) + 3x(1,1,0) + 8x(1,1,1) + 4x(0,0,0), n=20:
#   Δ_all       b=8, c=0 → Δ̂=0.40; Agresti–Min CI=[0.1437,0.5835] → польза
#   Δ_structure b=5, c=0 → Δ̂=0.25; CI=[0.0308,0.4238] → польза (гейт открыт)
#   Δ_memory    b=3, c=0 → Δ̂=0.15 < δ → неразрешающий
python3 - "$TMP/triples.jsonl" << 'EOF'
import json, sys
rows = [(1,0,0)]*5 + [(1,1,0)]*3 + [(1,1,1)]*8 + [(0,0,0)]*4
with open(sys.argv[1], "w") as f:
    for i, (full, core, van) in enumerate(rows):
        f.write(json.dumps({"task_id": f"t-{i}", "full": full, "core": core,
                            "vanilla": van, "stratum_surface": i < 8}) + "\n")
EOF
OUT=$(python3 "$SCRIPT" "$TMP/triples.jsonl")
assert_contains "$OUT" '"delta_hat": 0.4' "T7: Δ_all=0.40"
assert_contains "$OUT" '"outcome": "польза"' "T7b: Δ_all разрешился"
assert_contains "$OUT" '"delta_hat": 0.25' "T7c: Δ_structure=0.25"
assert_contains "$OUT" '"full_plus_core_minus": 5' "T7d: дискордантные структуры"
assert_contains "$OUT" '"delta_hat": 0.15' "T7e: Δ_memory=0.15"
assert_contains "$OUT" '"core_plus_vanilla_minus": 3' "T7f: дискордантные памяти"

# --- T8: гейт открыт разрешившимся Δ_all → подтверждающее прочтение ---
assert_contains "$OUT" '"gate": "открыт"' "T8: гейт открыт"
assert_contains "$OUT" '"reading": "подтверждающее"' "T8b: прочтение поднято"

# --- T9: гейт зависит от Δ_all, а не от собственной значимости Δ_structure ---
# Те же тройки, но Δ_all обнулён (full=vanilla всюду): Δ_structure остаётся
# крупным, прочтение обязано упасть до исследовательского.
python3 - "$TMP/gated.jsonl" << 'EOF'
import json, sys
rows = [(1,0,1)]*6 + [(1,1,1)]*10 + [(0,0,0)]*4
with open(sys.argv[1], "w") as f:
    for i, (full, core, van) in enumerate(rows):
        f.write(json.dumps({"task_id": f"t-{i}", "full": full, "core": core,
                            "vanilla": van, "stratum_surface": False}) + "\n")
EOF
OUT=$(python3 "$SCRIPT" "$TMP/gated.jsonl")
assert_contains "$OUT" '"full_plus_core_minus": 6' "T9: Δ_structure крупный"
assert_contains "$OUT" '"gate": "закрыт"' "T9b: гейт закрыт нулевым Δ_all"
assert_contains "$OUT" '"reading": "исследовательское"' "T9c: прочтение понижено вопреки размеру Δ_structure"

echo "test_ablation_analyze: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
