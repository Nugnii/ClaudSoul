#!/usr/bin/env bash
# СУДИТ: hooks/knowledge-activator.sh
# test_knowledge_frontmatter_batch.sh — пакетный разбор шапок знаний (D488).
#
# До D488 каждое поле каждого файла доставалось своим конвейером echo|grep|sed|tr, а
# каждый якорь — своим jq: ~150 процессов на файл, 39 с первого вызова на 244 файлах.
# Пакет разбирает все шапки одним awk+jq и обязан держать семантику тех конвейеров ПО
# ПОЛЮ, со всеми её особенностями: совпавшие строки ключа склеиваются переводом строки;
# якорь токенизируется целиком вместе с именем ключа; из чисел и дат берётся первое
# совпадение; у списка говорящих без скобок префикс ключа остаётся в значении; шапка —
# между первой и второй строкой `---`, а без второй — до конца файла. Значения ниже
# сверены с прежними конвейерами на этих же файлах при заведении теста.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
source "$HOOK_DIR/portable-lib.sh"
eval "$(sed -n '/^knowledge_frontmatter_batch() {/,/^}/p' "$HOOK_DIR/knowledge-activator.sh")"
if ! command -v knowledge_frontmatter_batch >/dev/null 2>&1; then
    echo "FAIL: knowledge_frontmatter_batch не найдена в knowledge-activator.sh"
    exit 1
fi

K="$TMP/kb"
mkdir -p "$K"

cat > "$K/pattern-full.md" <<'EOF'
---
name: "Правило | с трубой"
description: Описание "в кавычках"
domain: [bash, hooks]
situation: Хук ТОРМОЗИТ на первом вызове
trigger: first call slow
tags: [perf, fork]
stakes: время владельца
environment: macOS bash 3.2
circumstances: нагрузка
purpose: скорость
method: замер по звеньям
need: быстрый ответ
urgency: immediate
availability: unique
confidence: "4"
impact: 5
intensity: 3
confirmed_count: 7
last_confirmed: 2026-09-01T10:00:00
fragile: true
critical_anchors: [situation, trigger]
weight_modifiers: ["method:trained->environment:1"]
modification_history:
  - date: 2026-08-01
    change: первое
  - date: 2026-08-02
  -   date: 2026-08-03
related: [x]
  - date: 2026-08-04
---
body: not frontmatter
confidence: 1
EOF

cat > "$K/pattern-repeat.md" <<'EOF'
---
name: первая
name: вторая
domain: alpha
domain: beta
confidence: 4.5
confidence: 2
impact: 3
status: deprecated
scope: per-speaker
scope: mixed
valid_for: primary
pending_for: ["alice", "bob"]
invalid_for: [carol] tail
fragile:
fragile: true
---
EOF

cat > "$K/pattern-noclose.md" <<'EOF'
intro line
---
name: без закрытия
confidence: 2
impact: 2
EOF

printf -- '---\r\nname: crlf\r\nconfidence: 3\r\nimpact: 3\r\n---\r\n' > "$K/pattern-crlf.md"
printf 'no frontmatter at all\n' > "$K/pattern-plain.md"
: > "$K/pattern-empty.md"

knowledge_frontmatter_batch "$K"/pattern-full.md "$K"/pattern-repeat.md "$K"/pattern-noclose.md \
    "$K"/pattern-crlf.md "$K"/pattern-plain.md "$K"/pattern-empty.md > "$TMP/batch"
rc=$?

check() { # label expected actual
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL [%s]: ожидалось [%s], получено [%s]\n' "$1" "$2" "$3"
    fi
}

check "пакет отработал без ошибки" "0" "$rc"

# Записи по имени файла; поля по номеру (1 — имя файла ... 29 — weight_modifiers).
NAMES=""
while IFS=$'\x1f' read -r -d '' -a F; do
    NAMES="$NAMES ${F[0]}"
    key=$(printf '%s' "${F[0]%.md}" | tr -c 'a-z0-9' '_')
    for i in $(seq 0 28); do
        eval "R_${key}_$((i + 1))=\${F[$i]:-}"
    done
done < "$TMP/batch"
f() { local v="R_${1}_$2"; printf '%s' "${!v-<нет записи>}"; }

check "порядок записей = порядок файлов; пустой файл записи не даёт" \
    " pattern-full.md pattern-repeat.md pattern-noclose.md pattern-crlf.md pattern-plain.md" "$NAMES"

# Полная запись: каждое поле в прежней семантике.
check "status отсутствует" "" "$(f pattern_full 2)"
check "scope отсутствует → пусто (умолчание ставит вызывающий)" "" "$(f pattern_full 3)"
check "domain: токены вместе с именем ключа" "bash domain hooks " "$(f pattern_full 7)"
check "situation: кириллица в нижнем регистре, уникально, по кодовым точкам, короче 3 — прочь" \
    "situation вызове первом тормозит хук " "$(f pattern_full 8)"
check "trigger" "call first slow trigger " "$(f pattern_full 9)"
check "tags" "fork perf tags " "$(f pattern_full 10)"
check "environment: короткие токены отброшены" "bash environment macos " "$(f pattern_full 12)"
check "need" "быстрый ответ" "$(f pattern_full 16)"
check "urgency" "immediate" "$(f pattern_full 17)"
check "availability" "unique" "$(f pattern_full 18)"
check "confidence в кавычках → число" "4" "$(f pattern_full 19)"
check "impact" "5" "$(f pattern_full 20)"
check "intensity" "3" "$(f pattern_full 21)"
check "confirmed_count" "7" "$(f pattern_full 22)"
check "fragile" "true" "$(f pattern_full 23)"
check "modification_history: даты до первого ключа верхнего уровня" "3" "$(f pattern_full 24)"
check "last_confirmed: первая дата из метки времени" "2026-09-01" "$(f pattern_full 25)"
check "name: кавычки сняты, | → /" "Правило / с трубой" "$(f pattern_full 26)"
check "description: кавычки сняты" "Описание в кавычках" "$(f pattern_full 27)"
check "critical_anchors: токены вместе с именем ключа" \
    "critical_anchors situation trigger " "$(f pattern_full 28)"
check "weight_modifiers: кавычки и скобки сняты" "method:trained->environment:1" "$(f pattern_full 29)"

# Повторы ключей: склейка, первое совпадение, особенности списков говорящих.
check "name: повтор склеивается переводом строки" "первая
вторая" "$(f pattern_repeat 26)"
check "domain: токены обеих строк" "alpha beta domain " "$(f pattern_repeat 7)"
check "confidence: первое число первой строки" "4" "$(f pattern_repeat 19)"
check "status" "deprecated" "$(f pattern_repeat 2)"
check "scope: первая строка" "per-speaker" "$(f pattern_repeat 3)"
check "valid_for без скобок: префикс ключа остаётся" "valid_for: primary" "$(f pattern_repeat 4)"
check "pending_for: кавычки сняты, запятая → пробел" "alice  bob" "$(f pattern_repeat 5)"
check "invalid_for: хвост после ] отброшен" "carol" "$(f pattern_repeat 6)"
check "fragile: первая строка, даже пустая" "" "$(f pattern_repeat 23)"
check "modification_history нет → 0" "0" "$(f pattern_repeat 24)"
check "intensity нет → пусто" "" "$(f pattern_repeat 21)"

# Граница шапки.
check "без второй --- шапка идёт до конца файла" "без закрытия" "$(f pattern_noclose 26)"
check "строки до первой --- в шапку не входят" "2" "$(f pattern_noclose 19)"
check "CRLF: строка '---\\r' не граница → полей нет" "" "$(f pattern_crlf 26)"
check "без шапки → полей нет" "" "$(f pattern_plain 19)"

echo "test_knowledge_frontmatter_batch: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
