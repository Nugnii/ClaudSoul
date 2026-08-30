#!/usr/bin/env bash
# test_docs_match_tree.sh — документация описывает то, что есть, и только то, что есть.
#
# Результат: docs-inventory и docs-duplicates дают 0.
# Проверка результата: этот тест; красный — значит документы разошлись с деревом.
#
# Повод — вопрос собеседника 28 августа 2026: внесена ли работа сессии в документацию?
# Замер: семь новых механизмов упомянуты в architecture.md, README и CLAUDE.md НОЛЬ раз, а
# два стража документации были узкими — один срабатывает лишь при бампе версии и проверяет,
# что файлы ТРОНУТЫ коммитом, другой только на появление нового модуля.
#
# Почему тест, а не запуск по расписанию. Инструмент, который надо не забыть запустить, —
# прибор; красный тест нельзя прочитать и пройти мимо. Это тот же вывод, что дал замер
# 19 случаев «знание было уместно и не применено»: напоминания не меняют действия.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1

PASS=0; FAIL=0
for tool in scripts/docs-inventory.sh scripts/docs-duplicates.sh; do
    if [ ! -x "$tool" ]; then
        FAIL=$((FAIL+1)); echo "FAIL: нет исполняемого $tool"; continue
    fi
    out=$(bash "$tool" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $tool нашёл расхождение —"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
done

echo ""
echo "docs match tree tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
