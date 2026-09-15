#!/usr/bin/env bash
# test_absent_tool_guard.sh — свидетель стража отсутствующего инструмента.
# Предмет: отказ ровно там, где инструмента НЕТ на этой машине; молчание там, где он есть,
# где форма другая и где событие не Bash. Замена названа в тексте отказа.
# Пробные команды нарочно на ASCII: страж переносимости судит ЛИТЕРАЛ, и кириллица вплотную
# к синтаксису оболочки в фикстуре отбивается им же (проверено отказом 14 сентября 2026).
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/absent-tool-guard.sh"
# Каталог состояния — ПЕСОЧНИЦА с первой строки. Первый прогон этого свидетеля написал
# `absent-tool-fired-nosid.jsonl` в живой ~/.claude: ноги звали стража до того, как песочница
# создавалась в T6, и журнал ушёл по умолчанию хука.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

run() {  # run <command> [tool]
    printf '{"tool_name":"%s","tool_input":{"command":%s}}' "${2:-Bash}" \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | bash "$HOOK" 2>/dev/null
}
# Утверждение о ТИШИНЕ названо ролью, а не формой: судья стражей (test_guards_provable.sh)
# читает словарь именованных утверждений, и голое `[ -z "$O" ]` в него не входит. Расширять
# его словарь значило бы растить перечень форм — корень R3; имя роли дешевле и честнее.
assert_empty() { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: ${1:0:120}"; }

decision() { printf '%s' "$1" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])
except Exception: print("")' 2>/dev/null; }

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ, и он условный: отказ ожидается ТОЛЬКО если инструмента нет.
# Иначе нога судила бы не стража, а машину, на которой её запустили.
O=$(run 'timeout 900 bash run_all.sh')
if command -v timeout >/dev/null 2>&1; then
    assert_empty "$O" T1
else
    [ "$(decision "$O")" = "deny" ] && ok || bad T1 "timeout absent, no refusal: ${O:0:120}"
    grep -qF "run_with_timeout" <<< "$O" && ok || bad T1b "replacement not named"
    grep -qF "12101" <<< "$O" && ok || bad T1c "measurement behind the signal not shown"
fi

# T2 — форма без числа не судится: слово в журнале, переменной, прозе.
O2=$(run 'echo "outcome: timeout" >> journal.txt')
assert_empty "$O2" T2

# T3 — инструмент, который ЕСТЬ, не отбивается.
O3=$(run 'grep -c . /dev/null')
assert_empty "$O3" T3

# T4 — не Bash: предмет чужой.
O4=$(run 'timeout 5 sleep 1' 'Edit')
assert_empty "$O4" T4

# T5 — вторая форма реестра судится СВОЕЙ проверкой, а не общим списком.
O5=$(run 'cat -A f.txt')
if cat -A /dev/null >/dev/null 2>&1; then
    assert_empty "$O5" T5
else
    [ "$(decision "$O5")" = "deny" ] && ok || bad T5 "cat -A broken here, no refusal"
fi

# T6 — ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: страж спрашивает МАШИНУ, а не помнит ответ.
# Инструмент появляется в PATH — отказ обязан исчезнуть.
printf '#!/bin/sh\nexit 0\n' > "$TMP/timeout"; chmod +x "$TMP/timeout"
O6=$(PATH="$TMP:$PATH" run 'timeout 900 bash run_all.sh')
assert_empty "$O6" T6

# T7 — отказ ПИШЕТСЯ в журнал семейства `*-fired-*`: без него точность уровня 4 измерена
# один раз при заведении и больше никогда. Журнал кладётся в песочницу, живой ~/.claude тест
# не трогает.
JDIR="$STATE_DIR"; mkdir -p "$JDIR"
O7=$(printf '{"session_id":"T7SID","tool_name":"Bash","tool_input":{"command":"timeout 900 true"}}' \
    | STATE_DIR="$JDIR" bash "$HOOK" 2>/dev/null)
if command -v timeout >/dev/null 2>&1; then
    [ ! -s "$JDIR/absent-tool-fired-T7SID.jsonl" ] && ok || bad T7 "инструмент есть, а журнал записан"
else
    grep -q '"key":"timeout"' "$JDIR/absent-tool-fired-T7SID.jsonl" 2>/dev/null && ok \
        || bad T7 "отказ не записан в журнал: точность больше не измерима"
    # Ноги «не пишет в живой каталог» здесь нет намеренно: сравнение временного каталога с
    # живым тавтологично, а владелец правила один — hooks/tests/test_live_home_in_tests.sh (род K).
fi

echo "test_absent_tool_guard: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
