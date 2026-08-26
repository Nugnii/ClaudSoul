#!/usr/bin/env bash
# test_reformulation_tracker.sh — характеризующий тест каскадной верификации
# предсказаний (FORWARD/PROPOSAL/BACKWARD). Хук был без своего теста (F8);
# он центральный для L4/L6 — регрессия прошла бы молча. Изоляция через STATE_DIR.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_contains() {
    if grep -qF "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: '$2' not in output"; fi
}
assert_silent() {
    if [ -z "$1" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $1"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

make_transcript() {
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TMP/t.jsonl"
    echo "$TMP/t.jsonl"
}

run() {  # $1=user_prompt $2=transcript_path $3=sid
    printf '{"session_id":"%s","prompt":"%s","transcript_path":"%s"}' "$3" "$1" "$2" \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# T1 — BACKWARD: маркер коррекции в текущем сообщении
out=$(run "это совсем не так" "" "s1")
assert_contains "$out" "КОРРЕКТИРУЕТ" "T1 BACKWARD"

# T2 — FORWARD: переформулировка в прошлом ответе агента
tr=$(make_transcript "правильно ли я понимаю задачу")
out=$(run "да, верно" "$tr" "s2")
assert_contains "$out" "переформулировку" "T2 FORWARD"

# T3 — PROPOSAL: предложение в прошлом ответе агента
tr=$(make_transcript "предлагаю сделать через вариант X")
out=$(run "ок давай" "$tr" "s3")
assert_contains "$out" "предложение" "T3 PROPOSAL"

# T4 — приоритет BACKWARD > FORWARD
tr=$(make_transcript "переформулирую задачу так")
out=$(run "actually нет, не это" "$tr" "s4")
assert_contains "$out" "КОРРЕКТИРУЕТ" "T4 priority BACKWARD>FORWARD"

# T4a-T4c — граница слова: подстрока ≠ смысл (v1.14.1)
#
# Реальный случай. На реплику «Ахиренная штука 5 почему… т.е. проверять нужно НЕ ТОЛЬКО
# причины ошибок» хук объявил «Пользователь КОРРЕКТИРУЕТ». Это было согласие, развивающее
# мысль, а совпал маркер «не то» внутри слова «только». Метрика точности предсказаний
# получала miss там, где предсказание было верным.
out=$(run "проверять нужно не только причины ошибок" "" "s4a")
assert_silent "$out" "T4a «не только» — не коррекция"
out=$(run "это не такой случай как раньше" "" "s4b")
assert_silent "$out" "T4b «не такой» — не коррекция"
# Обратная сторона обязательна: настоящая коррекция теми же словами обязана гореть.
out=$(run "нет, не то, я про другое" "" "s4c")
assert_contains "$out" "КОРРЕКТИРУЕТ" "T4c «не то» отдельным словом — коррекция"

# T5 — нет триггеров → тишина
out=$(run "просто обычный вопрос про погоду" "" "s5")
assert_silent "$out" "T5 silent when no trigger"

# T6 — dedup: тот же turn (assistant+prompt) во второй раз → тишина
tr=$(make_transcript "правильно ли я понимаю")
_=$(run "мой ответ" "$tr" "s6")
out2=$(run "мой ответ" "$tr" "s6")
assert_silent "$out2" "T6 dedup second call silent"

# T7 — системный turn (task-notification) с маркером в теле → тишина
# (pattern-guard-scope-blindness: «не совсем» в tool_result — не речь юзера)
out=$(run "<task-notification> H3 не совсем подходит </task-notification>" "" "s7")
assert_silent "$out" "T7 system turn (task-notification) not scanned"

# T8 — эхо slash-команды с маркером в выводе → тишина
out=$(run "<local-command-stdout> результат не так выглядит </local-command-stdout>" "" "s8")
assert_silent "$out" "T8 slash-command output not scanned"

echo ""
echo "reformulation-tracker tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
