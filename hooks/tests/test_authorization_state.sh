#!/usr/bin/env bash
# test_authorization_state.sh — ADR-010 Ф1: авторизация как состояние задачи.
#
# Закрепляется:
#   - unit: взведение по поручению (с кириллической свёрткой регистра), гашение
#     нейтральной репликой, «продолжай» только В НАЧАЛЕ реплики;
#   - ЦЕЛЕВОЙ СЦЕНАРИЙ дефекта из ADR-010: правка после «делай», когда предыдущей
#     «user»-строкой транскрипта стала синтетика (task-notification) — событие
#     solicited, бюджет proactive НЕ расходуется;
#   - обратная сторона: без авторизации — proactive, бюджет расходуется;
#   - fallback без файла состояния (первый ход после установки): прежняя
#     одношаговая проверка по маркерам из той же библиотеки;
#   - нейтральная реальная реплика гасит состояние (записано active=false).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/itr-event-detector.sh"
AUTH_LIB="$HOOK_DIR/authorization-lib.sh"
STATE_LIB="$HOOK_DIR/intrusiveness-state-lib.sh"
for f in "$HOOK" "$AUTH_LIB" "$STATE_LIB"; do
    [ -f "$f" ] || { echo "FAIL: $f not found"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ITR_STATE_DIR="$TMP/state"
export HOME="$TMP/home"
mkdir -p "$ITR_STATE_DIR" "$HOME/.claude/hooks/state"

# shellcheck source=/dev/null
source "$STATE_LIB"
# shellcheck source=/dev/null
source "$AUTH_LIB"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- Unit: классификация и состояние ----------------------------------------------
auth_update s0 "Делай, как договорились"
M=$(auth_is_active s0) && [ "$M" = "explicit:делай" ] && ok || bad "U1" "grant с кириллической свёрткой: '$M'"
auth_update s0 "а почему получилось именно так?"
auth_is_active s0 >/dev/null && bad "U2" "нейтральная реплика не погасила" || ok
jq -e '.active == false' "$(auth_state_path s0)" >/dev/null && ok || bad "U2b" "active=false не записан"
auth_update s0 "продолжай"
auth_is_active s0 >/dev/null && ok || bad "U3" "«продолжай» в начале не взвёл"
# U4: договор изменён 29 августа 2026 (D207). Прежде авторизацию взводил только перечень
# форм, и содержательная реплика без глагола-маркера её ГАСИЛА. Замер по корпусу: из 1711
# реплик перечни признавали поручением 340 (19%), и 504 раза агент правил файлы при
# формальном «авторизации нет» — окрик на прямом поручении («Нужно интегрировать в
# систему», «Ставь debug-лог»). Теперь правило: содержательная реплика в идущей работе
# авторизует, гасят только вопрос и стоп-слово. Поэтому строка ниже — уже НЕ контрпример.
auth_update s0 "в середине текста продолжай смысл не считается"
auth_is_active s0 >/dev/null && ok || bad "U4" "содержательная реплика не взвела (правило D207)"
# Настоящий контрпример правила: вопрос авторизацией не является, какой бы длинный он ни был.
auth_update s0 "а почему тут выбран именно такой порядок обхода?"
auth_is_active s0 >/dev/null && bad "U4b" "вопрос взвёл авторизацию" || ok
# ...и стоп-слово гасит явно.
auth_update s0 "стоп, дальше не надо"
auth_is_active s0 >/dev/null && bad "U4c" "стоп-слово не погасило" || ok

# --- Транскрипт: [реальная реплика] → [синтетика] → [assistant Edit] ---------------
# prior_user, которого увидит одношаговая проверка, — СИНТЕТИКА без маркеров.
make_transcript() { # $1 out, $2 prior_user_text
    local out="$1" prior="$2"
    {
        jq -nc --arg t "$prior" '{message:{role:"user",content:[{type:"text",text:$t}]}}'
        jq -nc '{message:{role:"assistant",content:[{type:"tool_use",name:"Edit",input:{}},{type:"text",text:"Готово."}]}}'
    } > "$out"
}

run_hook() { # $1 sid, $2 transcript, $3 current_prompt
    jq -nc --arg sid "$1" --arg tp "$2" --arg pr "$3" \
        '{session_id:$sid, transcript_path:$tp, prompt:$pr}' \
        | bash "$HOOK" >/dev/null 2>&1 || true
}

last_event() { # $1 sid → "type outcome"
    jq -r '.events | last | "\(.type) \(.outcome)"' "$(_itr_state_path "$1")" 2>/dev/null
}
proactive_used() {
    jq -r '.budget.proactive_used' "$(_itr_state_path "$1")" 2>/dev/null
}

T1="$TMP/t1.jsonl"
make_transcript "$T1" "<task-notification> задача wf_x завершена, 4 агента, 250k токенов </task-notification>"

# --- S1: целевой сценарий ADR-010 — авторизация действует сквозь синтетику ---------
auth_update s1 "делай"
run_hook s1 "$T1" "спасибо, посмотрю результат позже — интересно вышло"
EV=$(last_event s1)
[ "$EV" = "solicited authorized" ] && ok || bad "S1a" "ожидалось 'solicited authorized', получено '$EV'"
PU=$(proactive_used s1)
[ "$PU" = "0" ] && ok || bad "S1b" "proactive_used=$PU, бюджет израсходован на авторизованную правку"
# S1c: по договору D207 нейтральная содержательная реплика НЕ гасит — гасят вопрос и
# стоп-слово. Проверяется именно это: состояние живо после нейтральной реплики...
auth_update s1 "спасибо, посмотрю результат позже — интересно вышло"
auth_is_active s1 >/dev/null && ok || bad "S1c" "нейтральная реплика погасила состояние (правило D207)"
# ...и гаснет после вопроса.
auth_update s1 "а зачем тут второй проход?"
auth_is_active s1 >/dev/null && bad "S1d" "вопрос не погасил состояние" || ok

# --- S2: без авторизации (файл есть, active=false) → proactive, бюджет тратится ----
auth_update s2 "а что это было?"
run_hook s2 "$T1" "спасибо, посмотрю результат позже — интересно вышло"
EV=$(last_event s2)
[ "$EV" = "proactive accepted" ] && ok || bad "S2a" "ожидалось 'proactive accepted', получено '$EV'"
PU=$(proactive_used s2)
[ "$PU" = "1" ] && ok || bad "S2b" "proactive_used=$PU, бюджет не израсходован на самовольную правку"

# --- S3: файла состояния нет — fallback по prior_user (маркер есть) ---------------
T3="$TMP/t3.jsonl"
make_transcript "$T3" "поправь заголовок в файле"
run_hook s3 "$T3" "спасибо, посмотрю результат позже — интересно вышло"
EV=$(last_event s3)
[ "$EV" = "solicited authorized" ] && ok || bad "S3" "fallback: ожидалось 'solicited authorized', получено '$EV'"

# --- S4: файла нет, prior_user нейтрален → proactive ------------------------------
T4="$TMP/t4.jsonl"
make_transcript "$T4" "как дела с проектом?"
run_hook s4 "$T4" "спасибо, посмотрю результат позже — интересно вышло"
EV=$(last_event s4)
[ "$EV" = "proactive accepted" ] && ok || bad "S4" "ожидалось 'proactive accepted', получено '$EV'"

echo ""
echo "test_authorization_state: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
