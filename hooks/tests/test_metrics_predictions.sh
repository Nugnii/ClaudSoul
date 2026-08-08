#!/usr/bin/env bash
# test_metrics_predictions.sh — prediction-calibration-lib.sh (мост L4↔L5).
#
# Что закрепляется:
#   - разбор таблиц `### Predictions` (тип из `P3:need`, строки без типа → untyped);
#   - pending — не решение, в знаменатель не входит;
#   - формула accuracy = (exact + 0.5×adjacent) / решённых, целочисленный процент;
#   - гейты выборки: секций < 5 → вердикт не выносится; тип с n < 5 → «выборка мала»;
#   - «не измеряли» отличим от нулей (нет SESSION.md / нет секций);
#   - корень с ПРОБЕЛОМ в пути («My Fixture») — регресс на словоразбиение списка
#     файлов, пойманное до первого коммита: awk получал пути аргументами.
#
# Тест не запускает metrics-collector целиком — библиотека проверяется напрямую,
# детерминированно, без состояния машины.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/prediction-calibration-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
. "$LIB"

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly in output:"; echo "$haystack"
    else PASS=$((PASS + 1)); fi
}

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected '$expected', got '$actual'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Фикстуры: корень с пробелом, два проекта, 5 секций, известные числа ---------
ROOT="$TMP/My Fixture"
mkdir -p "$ROOT/projA" "$ROOT/projB"

cat > "$ROOT/projA/SESSION.md" <<'EOF'
## 2026-08-01 — s1
### Predictions
| # | Predicted | Actual | Accuracy | Lesson |
|---|-----------|--------|----------|--------|
| P1:need | a | b | exact | l |
| P2:need | a | b | exact | l |
| P3:topic | a | b | miss | l |
| P4:topic | a | b | miss | l |
| P5 | a | b | adjacent | l |
| P6:need | a | b | pending | l |

## 2026-08-02 — s2
### Predictions
| # | Predicted | Actual | Accuracy | Lesson |
|---|-----------|--------|----------|--------|
| P1:need | a | b | exact | l |
| P2:need | a | b | exact | l |
| P3:topic | a | b | miss | l |
| P4:topic | a | b | exact | l |
EOF

cat > "$ROOT/projB/SESSION.md" <<'EOF'
### Predictions
| P1:need | a | b | exact | l |
| P2:topic | a | b | miss | l |
### Predictions
| P1:need | a | b | adjacent | l |
### Predictions
| # | Predicted | Actual | Accuracy | Lesson |
EOF

# Ожидаемое: секций 5; need n=6 (e5 a1 m0, acc 91), topic n=5 (e1 a0 m4, acc 20),
# untyped n=1 (a1, «выборка мала»); TOTAL решённых 12 (e6 a2 m4, acc 58).

# --- T1: scan находит оба файла в корне с пробелом --------------------------------
FILES=$(pred_scan_files "$ROOT")
assert_eq "$(printf '%s\n' "$FILES" | grep -c '')" "2" "T1 scan: два файла"
assert_contains "$FILES" "My Fixture/projA/SESSION.md" "T1 scan: путь с пробелом"

# --- T2: агрегат — известные числа ------------------------------------------------
AGG=$(printf '%s\n' "$FILES" | pred_aggregate)
assert_contains "$AGG" "TOTAL 5 12 6 2 4 58" "T2 TOTAL: секции/решённые/e/a/m/acc"
assert_contains "$AGG" "need 6 5 1 0 91" "T2 need"
assert_contains "$AGG" "topic 5 1 0 4 20" "T2 topic"
assert_contains "$AGG" "untyped 1 0 1 0 50" "T2 untyped"

# --- T3: markdown-блок — вердикты по правилу моста --------------------------------
WARN="$TMP/warn.txt"
BLOCK=$(pred_calibration_block "$ROOT" "$WARN")
assert_contains "$BLOCK" "## Prediction calibration (L4↔L5)" "T3 заголовок"
assert_contains "$BLOCK" "Секций Predictions:** 5" "T3 секции"
assert_contains "$BLOCK" "решённых предсказаний: 12" "T3 решённые"
assert_contains "$BLOCK" "| need | 6 | 5 | 1 | 0 | 91% | повысить confidence типа |" "T3 need повысить"
assert_contains "$BLOCK" "| topic | 5 | 1 | 0 | 4 | 20% | снизить confidence типа |" "T3 topic снизить"
assert_contains "$BLOCK" "выборка мала" "T3 untyped гейт типа"
assert_contains "$BLOCK" "**58%**" "T3 итог"

# --- T4: рекомендации дописаны в файл (подоболочка их не теряет) ------------------
assert_eq "$(grep -c '' "$WARN")" "2" "T4 два предупреждения"
assert_contains "$(cat "$WARN")" "topic» точны на 20%" "T4 снизить в warnfile"
assert_contains "$(cat "$WARN")" "need» точны на 91%" "T4 повысить в warnfile"

# --- T5: гейт секций — счёт есть, вердикта нет ------------------------------------
ROOT2="$TMP/small"
mkdir -p "$ROOT2/p"
cat > "$ROOT2/p/SESSION.md" <<'EOF'
### Predictions
| P1:need | a | b | exact | l |
EOF
BLOCK2=$(pred_calibration_block "$ROOT2" "$TMP/warn2.txt")
assert_contains "$BLOCK2" "вердикт по правилу моста не выносится" "T5 гейт секций"
assert_not_contains "$BLOCK2" "| need |" "T5 таблицы нет"
[ -s "$TMP/warn2.txt" ] && { FAIL=$((FAIL+1)); echo "FAIL [T5 warnfile пуст]"; } || PASS=$((PASS+1))

# --- T6: «не измеряли» — нет SESSION.md / нет секций ------------------------------
ROOT3="$TMP/empty"; mkdir -p "$ROOT3"
assert_contains "$(pred_calibration_block "$ROOT3" "")" "Не измеряли: SESSION.md не найдены" "T6 нет файлов"
ROOT4="$TMP/nosect"; mkdir -p "$ROOT4/p"
echo "# просто сессия без предсказаний" > "$ROOT4/p/SESSION.md"
assert_contains "$(pred_calibration_block "$ROOT4" "")" "Не измеряли: секций Predictions нет" "T6 нет секций"

# --- T7: pending не в знаменателе (need было бы 7 при ошибке) ---------------------
assert_not_contains "$AGG" "need 7" "T7 pending исключён"

echo ""
echo "test_metrics_predictions: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
