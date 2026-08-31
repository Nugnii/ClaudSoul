#!/usr/bin/env bash
# Unit tests for fsrs-lib.sh
# Run: bash hooks/tests/test_fsrs_lib.sh

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/fsrs-lib.sh"
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: expected='$expected' actual='$actual'")
    fi
}

# --- fsrs_stability ---
assert_eq "stability cc=0 impact=1" 7  "$(fsrs_stability 0 1)"
assert_eq "stability cc=1 impact=1" 11 "$(fsrs_stability 1 1)"   # 7×1.5 = 10.5 → 11
assert_eq "stability cc=5 impact=5" 49 "$(fsrs_stability 5 5)"
assert_eq "stability cc=10 impact=3" 63 "$(fsrs_stability 10 3)"
assert_eq "stability defaults (no args)" 7 "$(fsrs_stability)"
assert_eq "stability bad cc falls back to 0" 7 "$(fsrs_stability abc 1)"
assert_eq "stability bad impact falls back to 1" 7 "$(fsrs_stability 0 xyz)"
assert_eq "stability impact clamp to 5" 49 "$(fsrs_stability 5 99)"  # 7×3.5×2 = 49

# --- fsrs_days_overdue (календарный фоллбек: реестра сессий нет) ---
# /dev/null существует и пуст → эти проверки детерминированы на любой машине и
# не зависят от живого ~/.claude/sessions/registry.jsonl.
FSRS_SESSION_REGISTRY=/dev/null
TODAY=$(date +%Y-%m-%d)
# Future last_confirmed → negative overdue (fresh with stability buffer)
LC_TODAY="$TODAY"
RESULT_TODAY=$(fsrs_days_overdue "$LC_TODAY" 0 1)
# cc=0, impact=1 → stability=7. today - today = 0. 0 - 7 = -7.
assert_eq "overdue today cc=0 impact=1 → -7" "-7" "$RESULT_TODAY"

# Invalid date → 0
assert_eq "overdue invalid date → 0" 0 "$(fsrs_days_overdue 'not-a-date' 0 1)"
# Empty date → 0
assert_eq "overdue empty date → 0" 0 "$(fsrs_days_overdue '' 0 1)"

# Deterministic: 2026-01-01 with cc=0 impact=1 (stab=7). Given today is 2026-04-20,
# days_since = 109. overdue = 109 - 7 = 102.
# Note this test assumes TODAY=2026-04-20. Gate by date to avoid false fails.
if [ "$TODAY" = "2026-04-20" ]; then
    assert_eq "overdue 2026-01-01 cc=0 i=1 on 2026-04-20 → 102" 102 "$(fsrs_days_overdue 2026-01-01 0 1)"
fi

# --- fsrs_experience_days_since (D234: прошедшее — прожитые сессии, не календарь) ---
if command -v jq >/dev/null 2>&1; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

    # 30 сессий 29-го + 60 сессий 30-го; s1 задвоена — уникальность по session_id.
    REG="$TMP/reg.jsonl"
    { for i in $(seq 1 30); do printf '{"session_id":"a%s","started_at":"2026-08-29T10:00:00Z"}\n' "$i"; done
      for i in $(seq 1 60); do printf '{"session_id":"b%s","started_at":"2026-08-30T10:00:00Z"}\n' "$i"; done
      printf '{"session_id":"a1","started_at":"2026-08-29T18:00:00Z"}\n'; } > "$REG"
    FSRS_SESSION_REGISTRY="$REG"
    # после 28-го — 90 сессий / темп 30 = 3 дня опыта
    assert_eq "exp: 90 сессий после даты → 3" 3 "$(fsrs_experience_days_since 2026-08-28)"
    # сессии дня подтверждения не считаются (как раньше days_since=0 в тот же день)
    assert_eq "exp: тот же день → 0" 0 "$(fsrs_experience_days_since 2026-08-30)"
    assert_eq "exp: overdue = 3 - 7 = -4" "-4" "$(fsrs_days_overdue 2026-08-28 0 1)"
    # дефект-повод D234: месяцы календаря без сессий НЕ старят знание
    REG2="$TMP/reg2.jsonl"
    for i in $(seq 1 30); do printf '{"session_id":"c%s","started_at":"2026-01-05T10:00:00Z"}\n' "$i"; done > "$REG2"
    FSRS_SESSION_REGISTRY="$REG2"
    assert_eq "exp: 8 месяцев тишины, 30 сессий → 1 день опыта" 1 "$(fsrs_experience_days_since 2026-01-01)"
    assert_eq "exp: тишина не роняет в overdue" "-6" "$(fsrs_days_overdue 2026-01-01 0 1)"
    # нечитаемая дата → пусто (fsrs_days_overdue превращает в 0)
    assert_eq "exp: мусорная дата → пусто" "" "$(fsrs_experience_days_since not-a-date)"
    assert_eq "exp: overdue мусорной даты → 0" 0 "$(fsrs_days_overdue not-a-date 0 1)"
    FSRS_SESSION_REGISTRY=/dev/null
fi

# --- fsrs_review_status ---
assert_eq "status -10 → fresh"    "fresh"    "$(fsrs_review_status -10)"
assert_eq "status 0 → fresh"      "fresh"    "$(fsrs_review_status 0)"
assert_eq "status 1 → due"        "due"      "$(fsrs_review_status 1)"
assert_eq "status 7 → due"        "due"      "$(fsrs_review_status 7)"
assert_eq "status 8 → overdue"    "overdue"  "$(fsrs_review_status 8)"
assert_eq "status 30 → overdue"   "overdue"  "$(fsrs_review_status 30)"
assert_eq "status 31 → critical"  "critical" "$(fsrs_review_status 31)"
assert_eq "status 999 → critical" "critical" "$(fsrs_review_status 999)"
assert_eq "status empty → fresh"  "fresh"    "$(fsrs_review_status '')"

# --- fsrs_score_penalty_num ---
assert_eq "penalty fresh"    100 "$(fsrs_score_penalty_num fresh)"
assert_eq "penalty due"      100 "$(fsrs_score_penalty_num due)"
assert_eq "penalty overdue"  80  "$(fsrs_score_penalty_num overdue)"
assert_eq "penalty critical" 50  "$(fsrs_score_penalty_num critical)"
assert_eq "penalty unknown"  100 "$(fsrs_score_penalty_num junk)"

# --- fsrs_marker ---
assert_eq "marker fresh empty"          ""                    "$(fsrs_marker fresh)"
assert_eq "marker due"                  "⏳ due review"       "$(fsrs_marker due)"
assert_eq "marker overdue"              "⚠️ overdue"          "$(fsrs_marker overdue)"
assert_eq "marker critical"             "🔴 critical overdue" "$(fsrs_marker critical)"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    for f in "${FAILED_TESTS[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
exit 0
