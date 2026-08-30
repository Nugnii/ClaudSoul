#!/usr/bin/env bash
# test_ablation_core_inject.sh — инжектор контрольного плеча Core (протокол §2, §12).
#
# Плечо Core задано не только тем, что оно делает (top-k по лексической
# близости), но и тем, чего НЕ делает. Поэтому половина проверок здесь —
# отрицательные: в инъекции не должно быть ни confidence, ни priority, ни
# blocker, ни аналогий. Если структура протечёт в Core, контраст Δ_structure
# начнёт мерить разницу, которой нет, и замер тихо соврёт.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INJ="$ROOT/scripts/ablation/core/inject.py"
[ -f "$INJ" ] || { echo "FAIL: $INJ not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_missing() {
    if grep -Fq -- "$2" <<< "$1"; then bad "$3" "'$2' протекло в инъекцию: $1"; else ok; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась пустота: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; mkdir -p "$L"
export CORE_LESSONS_DIR="$L"

# Фикстуры: у первой шапка со всей структурой — она и проверяет непротекание.
{
  printf -- '---\n'
  printf 'name: Переносимость оболочки\n'
  printf 'description: не полагайся на семантику конкретного shell\n'
  printf 'confidence: 5\nimpact: 3\nblocker: true\npriority: 9.9\n'
  printf -- '---\n\nТело про оболочку, портируемость и тесты.\n'
} > "$L/pattern-shell.md"
printf -- '---\nname: Валидность измерения\ndescription: контролируй нужную переменную\n---\n\nПро замер и конфаунд.\n' > "$L/pattern-measure.md"
printf -- '---\nname: Совсем другое\ndescription: про кулинарию\n---\n\nСупы, бульоны, специи.\n' > "$L/pattern-soup.md"

run() { printf '%s' "$1" | python3 "$INJ" 2>&1; }
q() { printf '{"prompt":%s}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")"; }

# --- T1: релевантная запись поднимается, нерелевантная — нет ---
OUT=$(run "$(q 'проблема переносимости оболочки shell в тестах')")
assert_contains "$OUT" "Переносимость оболочки" "T1: релевантное поднято"
assert_missing  "$OUT" "Совсем другое"          "T1b: нерелевантное не поднято"

# --- T2: структура НЕ протекает — это и есть определение плеча ---
assert_missing "$OUT" "confidence" "T2: confidence"
assert_missing "$OUT" "impact"     "T2b: impact"
assert_missing "$OUT" "blocker"    "T2c: blocker"
assert_missing "$OUT" "priority"   "T2d: priority"
assert_missing "$OUT" "⚡"          "T2e: маркер blocker-tier"
assert_missing "$OUT" "Аналогии"   "T2f: кросс-доменные аналогии"

# --- T3: потолок top-k соблюдается ---
OUT=$(CORE_INJECT_K=1 run "$(q 'оболочка shell замер измерение кулинария супы')")
[ "$(grep -c '^[0-9]\. ' <<< "$OUT")" -eq 1 ] && ok || bad "T3" "K=1 не соблюдён: $OUT"
OUT=$(CORE_INJECT_K=3 run "$(q 'оболочка shell замер измерение кулинария супы')")
[ "$(grep -c '^[0-9]\. ' <<< "$OUT")" -eq 3 ] && ok || bad "T3b" "K=3 не соблюдён: $OUT"

# --- T4: детерминизм — два одинаковых вызова дают побайтово одно и то же ---
Q=$(q 'оболочка shell замер измерение')
A=$(run "$Q"); B=$(run "$Q")
[ "$A" = "$B" ] && ok || bad "T4" "выдача недетерминирована"

# --- T5: ничего не совпало — молчание, а не пустая шапка ---
assert_empty "$(run "$(q 'квазистеллярные объекты гравитационного коллапса')")" "T5"

# --- T6: пустой и слишком короткий запрос — молчание ---
assert_empty "$(run "$(q '')")"        "T6"
assert_empty "$(run "$(q 'да нет')")"  "T6b"

# --- T7: битый вход не роняет хук (иначе плечо падает на ровном месте) ---
OUT=$(printf 'не json' | python3 "$INJ" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T7" "упал на битом JSON: $OUT"
assert_empty "$OUT" "T7b"

# --- T8: базы знаний нет — молчание, а не падение ---
OUT=$(CORE_LESSONS_DIR="$TMP/нет-такой" run "$Q"); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T8" "упал без базы знаний"
assert_empty "$OUT" "T8b"

echo "test_ablation_core_inject: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
