#!/usr/bin/env bash
# test_metrics_composition.sh — итог таблицы «Состав базы» равен сумме её строк.
#
# Результат: читатель не видит таблицу, где строки не сходятся с итогом
# Проверка результата: bash hooks/tests/test_metrics_composition.sh даёт 0
#
# Повод, 7 сентября 2026. В живом файле метрик стояло: Cases 309 + Patterns 40 +
# Principles 10 = 359, а «Всего» — 464. Разница 105 — записи энциклопедического контура
# (entity/fact/relation): они входили в TOTAL и не входили ни в одну строку таблицы.
# Тот же класс, что чинился в этом же файле дважды: счётчик считает по всей базе,
# а строки перечисляют один контур. Ног у состава базы не было ни одной.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COLLECTOR="$REPO/hooks/metrics-collector.sh"
[ -f "$COLLECTOR" ] || { echo "SKIP: нет $COLLECTOR"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mk() {  # mk <имя> — файл знания с минимальной шапкой
    cat > "$TMP/.claude/global-lessons/$1" <<MD
---
name: $1
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
тело
MD
}

mkdir -p "$TMP/.claude/hooks/state" "$TMP/.claude/global-lessons"
mk case-a.md; mk case-b.md; mk pattern-a.md; mk principle-a.md
mk entity-a.md; mk fact-a.md; mk relation-a.md; mk relation-b.md
HOME="$TMP" bash "$COLLECTOR" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_metrics_composition.sh:$LINENO" >&2; exit 1; }
M="$TMP/.claude/hooks/state/metrics.md"

if [ ! -f "$M" ]; then
    bad "T0" "файл метрик не создан — прогон не состоялся"
else
    ok
    # число из строки таблицы по её метке
    val() { grep -F "| $1 |" "$M" 2>/dev/null | grep -oE '[0-9]+' | head -1; }
    TOT=$(grep -F '**Всего**' "$M" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    if [ -z "${TOT:-}" ]; then
        bad "T1" "итог таблицы не прочитан — сама таблица: $(grep -A 6 'Состав базы' "$M" | tr '\n' ' ')"
    else
        SUM=0
        for label in Cases Patterns Principles Entities Facts Relations; do
            v=$(val "$label"); SUM=$((SUM + ${v:-0}))
        done
        if [ "$SUM" = "$TOT" ]; then ok
        else bad "T1" "сумма строк $SUM не равна итогу $TOT — записи есть в итоге и нет ни в одной строке"; fi
        # и сам итог обязан быть равен числу файлов (8 созданных)
        if [ "$TOT" = "8" ]; then ok
        else bad "T2" "итог $TOT не равен числу файлов базы (8)"; fi
    fi
fi

echo "metrics composition: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
