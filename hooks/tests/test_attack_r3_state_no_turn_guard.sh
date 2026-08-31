#!/usr/bin/env bash
# test_attack_r3_state_no_turn_guard.sh — АТАКА: у третьего потребителя нет верхнего
# стража вовсе. Системный turn доходит до классификатора состояния и назначает
# собеседнику состояние по словам, которых он не писал.
#
# hook-input-lib.sh объявляет себя «единым источником scope-guard'а для language-marker
# хуков»: is_non_user_turn отвечает «кто прислал turn», user_own_speech — «чьи слова
# внутри». Пару зовут два хука из трёх:
#   reformulation-tracker.sh — is_non_user_turn + user_own_speech;
#   itr-event-detector.sh    — is_non_user_turn + user_own_speech;
#   intrusiveness-tracker.sh — НИ РАЗУ. Он берёт `.prompt` и сразу отдаёт его в
#                              itr_compute_state, где стоит только user_own_speech.
#
# user_own_speech заменой не служит: она вырезает разметку, а не отправителя. Тело
# `<bash-stdout>` или `<task-notification>` — обычный текст без заголовков, таблиц и
# цитат, поэтому проходит целиком. Состояние при этом не «одно из трёх мнений»:
# intrusiveness-tracker его ЗАПИСЫВАЕТ в файл сессии, и 4D gate читает оттуда весь ход.
#
# Достижимость проверена частично: в 40 недавних транскриптах нашлось 53 user-turn'а
# с такими тегами, и сам guard в двух других хуках поставлен по инциденту
# (case-2026-06-21 «детектор скан не той области») — то есть проект видел эти строки
# именно в поле prompt. Живое событие UserPromptSubmit я не наблюдал.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
ITR_LIB="$HOOKS_DIR/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
[ -f "$ITR_LIB" ] || { echo "FAIL: $ITR_LIB not found"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
export ITR_STATE_DIR="$TMP"
export STATE_DIR="$TMP"
# shellcheck source=/dev/null
source "$ITR_LIB" 2>/dev/null || true
command -v itr_compute_state >/dev/null 2>&1 || { echo "FAIL: itr_compute_state недоступна"; exit 1; }

SYS_BASH='<bash-stdout>make: опять не работает цель build, снова та же ошибка</bash-stdout>'
SYS_TASK='<task-notification>субагент вернул: помогите, тест падает</task-notification>'
SYS_CMD='<local-command-stdout>прогон: опять не работает, снова падает</local-command-stdout>'

# t0 — контроль: верхний страж эти строки опознаёт, значит вопрос не в распознавании
# shellcheck source=/dev/null
source "$LIB"
if is_non_user_turn "$SYS_BASH" && is_non_user_turn "$SYS_TASK" && is_non_user_turn "$SYS_CMD"; then ok
else bad "t0 is_non_user_turn recognises tags" "страж не опознал системные строки"; fi

# t1 — АТАКА: классификатор состояния читает вывод команды как речь собеседника
st=$(itr_compute_state "" "$SYS_BASH" 2>/dev/null)
case "$st" in
    stuck*) bad "t1 bash-stdout raises stuck" "вывод команды дал состояние: $st" ;;
    *) ok ;;
esac

# t2 — АТАКА: отчёт субагента поднимает distressed — высший приоритет, режет весь ход
st=$(itr_compute_state "" "$SYS_TASK" 2>/dev/null)
case "$st" in
    distressed*) bad "t2 task-notification raises distressed" "отчёт субагента дал состояние: $st" ;;
    *) ok ;;
esac

# t3 — АТАКА: эхо slash-команды
st=$(itr_compute_state "" "$SYS_CMD" 2>/dev/null)
case "$st" in
    stuck*) bad "t3 command echo raises stuck" "эхо команды дало состояние: $st" ;;
    *) ok ;;
esac

# t4 — сквозной: хук ЗАПИСЫВАЕТ это состояние в файл сессии, где его читает 4D gate
HOOK="$HOOKS_DIR/intrusiveness-tracker.sh"
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    TMP2=$(mktemp -d)
    jq -nc --arg s r3g1 --arg p "$SYS_BASH" '{session_id:$s,prompt:$p}' \
        | STATE_DIR="$TMP2" ITR_STATE_DIR="$TMP2" bash "$HOOK" >/dev/null 2>&1 || true
    persisted=$(jq -r '.state.current // "none"' "$TMP2/intrusiveness-r3g1.json" 2>/dev/null || echo "none")
    if [ "$persisted" = "stuck" ] || [ "$persisted" = "distressed" ]; then
        bad "t4 state persisted from system turn" "в файле сессии записано current=$persisted"
    else ok; fi
fi

# t5 — граница: настоящая жалоба собеседника обязана остаться слышимой
st=$(itr_compute_state "" "опять не работает, снова та же ошибка" 2>/dev/null)
case "$st" in
    stuck*) ok ;;
    *) bad "t5 real complaint still heard" "настоящая жалоба дала состояние: $st" ;;
esac

echo ""
echo "attack r3 state-no-turn-guard: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
