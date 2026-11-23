#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_adversary_d509_concatenated_arrays_fire.sh
#
# АТАКА (D509, противник): вход из НЕСКОЛЬКИХ JSON-значений подряд. Блок
# `detection_signals: |` объявлен ОДНИМ массивом, а здесь в нём два массива строкой за
# строкой. Прежняя редакция такой блок не исполняла (счёт сигналов «1\n1» не число —
# rc=1, ни одного сигнала), и так же его читает `scripts/knowledge-instrument-audit.sh`:
# json.loads → «bad» → «blocker: true, но сигналов нет или они не разбираются».
# Новая (_ds_compile) кормит jq весь текст, jq исполняет программу на КАЖДОМ значении,
# и поток несёт сигналы обоих массивов: второй массив живёт, вплоть до отказа `deny`
# через blocker-tier-check.sh. То же у ds_evaluate_node / ds_evaluate_signal: прежние
# отвечали rc=1 на два значения подряд, новые исполняют первое.
#
# Ожидание: решения тождественны прежней редакции — rc=1, имя не печатается, страж молчит.
# Факт:     печатается «second», rc=0; страж отдаёт permissionDecision: deny.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
HOOK="$REPO/hooks/blocker-tier-check.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

T=$(mktemp -d)
OLD="$T/old-lib.sh"
git -C "$REPO" show 'a03e2c5f^:hooks/detection-signals-lib.sh' > "$OLD" 2>/dev/null || OLD=""
[ -s "${OLD:-/nonexistent}" ] || OLD=""

FAIL=0

# run <библиотека> <функция> <аргументы…> → "rc=N|вывод"
run() {
    local lib="$1"; shift
    bash -c '. "$1"; shift; out=$("$@" 2>/dev/null); printf "rc=%s|%s" "$?" "$out"' _ "$lib" "$@"
}

check() { # $1=метка $2=ожидание $3=факт
    if [ "$2" = "$3" ]; then
        echo "ok   $1: $3"
    else
        echo "FAIL $1: ждали [$2], получили [$3]"
        FAIL=1
    fi
}

mkdir -p "$T/k" "$T/k-ctrl" "$T/state" "$T/state-ctrl"
cat > "$T/k/pattern-two-arrays.md" <<'EOF'
---
name: pattern-two-arrays
blocker: true
blocker_reminder: "напоминание"
detection_signals: |
  [{"name":"first","all_of":[{"tool_matches":["Bash"]},{"command_uses":"zzz-never"}]}]
  [{"name":"second","enforcement":"deny","all_of":[{"tool_matches":["Bash"]},{"command_uses":"ls"}]}]
---
body
EOF
# Положительный контроль: тот же сигнал в ОДНОМ массиве обязан срабатывать — иначе тест
# не умеет сказать «да», и его rc=1 ничего не значит.
cat > "$T/k-ctrl/pattern-one-array.md" <<'EOF'
---
name: pattern-one-array
blocker: true
blocker_reminder: "напоминание"
detection_signals: |
  [{"name":"first","all_of":[{"tool_matches":["Bash"]},{"command_uses":"zzz-never"}]},
   {"name":"second","enforcement":"deny","all_of":[{"tool_matches":["Bash"]},{"command_uses":"ls"}]}]
---
body
EOF
TI='{"command":"ls -la"}'

check "контроль: один массив" "rc=0|second" \
    "$(run "$LIB" ds_evaluate "$T/k-ctrl/pattern-one-array.md" Bash "$TI" "")"

# 1. ds_evaluate на двух массивах подряд.
check "ds_evaluate, два массива подряд" "rc=1|" \
    "$(run "$LIB" ds_evaluate "$T/k/pattern-two-arrays.md" Bash "$TI" "")"

# 2. Публичные ds_evaluate_node / ds_evaluate_signal на двух значениях подряд.
check "ds_evaluate_node, два узла подряд" "rc=1|" \
    "$(run "$LIB" ds_evaluate_node '{"command_uses":"ls"} {"command_uses":"zzz"}' Bash "$TI" "")"
check "ds_evaluate_signal, два сигнала подряд" "rc=1|" \
    "$(run "$LIB" ds_evaluate_signal '{"name":"x","all_of":[{"command_uses":"ls"}]} {"name":"y","all_of":[]}' Bash "$TI" "")"

# 3. Сверка с прежней редакцией (если история git доступна).
if [ -n "$OLD" ]; then
    for leg in \
        "ds_evaluate|$T/k/pattern-two-arrays.md" \
        'ds_evaluate_node|{"command_uses":"ls"} {"command_uses":"zzz"}' \
        'ds_evaluate_signal|{"name":"x","all_of":[{"command_uses":"ls"}]} {"name":"y","all_of":[]}'; do
        fn="${leg%%|*}"; a1="${leg#*|}"
        check "прежняя = новая: $fn" "$(run "$OLD" "$fn" "$a1" Bash "$TI" "")" "$(run "$LIB" "$fn" "$a1" Bash "$TI" "")"
    done
else
    echo "skip сверка с прежней редакцией: нет истории git"
fi

# 4. Достижимость: настоящий страж с базой из одного такого файла.
IN='{"session_id":"adv-d509-arrays","tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/tmp"}'
CTRL_OUT=$(printf '%s' "$IN" | BLOCKER_KNOWLEDGE_DIR="$T/k-ctrl" BLOCKER_STATE_DIR="$T/state-ctrl" bash "$HOOK" 2>/dev/null)
if grep -q '"permissionDecision": "deny"' <<< "$CTRL_OUT"; then
    echo "ok   контроль стража: один массив даёт deny"
else
    echo "FAIL контроль стража: один массив не дал deny — стенд не умеет сказать «да»"
    FAIL=1
fi
HOOK_OUT=$(printf '%s' "$IN" | BLOCKER_KNOWLEDGE_DIR="$T/k" BLOCKER_STATE_DIR="$T/state" bash "$HOOK" 2>/dev/null)
if grep -q '"permissionDecision": "deny"' <<< "$HOOK_OUT"; then
    echo "FAIL страж: отказ deny из блока, который прежняя редакция и аудит инструментов считают неразбираемым"
    FAIL=1
else
    echo "ok   страж молчит на двух массивах"
fi

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
