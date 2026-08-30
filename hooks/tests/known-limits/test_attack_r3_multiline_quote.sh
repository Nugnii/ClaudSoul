#!/usr/bin/env bash
# test_attack_r3_multiline_quote.sh — АТАКА: вырезание чужой прямой речи работает
# только внутри ОДНОЙ строки, поэтому цитата, перенесённая на вторую строку, проходит
# целиком.
#
# `gsub(/"[^"]*"/, " ", line)` живёт в теле awk, а awk обрабатывает вход построчно.
# Пока чужая реплика умещается в строку, страж раунда 1 (атака 6) её снимает. Стоит
# той же чужой реплике занять две строки — открывающая кавычка остаётся в первой,
# закрывающая во второй, ни в одной строке пары нет, и gsub не находит НИЧЕГО.
#
# Форма не экзотическая, а обычная: цитируют письмо, реплику из другого чата, абзац
# рецензии. Перенос строки внутри цитаты появляется сам собой при копировании.
#
# Разница с закрытой атакой раунда 2 (test_attack_r2_handoff_header_raw.sh): там
# заголовок уходил сырым через ВЕТКУ зачина-подписи, то есть в обход awk. Здесь awk
# отрабатывает штатно и всё равно ничего не вырезает — дыра в самом стражe, а не в
# обходном пути мимо него.
#
# Итог: собеседник цитирует чужую критику и с ней НЕ соглашается («а по-моему
# нормально»), а reformulation-tracker читает чужие слова как его собственную коррекцию.

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

assert_stripped() {  # $1=текст $2=маркер, которого быть НЕ должно $3=имя
    local got; got=$(user_own_speech "$1")
    if grep -qF "$2" <<< "$got"; then
        bad "$3" "чужой маркер '$2' остался: $(printf '%s' "$got" | tr '\n' '/' | cut -c1-100)"
    else ok; fi
}
assert_keeps() {  # $1=текст $2=подстрока, обязанная остаться $3=имя
    local got; got=$(user_own_speech "$1")
    if grep -qF "$2" <<< "$got"; then ok
    else bad "$3" "'$2' пропало из собственной речи"; fi
}

ONE_LINE='он написал:
"это не совсем то, что ты предлагаешь, и вообще всё иначе"
а по-моему нормально'

TWO_LINES='он написал:
"это не совсем то, что ты предлагаешь,
и вообще всё иначе"
а по-моему нормально'

# t0 — контроль: та же цитата в одну строку вырезается
assert_stripped "$ONE_LINE" "не совсем" "t0 single-line quote stripped"

# t1 — АТАКА: перенос строки внутри цитаты — и она проходит целиком
assert_stripped "$TWO_LINES" "не совсем" "t1 multiline quote leaks"

# t2 — граница не должна уехать в другую сторону: своя часть обязана остаться
assert_keeps "$TWO_LINES" "по-моему нормально" "t2 own part still kept"

# t3 — та же дыра с маркером состояния внутри многострочной цитаты
assert_stripped 'коллега пишет:
"опять не работает сборка,
третий день подряд"
у меня всё собирается' "опять" "t3 state marker leaks"

# t4 — та же дыра на оси состояния: чужая жалоба поднимает stuck
ITR_LIB="$HOOKS_DIR/intrusiveness-state-lib.sh"
if [ -f "$ITR_LIB" ]; then
    TMP=$(mktemp -d)
    export ITR_STATE_DIR="$TMP"
    export STATE_DIR="$TMP"
    # shellcheck source=/dev/null
    source "$ITR_LIB" 2>/dev/null || true
    if command -v itr_compute_state >/dev/null 2>&1; then
        st=$(itr_compute_state "" 'коллега пишет:
"опять не работает сборка,
третий день подряд"
у меня всё собирается' 2>/dev/null)
        case "$st" in
            stuck*) bad "t4 state from foreign multiline quote" "чужая жалоба дала состояние: $st" ;;
            *) ok ;;
        esac
    fi
fi

# t5 — сквозной: хук объявляет коррекцию на цитате, с которой собеседник не согласен
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    TMP2=$(mktemp -d); mkdir -p "$TMP2/state"
    out=$(jq -nc --arg s r3m1 --arg p "$TWO_LINES" \
        '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP2/state" bash "$HOOK" 2>/dev/null)
    if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
        bad "t5 hook fires BACKWARD on quoted foreign critique" "хук объявил коррекцию"
    else ok; fi
fi

echo ""
echo "attack r3 multiline-quote: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
