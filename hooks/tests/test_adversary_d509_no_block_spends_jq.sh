#!/usr/bin/env bash
# test_adversary_d509_no_block_spends_jq.sh
#
# АТАКА (D509, противник, производительность): файл знания без блока
# `detection_signals: |` (или с пустым блоком). Прежняя ds_evaluate шла через
# ds_extract_signals: пустой блок → `[]` → rc=1, НОЛЬ запусков jq. Новая зовёт
# `_ds_compile signals ""` без проверки на пустоту — jq запускается на пустом тексте
# ради пустого потока. Это вход, на котором новая редакция зовёт jq БОЛЬШЕ прежней
# (D509 обещал только меньше). Страж зовёт ds_evaluate на каждый файл с `blocker: true`
# на КАЖДОМ вызове инструмента; знание с флагом и без сигналов (например, живущее одним
# `cross_hook_recall_gate`) платит лишний процесс на каждом вызове.
#
# Ожидание: 0 запусков jq, rc=1.
# Факт:     1 запуск jq.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
REAL_JQ=$(command -v jq 2>/dev/null) || { echo "SKIP: нет jq"; exit 0; }

T=$(mktemp -d)
mkdir -p "$T/shim"
# Счётчик-обёртка: каждая строка в файле — один запуск jq.
printf '#!/bin/sh\necho x >> "%s/count"\nexec "%s" "$@"\n' "$T" "$REAL_JQ" > "$T/shim/jq"
chmod +x "$T/shim/jq"

FAIL=0

calls() { # $1=файл паттерна → число запусков jq за один ds_evaluate
    : > "$T/count"
    PATH="$T/shim:$PATH" bash -c '. "$1"; ds_evaluate "$2" Bash "{\"command\":\"ls\"}" "" >/dev/null 2>&1' _ "$LIB" "$1" || true  # код оценки не предмет: число запусков jq читает строка ниже (D1261)
    local n
    n=$(wc -l < "$T/count")
    printf '%s' "$((n + 0))"
}

printf -- '---\nname: p\nblocker: true\n---\nbody\n' > "$T/nosig.md"
printf -- '---\nname: p\nblocker: true\ndetection_signals: |\n---\nbody\n' > "$T/emptysig.md"
printf -- '---\nname: p\nblocker: true\ndetection_signals: |\n  [{"name":"s","all_of":[{"prompt_contains":"q"}]}]\n---\nbody\n' > "$T/sig.md"

# Положительный контроль: обёртка считает — на файле с сигналами запуск есть.
n=$(calls "$T/sig.md")
if [ "$n" -ge 1 ]; then
    echo "ok   контроль: файл с сигналами — $n запуск(ов) jq, счётчик работает"
else
    echo "FAIL контроль: счётчик не видит jq ($n) — тест не различает"
    FAIL=1
fi

for f in nosig.md emptysig.md; do
    n=$(calls "$T/$f")
    if [ "$n" -eq 0 ]; then
        echo "ok   $f: 0 запусков jq"
    else
        echo "FAIL $f: $n запуск(ов) jq там, где прежняя редакция не запускала ни одного"
        FAIL=1
    fi
done

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
