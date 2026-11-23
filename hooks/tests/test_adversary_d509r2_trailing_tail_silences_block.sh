#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_adversary_d509r2_trailing_tail_silences_block.sh
#
# АТАКА (D509, противник, раунд 2): в блоке `detection_signals: |` за ОДНИМ правильным
# массивом стоит хвост, который JSON-значением не является: лишняя `]`, запятая, строка
# `  # note` (внутри `|` это содержимое, а не комментарий YAML), забытая ограда ```.
# Это не «несколько документов подряд» (закрытый класс 1): второго значения здесь нет.
#
# Прежняя редакция читала блок `jq -c '.'`: jq печатает разобранный массив ДО того, как
# споткнуться о хвост, и сигналы исполнялись — вплоть до отказа `deny` у стража.
# Новая читает блок `jq -s` (починка класса 1): разбор падает целиком, поток пуст,
# ds_evaluate молчит. Та же библиотека при этом продолжает отдавать сигналы этого блока
# через ds_extract_signals (им страж берёт enforcement и remedy) — внутри одной библиотеки
# блок одновременно «есть» и «нет».
#
# Ожидание: решения тождественны прежней редакции — печатается «sig», rc=0; страж — deny.
# Факт:     rc=1, имя не печатается; страж молчит.
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
        echo "FAIL $1: ждали [$(printf '%q' "$2")], получили [$(printf '%q' "$3")]"
        FAIL=1
    fi
}

SIG='[{"name":"sig","enforcement":"deny","all_of":[{"tool_matches":["Bash"]},{"command_uses":"frobnicate"}]}]'
mk() { # $1=имя файла $2=хвост блока (строки с отступом)
    mkdir -p "$T/$1"
    printf -- '---\nname: pattern-%s\nblocker: true\nblocker_reminder: "напоминание"\ndetection_signals: |\n  %s%s\n---\nbody\n' \
        "$1" "$SIG" "$2" > "$T/$1/pattern-$1.md"
}
mk ctrl  ''                    # положительный контроль: блок без хвоста
mk brkt  ']'                   # лишняя скобка
mk comma ','                   # запятая после массива
mk note  $'\n  # note: fires on frobnicate'
mk fence $'\n  ```'

TI='{"command":"frobnicate --all"}'

# Положительный контроль: без хвоста сигнал обязан срабатывать — иначе rc=1 ниже ничего не значит.
check "контроль: блок без хвоста" "rc=0|sig" "$(run "$LIB" ds_evaluate "$T/ctrl/pattern-ctrl.md" Bash "$TI" "")"

for v in brkt comma note fence; do
    f="$T/$v/pattern-$v.md"
    # 1. Сама библиотека видит сигнал этого блока: ds_extract_signals отдаёт его, и он совпадает.
    sj=$(bash -c '. "$1"; ds_extract_signals "$2" | jq -c ".[0]"' _ "$LIB" "$f" 2>/dev/null)
    check "$v: ds_extract_signals отдаёт сигнал" "rc=0|" "$(run "$LIB" ds_evaluate_signal "$sj" Bash "$TI" "")"
    # 2. ...и ds_evaluate того же файла обязан сработать тем же именем.
    check "$v: ds_evaluate печатает имя" "rc=0|sig" "$(run "$LIB" ds_evaluate "$f" Bash "$TI" "")"
    # 3. Сверка с прежней редакцией.
    if [ -n "$OLD" ]; then
        check "$v: прежняя = новая" "$(run "$OLD" ds_evaluate "$f" Bash "$TI" "")" "$(run "$LIB" ds_evaluate "$f" Bash "$TI" "")"
    fi
done
[ -n "$OLD" ] || echo "skip сверка с прежней редакцией: нет истории git"

# 4. Достижимость: настоящий страж. Контроль — блок без хвоста даёт deny.
IN='{"session_id":"adv-d509r2-tail","tool_name":"Bash","tool_input":{"command":"frobnicate --all"},"cwd":"/tmp"}'
for v in ctrl brkt note; do
    mkdir -p "$T/state-$v"
    out=$(printf '%s' "$IN" | BLOCKER_KNOWLEDGE_DIR="$T/$v" BLOCKER_STATE_DIR="$T/state-$v" bash "$HOOK" 2>/dev/null)
    if grep -q '"permissionDecision": "deny"' <<< "$out"; then
        echo "ok   страж, $v: deny"
    else
        echo "FAIL страж, $v: отказа нет — прежняя редакция здесь отказывала"
        FAIL=1
    fi
done

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
