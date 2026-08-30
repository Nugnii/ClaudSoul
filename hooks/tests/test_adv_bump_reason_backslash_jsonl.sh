#!/usr/bin/env bash
# test_adv_bump_reason_backslash_jsonl.sh — АТАКА: та же обратная косая рвёт durable-журнал
# `disagreement-outcomes.jsonl`, и рвёт его для ВСЕХ строк сразу.
#
# `dis_close_outcome` собирает JSON тем же printf (строка 100), подставляя причину в
# строковое поле `"case"`. Санитайзер снимает только кавычки и переводы строк. Причина,
# кончающаяся на `\`, экранирует закрывающую кавычку: `"case":"…C:\"}` — строка не JSON.
#
# Разница с YAML-атакой в радиусе. Журнал читается потоково (`jq`), и одна битая строка
# обрывает разбор ХВОСТА файла. Это не гипотеза о поведении jq: внутренний архив (не публикуется):1702
# описывает уже случившееся — «metrics-collector считал по 285 строкам лога из 7665
# (jq обрывался на битой строке, ошибка глушилась): 10 уникальных знаний вместо 99,
# hit_rate 34% вместо 79%». Тот же класс, другой писатель.
#
# Достижимость: та же, что у YAML-атаки — свободный текст причины из /learn Step 4a/4e.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

mk() {
cat > "$LESSONS_DIR/$1" <<'KN'
---
name: проба
confidence: 4
confirmed_count: 2
contradicted_count: 0
provenance_log: []
---
тело
KN
}
mk pattern-first.md
mk pattern-second.md

# 1) обычная запись, 2) запись с косой, 3) снова обычная — чтобы видеть, теряется ли хвост
bash "$SCRIPT" pattern-first  confirmed "обычная причина"        >/dev/null 2>&1
bash "$SCRIPT" pattern-second confirmed 'откат до каталога C:\'  >/dev/null 2>&1
bash "$SCRIPT" pattern-first  confirmed "ещё одна обычная"       >/dev/null 2>&1

J="$STATE_DIR/disagreement-outcomes.jsonl"
[ -f "$J" ] || { echo "FAIL: журнал не создан вовсе"; exit 1; }

bad=$(python3 - "$J" <<'PY'
import json, sys
bad = []
for i, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    if not line.strip():
        continue
    try:
        json.loads(line)
    except Exception as e:
        bad.append(f"строка {i}: {e}")
print("\n".join(bad))
PY
)

rc=0
if [ -n "$bad" ]; then
    echo "FAIL: в журнале есть неразбираемые строки:"
    printf '%s\n' "$bad" | sed 's|^|    |'
    rc=1
fi

if command -v jq >/dev/null 2>&1; then
    seen=$(jq -r '.knowledge' "$J" 2>/dev/null | wc -l | tr -d ' ')
    total=$(grep -c . "$J")
    echo "потоковый разбор jq: увидено $seen из $total записей"
    if [ "$seen" != "$total" ]; then
        echo "FAIL: jq потерял $(( total - seen )) запис(и/ей) — счёт исходов занижен молча"
        rc=1
    fi
fi

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: каждая строка журнала — валидный JSON независимо от текста причины."
    echo "Факт:     содержимое журнала:"
    sed 's|^|    |' "$J"
    echo "adv bump reason-backslash-jsonl: КРАСНЫЙ"
else
    echo "adv bump reason-backslash-jsonl: passed"
fi
exit "$rc"
