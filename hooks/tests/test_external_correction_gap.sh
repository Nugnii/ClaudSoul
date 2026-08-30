#!/usr/bin/env bash
# test_external_correction_gap.sh — детекция внешней рецензии и требование гэп-разбора.
# Изоляция через STATE_DIR env var (образец: test_decompose_detector.sh).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/external-correction-gap.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
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
mkdir -p "$STATE_DIR"

run_with() {
    local sid="$1" prompt="$2"
    printf '{"session_id":"%s","user_prompt":%s}' "$sid" "$(printf '%s' "$prompt" | jq -Rs .)" | \
        STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null
}

# --- T1: маркер «рецензент» → fire с требованием гэп-разбора ---
OUT=$(run_with "sid1" "Я дал ссылку на репозиторий для оценки и вот вердикт рецензента: система перегружена")
assert_contains "$OUT" "Внешняя рецензия" "T1: маркер рецензента детектирован"
assert_contains "$OUT" "катчабельна ли она внутренним знанием" "T1b: требование классификации"
assert_contains "$OUT" "минимум 3 уровня" "T1c: требование цепочки почему"

# --- T2: нейтральный prompt → silent ---
OUT=$(run_with "sid2" "поправь функцию в activity-flush и добавь тест на пустой ввод")
assert_empty "$OUT" "T2: нейтральный prompt игнорируется"

# --- T3: «сделай ревью» — просьба ко мне, не внешняя правка → silent ---
OUT=$(run_with "sid3" "сделай code review моего модуля и скажи что не так")
assert_empty "$OUT" "T3: просьба о ревью не считается внешней рецензией"

# --- T4: постоянный механизм — второй раунд рецензии в той же сессии тоже fire ---
OUT=$(run_with "sid1" "рецензент прислал ещё замечания, вот они")
assert_contains "$OUT" "Внешняя рецензия" "T4: повторный раунд в той же сессии срабатывает"

# --- T5: заглавная кириллица «Вердикт» → fire (свёртка регистра) ---
OUT=$(run_with "sid5" "Вердикт по проекту прилагаю ниже")
assert_contains "$OUT" "Внешняя рецензия" "T5: заглавный маркер детектирован"

# --- T6: distressed state → silent (AP2) ---
printf '{"state_axis":"distressed"}' > "$STATE_DIR/intrusiveness-sid6.json"
OUT=$(run_with "sid6" "вердикт рецензента: всё плохо")
assert_empty "$OUT" "T6: distressed глушит инжект"

# --- T8: системное уведомление с маркером → silent (эхо своих слов — не рецензия) ---
OUT=$(run_with "sid8" "[SYSTEM NOTIFICATION - NOT USER INPUT] <task-notification> Monitor event: вердикт прогона CI </task-notification>")
assert_empty "$OUT" "T8: системное уведомление игнорируется"

# --- T7: нет session_id → silent, не падает ---
OUT=$(printf '{"user_prompt":"вердикт рецензента"}' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T7: без session_id тихий выход"

echo "test_external_correction_gap: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
