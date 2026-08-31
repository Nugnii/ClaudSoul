#!/usr/bin/env bash
# test_intrusiveness_tracker.sh — характеризующий тест хука-обёртки.
# Сама intrusiveness-state-lib покрыта (182 ассерта в test_intrusiveness_lib);
# здесь — тонкая обёртка UserPromptSubmit: читает состояние и инжектит секцию.
# Тест закрывает F8 для обёртки: fresh-сессия молчит, без SID молчит, не падает.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/intrusiveness-tracker.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_silent() {
    if [ -z "$1" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $1"; fi
}
assert_rc0() {
    if [ "$1" -eq 0 ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1 (ожидался 0)"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

run() {  # $1=session_id $2=prompt
    printf '{"session_id":"%s","prompt":"%s"}' "$1" "$2" \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# fresh-сессия: первый turn создаёт пустой scaffold → инжекта ещё нет (тишина)
out=$(run "fresh-sid" "обычный вопрос"); rc=$?
assert_silent "$out" "T1 fresh session → silent"
assert_rc0 "$rc" "T1 rc=0"

# без session_id → ранний выход, тишина
out=$(run "" "вопрос"); rc=$?
assert_silent "$out" "T2 no session_id → silent"
assert_rc0 "$rc" "T2 rc=0"

# повторный вызов той же сессии не падает (idempotent init)
out=$(run "fresh-sid" "ещё вопрос"); rc=$?
assert_rc0 "$rc" "T3 repeat call rc=0"

# === T4: доказательство СРАБАТЫВАНИЯ (v1.12.4) ===
# До этого тест состоял из трёх проверок тишины и одной на код возврата. Пустой
# файл прошёл бы его целиком: молчание доказывает только молчание. Мета-тест
# `test_guards_provable.sh` это назвал — здесь долг закрыт.
#
# Хук инжектит состояние гейта, когда в сессии уже есть накопленное состояние.
# Прогоняем несколько ходов подряд, пока scaffold не наполнится, и требуем вывод.
assert_nonsilent() {
    if [ -n "$1" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидался вывод, получена тишина"; fi
}
# Пустой сессии мало: `itr_format_context` намеренно возвращает пусто, пока в
# состоянии нет ничего интересного (иначе инжект шумел бы на каждом первом ходу).
# Значит для доказательства срабатывания состояние надо наполнить — событием.
run "warm-sid" "первый ход" >/dev/null 2>&1
( STATE_DIR="$TMP/state"; export STATE_DIR
  # shellcheck source=/dev/null
  source "$HOOKS_DIR/intrusiveness-state-lib.sh" 2>/dev/null \
    && itr_log_event "warm-sid" gentle accepted 2 "фикстура теста" >/dev/null 2>&1 ) || true
out=$(run "warm-sid" "продолжаем работу")
assert_nonsilent "$out" "T4 состояние наполнено → хук говорит (не пустой файл)"
if [ -n "$out" ]; then
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [T4b]: вывод не валидный hookSpecificOutput: $out"
    fi
fi

echo ""
echo "intrusiveness-tracker tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
