#!/usr/bin/env bash
# test_adversary_d509_nul_in_value_truncates_stream.sh
#
# АТАКА (D509, противник): байт NUL (`\u0000`) в значении листа или в имени сигнала.
# Новый поток лексем читается `read -r -d ''` — разделитель записи у него NUL, поэтому
# лексема с NUL обрывает ВЕСЬ поток на этом байте: лист получает усечённое значение, а
# все сигналы паттерна после него пропадают. Назван только предел про байт \037; про NUL
# в шапке библиотеки ничего нет, и последствие другое — не «паттерн молчит целиком»,
# а «молчит всё, что стоит в файле ниже».
# Прежняя редакция брала значение `$(jq -r …)`: подстановка выбрасывает NUL, значение
# склеивается («x\u0000y» → «xy»), остальные сигналы живут.
#
# Ожидание: решения тождественны прежней — печатается «b» (второй сигнал), rc=0;
#           сигнал с NUL в имени печатается без NUL.
# Факт:     rc=1, ничего не печатается.
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
        echo "ok   $1: $3"
    else
        echo "FAIL $1: ждали [$(printf '%q' "$2")], получили [$(printf '%q' "$3")]"
        FAIL=1
    fi
}

# `\u0000` ниже — JSON-экранирование (шесть символов), а не сырой байт: так его пишет автор знания.
cat > "$T/value.md" <<'EOF'
---
blocker: true
detection_signals: |
  [{"name":"a","all_of":[{"prompt_contains":"x\u0000y"}]},{"name":"b","all_of":[{"prompt_contains":"q"}]}]
---
EOF
cat > "$T/name.md" <<'EOF'
---
blocker: true
detection_signals: |
  [{"name":"n\u0000m","all_of":[{"prompt_contains":"q"}]}]
---
EOF
# Положительный контроль: тот же файл без NUL — второй сигнал обязан сработать.
cat > "$T/ctrl.md" <<'EOF'
---
blocker: true
detection_signals: |
  [{"name":"a","all_of":[{"prompt_contains":"xy"}]},{"name":"b","all_of":[{"prompt_contains":"q"}]}]
---
EOF
TI='{"command":"ls"}'

check "контроль: без NUL" "rc=0|b" "$(run "$LIB" ds_evaluate "$T/ctrl.md" Bash "$TI" "q")"
check "NUL в значении первого сигнала" "rc=0|b" "$(run "$LIB" ds_evaluate "$T/value.md" Bash "$TI" "q")"
check "NUL в имени сигнала" "rc=0|nm" "$(run "$LIB" ds_evaluate "$T/name.md" Bash "$TI" "q")"

if [ -n "$OLD" ]; then
    for f in value.md name.md; do
        check "прежняя = новая: $f" "$(run "$OLD" ds_evaluate "$T/$f" Bash "$TI" "q")" \
            "$(run "$LIB" ds_evaluate "$T/$f" Bash "$TI" "q")"
    done
else
    echo "skip сверка с прежней редакцией: нет истории git"
fi

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
