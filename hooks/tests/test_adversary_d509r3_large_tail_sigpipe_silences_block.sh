#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_adversary_d509r3_large_tail_sigpipe_silences_block.sh
#
# АТАКА (D509, противник, раунд 3). ВХОД ЗАКРЫТОГО КЛАССА «число документов во входе
# компиляции»: документ и мусор после него — но мусор ДЛИННЫЙ (больше ~128 КБ на macOS).
# Починка раунда 2 сделала вход «значения до первой ошибки разбора» (`[try inputs]`), и
# короткий хвост исполняется. Длинный — нет, по другому механизму: jq бросает чтение на
# первой ошибке разбора и выходит, пишущий в трубу `printf` получает SIGPIPE (код 141),
# под `pipefail` (его ставит сама библиотека) код конвейера в _ds_compile — 141, и
# `|| out=""` выбрасывает уже напечатанный поток целиком: блок молчит.
# Прежняя редакция читала блок `json=$(printf … | jq -c '.')` без проверки кода — первый
# документ доходил до оценки при любой длине хвоста, вплоть до отказа `deny` у стража.
#
# Ожидание: решения тождественны прежней редакции при любой длине хвоста — печатается «sig».
# Факт:     хвост 2000 строк (142 КБ) — rc=1, имя не печатается; страж молчит.
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

# mk <каталог> <число строк хвоста>: один верный массив, лишняя `]`, затем N строк текста.
mk() {
    local i
    mkdir -p "$1"
    {
        printf -- '---\nname: pattern-tail\nblocker: true\nblocker_reminder: "напоминание"\ndetection_signals: |\n'
        printf '  [{"name":"sig","enforcement":"deny","all_of":[{"tool_matches":["Bash"]},{"command_uses":"frobnicate"}]}]\n  ]\n'
        i=0
        while [ "$i" -lt "$2" ]; do
            printf '  # filler line %05d ................................................\n' "$i"
            i=$((i + 1))
        done
        printf -- '---\nbody\n'
    } > "$1/pattern-tail.md"
}
mk "$T/short" 100      # положительный контроль: короткий хвост (раунд 2) исполняется
mk "$T/long" 2000      # 142 КБ хвоста

TI='{"command":"frobnicate --all"}'
check "контроль: короткий хвост" "rc=0|sig" "$(run "$LIB" ds_evaluate "$T/short/pattern-tail.md" Bash "$TI" "")"
check "длинный хвост: ds_evaluate печатает имя" "rc=0|sig" "$(run "$LIB" ds_evaluate "$T/long/pattern-tail.md" Bash "$TI" "")"
if [ -n "$OLD" ]; then
    check "длинный хвост: прежняя = новая" \
        "$(run "$OLD" ds_evaluate "$T/long/pattern-tail.md" Bash "$TI" "")" \
        "$(run "$LIB" ds_evaluate "$T/long/pattern-tail.md" Bash "$TI" "")"
else
    echo "skip сверка с прежней редакцией: нет истории git"
fi

# Достижимость: настоящий страж. Контроль — короткий хвост даёт deny.
IN='{"session_id":"adv-d509r3-tail","tool_name":"Bash","tool_input":{"command":"frobnicate --all"},"cwd":"/tmp"}'
for v in short long; do
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
