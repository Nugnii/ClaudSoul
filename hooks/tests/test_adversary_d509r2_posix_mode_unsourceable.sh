#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_adversary_d509r2_posix_mode_unsourceable.sh
#
# АТАКА (D509, противник, раунд 2): библиотека в режиме POSIX оболочки. Новая редакция
# читает поток лексем через подстановку процесса `done < <(…)` (_ds_compile). bash до 5.1
# в режиме POSIX подстановку процесса не разбирает вовсе — это СИНТАКСИЧЕСКАЯ ошибка, и
# `source` обрывается на ней: _ds_compile, _ds_walk, ds_evaluate_node, ds_evaluate_signal,
# ds_evaluate не определяются. bash 3.2 — исполнитель на macOS. Режим включает переменная
# окружения POSIXLY_CORRECT (её наследует хук от процесса Claude Code) либо SHELLOPTS=posix.
# Прежняя редакция подстановки процесса не содержала и в этом режиме работала; в цепочке
# blocker-tier-check.sh → paths-lib.sh → throttle-lib.sh → библиотека других `<(` нет.
#
# Ожидание: в режиме POSIX решения тождественны обычному режиму и прежней редакции;
#           страж отдаёт тот же отказ.
# Факт (bash 3.2): ds_evaluate_node не определена (rc=127); страж выходит 0 молча —
#           отказ `deny` пропадает без следа в выводе.
# На bash ≥ 5.1 подстановка процесса в режиме POSIX разрешена, и тест там зелёный.
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

# run <библиотека> <функция> <аргументы…> → "rc=N|вывод"; окружение — как у вызывающего.
run() {
    local lib="$1"; shift
    bash -c '. "$1"; shift; out=$("$@" 2>/dev/null); printf "rc=%s|%s" "$?" "$out"' _ "$lib" "$@" 2>/dev/null
}

check() { # $1=метка $2=ожидание $3=факт
    if [ "$2" = "$3" ]; then
        echo "ok   $1: $3"
    else
        echo "FAIL $1: ждали [$(printf '%q' "$2")], получили [$(printf '%q' "$3")]"
        FAIL=1
    fi
}

NODE='{"all_of":[{"tool_matches":["Bash"]},{"command_uses":"frobnicate"}]}'
TI='{"command":"frobnicate --all"}'

# Положительный контроль: в обычном режиме узел совпадает.
check "контроль: обычный режим" "rc=0|" "$(run "$LIB" ds_evaluate_node "$NODE" Bash "$TI" "")"

# 1. Тот же вызов в режиме POSIX.
check "POSIXLY_CORRECT: ds_evaluate_node" "rc=0|" \
    "$(POSIXLY_CORRECT=1 run "$LIB" ds_evaluate_node "$NODE" Bash "$TI" "")"
if [ -n "$OLD" ]; then
    check "POSIXLY_CORRECT: прежняя = новая" \
        "$(POSIXLY_CORRECT=1 run "$OLD" ds_evaluate_node "$NODE" Bash "$TI" "")" \
        "$(POSIXLY_CORRECT=1 run "$LIB" ds_evaluate_node "$NODE" Bash "$TI" "")"
else
    echo "skip сверка с прежней редакцией: нет истории git"
fi

# 2. Достижимость: настоящий страж с базой из одного блокера. Контроль — обычный режим даёт deny.
mkdir -p "$T/k" "$T/state-a" "$T/state-b"
cat > "$T/k/pattern-posix.md" <<'EOF'
---
name: pattern-posix
blocker: true
blocker_reminder: "напоминание"
detection_signals: |
  [{"name":"sig","enforcement":"deny","all_of":[{"tool_matches":["Bash"]},{"command_uses":"frobnicate"}]}]
---
body
EOF
IN='{"session_id":"adv-d509r2-posix","tool_name":"Bash","tool_input":{"command":"frobnicate --all"},"cwd":"/tmp"}'
out=$(printf '%s' "$IN" | BLOCKER_KNOWLEDGE_DIR="$T/k" BLOCKER_STATE_DIR="$T/state-a" bash "$HOOK" 2>/dev/null)
if grep -q '"permissionDecision": "deny"' <<< "$out"; then
    echo "ok   контроль стража: обычный режим — deny"
else
    echo "FAIL контроль стража: обычный режим не дал deny — стенд не умеет сказать «да»"
    FAIL=1
fi
out=$(printf '%s' "$IN" | POSIXLY_CORRECT=1 BLOCKER_KNOWLEDGE_DIR="$T/k" BLOCKER_STATE_DIR="$T/state-b" bash "$HOOK" 2>/dev/null)
if grep -q '"permissionDecision": "deny"' <<< "$out"; then
    echo "ok   страж под POSIXLY_CORRECT: deny"
else
    echo "FAIL страж под POSIXLY_CORRECT: отказа нет, вывод [$(printf '%q' "$out")] ($(bash --version | head -1))"
    FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
