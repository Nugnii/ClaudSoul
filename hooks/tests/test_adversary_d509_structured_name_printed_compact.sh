#!/usr/bin/env bash
# test_adversary_d509_structured_name_printed_compact.sh
#
# АТАКА (D509, противник): имя сигнала — объект или массив, а не строка. Контракт
# ds_evaluate — НАПЕЧАТАННОЕ имя тождественно прежней редакции. Прежняя печатала имя
# `jq -r '.name // ""'` — объект и массив с отступами, многострочно. Новая гонит имя через
# `r` → `tojson` и печатает компактно. Названный предел в шапке библиотеки говорит только о
# ЗНАЧЕНИИ ЛИСТА («массив или объект в значении листа печатается компактно»); имя сигнала
# под него не подпадает. Имя у стража — ключ дросселя `<паттерн>:<сигнал>` и текст
# `🛑 Blocker: <сигнал>`, то есть меняется ключ, по которому сигнал дросселируется.
#
# Ожидание: печатается то же, что печатает `jq -r '.name'` этого сигнала.
# Факт:     печатается компактный JSON.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

T=$(mktemp -d)
OLD="$T/old-lib.sh"
git -C "$REPO" show 'a03e2c5f^:hooks/detection-signals-lib.sh' > "$OLD" 2>/dev/null || OLD=""
[ -s "${OLD:-/nonexistent}" ] || OLD=""

FAIL=0

run() {
    local lib="$1"; shift
    bash -c '. "$1"; shift; out=$("$@" 2>/dev/null); printf "rc=%s|%s" "$?" "$out"' _ "$lib" "$@"
}

check() { # $1=метка $2=ожидание $3=факт
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: ждали [$(printf '%q' "$2")], получили [$(printf '%q' "$3")]"
        FAIL=1
    fi
}

TI='{"command":"ls"}'
for name in '"plain"' '{"id":"a"}' '["a","b"]'; do
    f="$T/p$RANDOM.md"
    printf -- '---\nblocker: true\ndetection_signals: |\n  [{"name":%s,"all_of":[{"prompt_contains":"q"}]}]\n---\n' "$name" > "$f"
    want=$(jq -r '.name // ""' <<< "{\"name\":$name}")
    check "имя $name печатается как jq -r" "rc=0|$want" "$(run "$LIB" ds_evaluate "$f" Bash "$TI" "q")"
    if [ -n "$OLD" ]; then
        check "прежняя = новая: имя $name" "$(run "$OLD" ds_evaluate "$f" Bash "$TI" "q")" \
            "$(run "$LIB" ds_evaluate "$f" Bash "$TI" "q")"
    fi
done
[ -n "$OLD" ] || echo "skip сверка с прежней редакцией: нет истории git"

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
