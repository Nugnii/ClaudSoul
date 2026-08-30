#!/usr/bin/env bash
# test_attack_r2_stuck_becomes_focus.sh — АТАКА: приложенный лог в цитате не просто
# теряет stuck, а переворачивает состояние в его противоположность — focus.
#
# itr_compute_state читает ось stuck по `user_own_speech "$text" soft`, а оси
# focus/exploration — по ПОЛНОМУ `$text`. Две строки, начинающиеся с `>`, обнуляют
# собственную речь целиком (счётчик quoted >= 2), поэтому «опять не работает» до оси
# stuck не доходит. Приложенный лог при этом остаётся виден оси focus: он длинный и
# несёт технические маркеры (`Error:`, `src/app.ts:42`, `step 3`) — score_focus
# набирает 2, и приоритет отдаёт focus.
#
# Разворот именно смысловой, а не «сигнал ослаб»: stuck говорит гейту «собеседник
# буксует, вмешательства урезать», focus говорит «собеседник в работе». Из реплики
# «опять не работает, третий раз подряд» получается вердикт «человек сосредоточен».
#
# Цитирование лога через `>` — обычная форма показать вывод, а не редкий случай.
# Это НЕ шапка D89 (там короткая вставка ПОДНИМАЕТ stuck): здесь наоборот, настоящий
# сигнал собеседника теряется и подменяется чужим.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }

TMP=$(mktemp -d)
export ITR_STATE_DIR="$TMP"
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
state_of() { itr_compute_state "" "$1" | cut -d'|' -f1; }

COMPLAINT="опять не работает, третий раз подряд"
LOG2=$(awk 'BEGIN { for (i = 0; i < 10; i++) print "> Error: build step " i " failed at src/app.ts:42" }')
LOG1='> Error: build step failed at src/app.ts:42'

# t0 — контроль: голая жалоба даёт stuck
got=$(state_of "$COMPLAINT")
if [ "$got" = "stuck" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [t0 контроль: голая жалоба]: ожидалось stuck, получено '$got'"; fi

# t1 — контроль: с ОДНОЙ строкой цитаты сигнал ещё жив
got=$(state_of "$COMPLAINT
$LOG1")
if [ "$got" = "stuck" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [t1 контроль: одна строка цитаты]: ожидалось stuck, получено '$got'"; fi

# t2 — АТАКА: со второй строкой цитаты состояние переворачивается
got=$(state_of "$COMPLAINT
$LOG2")
if [ "$got" = "stuck" ]; then PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [t2 жалоба + лог в цитате]: ожидалось stuck, получено '$got' — сигнал собеседника потерян"
fi

# t3 — отдельно: вердикт не должен быть focus (это прямая противоположность)
got=$(state_of "$COMPLAINT
$LOG2")
if [ "$got" = "focus" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [t3 разворот]: буксующий собеседник классифицирован как focus"
else PASS=$((PASS + 1)); fi

# t4 — тот же лог БЕЗ жалобы не должен внезапно оказаться собранным собеседником
#      (граница: если чинить обнулением quoted, чужой лог не обязан давать stuck)
got=$(state_of "$LOG2")
if [ "$got" = "stuck" ]; then
    FAIL=$((FAIL + 1)); echo "FAIL [t4 чужой лог без собственной речи дал stuck]: '$got'"
else PASS=$((PASS + 1)); fi

rm -rf "$TMP"
echo ""
echo "attack r2 stuck-becomes-focus: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
