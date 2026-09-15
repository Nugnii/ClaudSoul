#!/usr/bin/env bash
# test_attack_r3_handoff_threshold_flip.sh — АТАКА: порог 500 символов у ветки
# зачина-подписи переворачивается ОДНИМ символом, и всё, что короче, не защищено
# вообще ничем.
#
# Ветка срабатывает при `_uos_len >= 500 && _uos_flen <= 100`. Ниже 500 она молчит,
# а других признаков у пересылки без markdown-разметки нет: заголовков нет, таблицы
# нет, цитатных строк нет, кодовых блоков нет. Комментарий в функции это и признаёт:
# «Пересылка без markdown-разметки ничем другим от собственной речи не отличается».
#
# Значит защита есть ровно у длинных пересылок. Пересылка на 499 символов — обычное
# сообщение из чата, реплика рецензента, кусок письма — проходит ЦЕЛИКОМ, вместе с
# чужими маркерами. Тот же текст, дописанный одним символом, гасится до одной строки.
# Один и тот же вход даёт противоположные вердикты, и граница проходит там, где чаще
# всего живёт реальная пересылка, а не там, где её нет.
#
# Обоснование порога в коде («замер по словарю состояния: выше 2750 символов есть и
# настоящая речь владельца») отвечает на вопрос «где НЕЛЬЗЯ ставить верхнюю границу»,
# а не на вопрос «что делать с тем, что ниже нижней». Ниже — дыра во всю ширину.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

uos_len() { printf '%s' "$1" | LC_ALL=C.UTF-8 wc -m | tr -d '[:space:]'; }

# Пересылка ровно заданной длины в символах: зачин-подпись + чужой текст с маркером.
mk_handoff() {  # $1 = целевая длина в символах
    local first="из соседней сессии:"
    local unit="Автор пишет, что это не совсем то, что нужно. "
    local t="$first
"
    while [ "$(uos_len "$t$unit")" -le "$1" ]; do t="$t$unit"; done
    while [ "$(uos_len "$t")" -lt "$1" ]; do t="$t."; done
    printf '%s' "$t"
}

H500=$(mk_handoff 500)
H499=$(mk_handoff 499)

# t0 — контроль: на 500 символах страж работает, тело пересылки отсечено
got=$(user_own_speech "$H500")
if grep -qF "не совсем" <<< "$got"; then
    bad "t0 handoff at 500 must be stripped" "маркер остался: ${got:0:70}"
else ok; fi

# t1 — АТАКА: тот же текст на символ короче проходит целиком
got=$(user_own_speech "$H499")
if grep -qF "не совсем" <<< "$got"; then
    bad "t1 one char below threshold leaks whole handoff" \
        "прошло $(uos_len "$got") символов чужого текста"
else ok; fi

# t2 — размер обеих строк отличается на один символ: вердикт держится не на смысле
if [ "$(uos_len "$H499")" -eq 499 ] && [ "$(uos_len "$H500")" -eq 500 ]; then ok
else bad "t2 fixture length" "длины: $(uos_len "$H499") и $(uos_len "$H500")"; fi

# t3 — обычная короткая пересылка из чата: ни одного признака, ничем не прикрыта
CHAT="переслал что мне ответили:
Коллега: посмотрел твой вариант, это не совсем то, о чём договаривались вчера.
Надо переделать первый шаг, остальное можно оставить как есть."
got=$(user_own_speech "$CHAT")
if grep -qF "не совсем" <<< "$got"; then
    bad "t3 short forwarded chat leaks" "чужие слова ушли как собственная речь"
else ok; fi

# t4 — та же дыра доходит до состояния: чужая жалоба короче 500 символов даёт stuck
ITR_LIB="$HOOKS_DIR/intrusiveness-state-lib.sh"
if [ -f "$ITR_LIB" ]; then
    TMP=$(mktemp -d)
    export ITR_STATE_DIR="$TMP"
    export STATE_DIR="$TMP"
    # shellcheck source=/dev/null
    source "$ITR_LIB" 2>/dev/null || true
    if command -v itr_compute_state >/dev/null 2>&1; then
        st=$(itr_compute_state "" "переслал что мне ответили:
Коллега: у меня опять не работает сборка, снова та же ошибка третий день." 2>/dev/null)
        case "$st" in
            stuck*) bad "t4 state from short handoff" "чужая жалоба дала состояние: $st" ;;
            *) ok ;;
        esac
    fi
fi

# t5 — сквозной: хук объявляет коррекцию на пересланном сообщении в 499 символов
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    TMP2=$(mktemp -d); mkdir -p "$TMP2/state"
    out=$(jq -nc --arg s r3t1 --arg p "$H499" \
        '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP2/state" bash "$HOOK" 2>/dev/null)
    if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
        bad "t5 hook fires BACKWARD on 499-char handoff" "хук объявил коррекцию"
    else ok; fi
fi

echo ""
echo "attack r3 handoff-threshold-flip: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
