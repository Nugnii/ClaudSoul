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

echo ""
echo "hook-input-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
