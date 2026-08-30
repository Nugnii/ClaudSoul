#!/usr/bin/env bash
# test_hook_input_lib.sh — is_non_user_turn: системные/инструментальные turn'ы
# vs речь юзера. Единый источник scope-guard'а для language-marker хуков.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/hook-input-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
assert_system() {
    if is_non_user_turn "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидался системный turn"; fi
}
assert_user() {
    if is_non_user_turn "$1"; then FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась речь юзера"
    else PASS=$((PASS + 1)); fi
}

# Системные turn'ы (маркер коррекции в теле НЕ должен считаться речью)
assert_system "<task-notification><result>не совсем</result></task-notification>" "task-notification"
assert_system "prefix <local-command-stdout>не так выглядит</local-command-stdout>" "local-command-stdout"
assert_system "<command-name>/effort</command-name>" "command-name"
assert_system "<bash-stdout>output не то</bash-stdout>" "bash-stdout"
assert_system "<tool-use-error>err</tool-use-error>" "tool-use-error"

# Настоящая речь юзера (в т.ч. с маркерами коррекции — должна детектироваться дальше)
assert_user "нет, не совсем то" "real correction"
assert_user "обычный вопрос про погоду" "plain user"
assert_user "" "empty"

# --- user_own_speech: авторство высказывания внутри реплики (D87) ---
# is_non_user_turn отвечает «кто прислал turn», user_own_speech — «чьи слова внутри».
assert_silent_speech() {
    local got; got=$(user_own_speech "$1")
    if [ -z "$got" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась пустая собственная речь, получено: ${got:0:60}"; fi
}
assert_keeps() {  # $1=текст $2=подстрока, которая должна остаться $3=имя
    local got; got=$(user_own_speech "$1")
    if grep -qF "$2" <<< "$got"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: '$2' не сохранилось в собственной речи"; fi
}

assert_silent_speech "Base directory for this skill: /x
# скилл
текст не совсем такой" "skill body"
assert_silent_speech "This session is being continued from a previous conversation.
Пользователь сказал не совсем то." "continuation summary"
assert_silent_speech "Review target: \`--effort high\`
раздел не так работает" "command report"
# Объём фикстуры доведён до реалистичного: признак документа гасит реплику только при
# теле от 300 непробельных символов, иначе гасла бы своя короткая жалоба с приложением
# (раунд 1 атака 3 t6, раунд 2 атака 5 t3). Настоящие пересылки в выборке — 3512 и 7483
# символа, прежняя фикстура была на 120 и реальность не представляла.
PASTED_DOC="# Документ

## Раздел

Автор пишет не совсем то, и дальше идёт связный разбор на несколько абзацев подряд.
$(for _i in 1 2 3 4 5 6; do printf 'Ещё один абзац пересланного текста, каких в настоящей пересылке десятки.\n'; done)

| a | b |
|---|---|"
assert_silent_speech "$PASTED_DOC" "pasted document with headers and table"
assert_silent_speech "> первая строка цитаты
> вторая строка цитаты не совсем такая" "two quoted lines = pasted"

# Зачин-подпись: короткая строка с двоеточием перед длинным чужим текстом
LONG_HANDOFF="из соседней сессии:

$(printf 'разбор идёт по кругу, снова тот же вопрос про сжатие. %.0s' $(seq 1 20))"
# Тело пересылки отсечено, а сам зачин остаётся своей речью
_own=$(user_own_speech "$LONG_HANDOFF")
if grep -qF "снова" <<< "$_own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [handoff body must be stripped]"
else PASS=$((PASS + 1)); fi
assert_keeps "$LONG_HANDOFF" "из соседней сессии:" "handoff line itself stays own speech"
# Своя жалоба с приложенным логом: маркер в зачине настоящий, тело чужое
_own=$(user_own_speech "опять не работает — git push error:
$(printf 'stack trace line %.0s' $(seq 1 40))")
if grep -qF "опять не работает" <<< "$_own"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [own complaint before pasted log must survive]"; fi
# Тот же зачин, но текст короткий — это своя реплика, не пересылка
assert_keeps "смотри:
опять не так" "опять не так" "short body after colon stays own speech"

# Прямая речь сохраняется целиком
assert_keeps "нет, не совсем то" "не совсем" "plain correction kept"
assert_keeps "он пишет:

> тут не совсем так

а по-моему ты неверно понял" "неверно понял" "mixed: direct part kept"
# Цитата вырезается даже когда прямая часть остаётся
own=$(user_own_speech "он пишет:

> тут не совсем так

а по-моему ты неверно понял")
if grep -qF "не совсем" <<< "$own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [mixed: quoted part must be stripped]"
else PASS=$((PASS + 1)); fi
# Код-блок не является речью
own=$(user_own_speech "смотри вывод:
\`\`\`
error: не так собрано
\`\`\`
почини")
if grep -qF "не так" <<< "$own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [fenced block must be stripped]"
else PASS=$((PASS + 1)); fi

echo ""
echo "hook-input-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
