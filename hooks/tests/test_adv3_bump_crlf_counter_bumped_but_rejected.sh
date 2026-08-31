#!/usr/bin/env bash
# test_adv3_bump_crlf_counter_bumped_but_rejected.sh — отказ обязан означать «файл не тронут».
#
# Результат: у вызова два честных исхода — либо ноль и запись в журнале, либо ненулевой
# код и НЕТРОНУТОЕ знание. Третьего («счётчик увеличен, но исход НЕ записан») быть не должно.
# Проверка результата: bash hooks/tests/test_adv3_bump_crlf_counter_bumped_but_rejected.sh даёт 0
#
# Атака. Разделитель frontmatter разбирается в скрипте ПЯТЬЮ awk-программами, и одна из них
# отличается: `show_counters` (строка 81) требует `/^---$/`, остальные четыре (226, 247, 300,
# 392) принимают `/^---[[:space:]]*$/`. Файл с окончаниями строк CRLF (или с пробелом после
# `---`) проходит основной проход и НЕ проходит проверочный: счётчик увеличен, last_confirmed
# переписан, запись провенанса добавлена — а скрипт печатает «исход НЕ записан», возвращает 1
# и журнала не создаёт. Повторный вызов по инструкции /learn Step 4e увеличит счётчик второй
# раз при по-прежнему пустом журнале.
#
# Это ровно тот дефект «два разбора одного поля расходятся молча», от которого скрипт
# избавился для ЗНАЧЕНИЯ счётчика (комментарий строки 61-65) и оставил для его РАМКИ.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$HOOKS_DIR/knowledge-counter-bump.sh"
[ -f "$BUMP" ] || { echo "FAIL: $BUMP не найден"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Изоляция: боевые каталоги не трогаем ни одним байтом.
unset CLAUDE_STATE_DIR
export LESSONS_DIR="$TMP/lessons"
export STATE_DIR="$TMP/state"
export CLAUDE_CODE_SESSION_ID="adv3-crlf"
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

K="$LESSONS_DIR/pattern-crlf.md"
printf -- '---\r\nname: pattern-crlf\r\ntype: pattern\r\nconfidence: 4\r\nimpact: 4\r\nconfirmed_count: 2\r\ncontradicted_count: 0\r\nlast_confirmed: 2026-01-01\r\nstatus: active\r\n---\r\n\r\nтело\r\n' > "$K"

OUT=$(bash "$BUMP" pattern-crlf confirmed "подтвердилось на деле" 2>&1); RC=$?

# Значение счётчика читаем независимо от скрипта: первое поле frontmatter, \r снят.
COUNT_AFTER=$(grep -m1 '^confirmed_count:' "$K" | tr -d '\r' | sed 's/^confirmed_count:[[:space:]]*//')
JOURNAL="$STATE_DIR/disagreement-outcomes.jsonl"

echo "--- код возврата: $RC"
echo "--- вывод: $OUT"
echo "--- confirmed_count после вызова: $COUNT_AFTER (было 2)"

if [ "$RC" -eq 0 ]; then
    if [ -s "$JOURNAL" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [успех без журнала]: rc=0, а $JOURNAL пуст"; fi
else
    if [ "$COUNT_AFTER" = "2" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL [отказ с правкой]: скрипт вернул $RC и напечатал «исход НЕ записан»,"
        echo "  но confirmed_count изменился 2 → $COUNT_AFTER, то есть подтверждение УЖЕ зачтено в знании."
        echo "  Повторный вызов по /learn Step 4e зачтёт его второй раз, а журнал так и останется пустым."
    fi
    if grep -q '^last_confirmed: 2026-01-01' <<< "$(tr -d '\r' < "$K")"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL [отказ с правкой]: last_confirmed переписан при отказе:"
        grep -m1 '^last_confirmed:' "$K" | sed 's/^/    /'
    fi
    if grep -q 'provenance_log' <<< "$(cat "$K")"; then
        FAIL=$((FAIL+1))
        echo "FAIL [отказ с правкой]: при отказе в знание добавлена запись provenance_log"
    else
        PASS=$((PASS+1))
    fi
    if [ -s "$JOURNAL" ]; then
        FAIL=$((FAIL+1)); echo "FAIL: журнал непуст при отказе"
    else
        PASS=$((PASS+1))
    fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
