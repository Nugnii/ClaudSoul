#!/usr/bin/env bash
# СУДИТ: hooks/test-exit-explicit-guard.sh
# test_test_exit_explicit_guard.sh — страж момента записи: тест в старой форме кода
# возврата в дерево не записывается (D338).
#
# Предикат один — hooks/tests/test_tests_exit_explicit.sh; здесь проверяется, что страж
# собирает ИТОГ правки верно (Write — целиком, Edit — замена, MultiEdit — по очереди) и
# отказывает ровно тогда, когда итог кончается не явным exit. Фикстурное дерево — своё:
# страж ищет предикат по корню правимого файла, а не по корню сессии, поэтому чужое дерево
# без предиката проверяется отдельной ногой.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/test-exit-explicit-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
decision() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$1" 2>/dev/null; }
reason()   { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$1" 2>/dev/null; }
# Утверждения о срабатывании и тишине — ролью: страж отказал / страж промолчал.
denied() { [ "$(decision "$1")" = "deny" ]; }
assert_empty() { [ -z "$1" ] && ok || bad "$2" "страж заговорил: $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/tree"; mkdir -p "$ROOT/hooks/tests" "$ROOT/hooks/lib"
cp "$HOOKS_DIR/tests/test_tests_exit_explicit.sh" "$HOOKS_DIR/tests/universe-lib.sh" "$ROOT/hooks/tests/"
cp "$HOOKS_DIR/lib/universe-lib.sh" "$ROOT/hooks/lib/"

OLD=$'#!/usr/bin/env bash\nPASS=0; FAIL=0\n[ 1 = 1 ] && PASS=1\necho "t: $PASS passed, $FAIL failed"\n[ "$FAIL" -eq 0 ]\n'
NEW=$'#!/usr/bin/env bash\nPASS=0; FAIL=0\n[ 1 = 1 ] && PASS=1\necho "t: $PASS passed, $FAIL failed"\nexit $(( FAIL != 0 ))\n'

write_payload() { jq -cn --arg f "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
edit_payload()  { jq -cn --arg f "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}'; }
run() { bash "$HOOK" 2>/dev/null; }

# T1: Write в старой форме — отказ, и причина называет явный exit.
OUT=$(write_payload "$ROOT/hooks/tests/test_new.sh" "$OLD" | run)
if denied "$OUT"; then ok; else bad T1 "старая форма записана без отказа: ${OUT:-<пусто>}"; fi
grep -q 'явным exit' <<< "$(reason "$OUT")" && ok || bad T1b "причина не называет правило: $(reason "$OUT")"

# T2: Write с явным exit — тишина.
OUT=$(write_payload "$ROOT/hooks/tests/test_new.sh" "$NEW" | run)
assert_empty "$OUT" T2

# T3: Edit, дописывающий строку ПОСЛЕ exit — итог кончается не exit, отказ.
printf '%s' "$NEW" > "$ROOT/hooks/tests/test_live.sh"
OUT=$(edit_payload "$ROOT/hooks/tests/test_live.sh" 'exit $(( FAIL != 0 ))' $'exit $(( FAIL != 0 ))\necho "done"' | run)
if denied "$OUT"; then ok; else bad T3 "правка, ломающая концовку, прошла: ${OUT:-<пусто>}"; fi

# T4: Edit внутри тела — концовка цела, тишина.
OUT=$(edit_payload "$ROOT/hooks/tests/test_live.sh" '[ 1 = 1 ]' '[ 2 = 2 ]' | run)
assert_empty "$OUT" T4

# T5: старой половины в файле нет — итог неизвестен, страж молчит (отказ назовёт инструмент).
OUT=$(edit_payload "$ROOT/hooks/tests/test_live.sh" 'нет такой строки' 'x' | run)
assert_empty "$OUT" T5

# T6: MultiEdit — первая правка безобидна, вторая ломает концовку; итог собирается по очереди.
OUT=$(jq -cn --arg f "$ROOT/hooks/tests/test_live.sh" '{tool_name:"MultiEdit",tool_input:{file_path:$f,edits:[
        {old_string:"[ 1 = 1 ]",new_string:"[ 3 = 3 ]"},
        {old_string:"exit $(( FAIL != 0 ))",new_string:"exit $(( FAIL != 0 ))\n: > /dev/null"}]}}' | run)
if denied "$OUT"; then ok; else bad T6 "MultiEdit, ломающий концовку, прошёл: ${OUT:-<пусто>}"; fi

# T7: файл вне hooks/tests/test_*.sh — не предмет стража.
OUT=$(write_payload "$ROOT/hooks/other.sh" "$OLD" | run)
assert_empty "$OUT" T7

# T8: чужое дерево без предиката — прибора нет, страж молчит (гейт -f до вызова).
mkdir -p "$TMP/foreign/hooks/tests"
OUT=$(write_payload "$TMP/foreign/hooks/tests/test_x.sh" "$OLD" | run)
assert_empty "$OUT" T8

# T9: точность на мире — запись НАСТОЯЩЕГО теста дерева (этого файла) отказа не вызывает.
OUT=$(write_payload "$HOOKS_DIR/tests/test_test_exit_explicit_guard.sh" "$(cat "$0")" | run)
assert_empty "$OUT" T9

echo "test_test_exit_explicit_guard: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
