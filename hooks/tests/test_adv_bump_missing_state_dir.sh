#!/usr/bin/env bash
# test_adv_bump_missing_state_dir.sh — АТАКА: нет каталога состояния — исход теряется молча,
# а счётчик знания при этом уже увеличен.
#
# `dis_close_outcome` дописывает журнал перенаправлением `>> "$S/disagreement-outcomes.jsonl"`
# (строка 102). Каталог `$S` скрипт не создаёт нигде, и результат перенаправления не
# проверяет. Нет каталога — оболочка ругается в stderr, функция как ни в чём не бывало
# печатает `_closed=0`, и вызывающий код выводит «✅ … погашено записей: 0» с кодом 0.
#
# Это разрыв, а не потеря одной строки: счётчик в знании УЖЕ увеличен (`cat > "$FILE"`
# отработал строкой раньше), а durable-свидетельство того же события не создано. База
# знаний и журнал исходов расходятся, и расходятся именно в ту сторону, которую шапка
# скрипта называет измеренным перекосом (строки 70-78).
#
# Соседние хуки эту предпосылку не разделяют: `mkdir -p "$STATE_DIR"` есть в
# accepted-alternative-gap.sh, auto-scanner.sh, budget-gate.sh, blocker-tier-check.sh,
# changelog-reminder.sh и других — здесь его нет ни одного.
#
# Достижимость: НИЗКАЯ при штатной установке — install.sh:252 создаёт каталог заранее.
# Остаются машина без прогона install.sh, переезд каталога и вызов с иным STATE_DIR.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons"
export STATE_DIR="$T/state-not-created-yet"     # намеренно не создаём
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR"

cat > "$LESSONS_DIR/pattern-probe.md" <<'KN'
---
name: проба
confidence: 4
confirmed_count: 2
contradicted_count: 0
provenance_log: []
---
тело
KN

out=$(bash "$SCRIPT" pattern-probe confirmed "подтвердилось" 2>&1); brc=$?
cnt=$(grep '^confirmed_count:' "$LESSONS_DIR/pattern-probe.md")
echo "код возврата: $brc"
echo "счётчик знания: $cnt"
echo "журнал существует: $([ -f "$STATE_DIR/disagreement-outcomes.jsonl" ] && echo да || echo НЕТ)"

rc=0
if [ "$cnt" = "confirmed_count: 3" ] && [ ! -f "$STATE_DIR/disagreement-outcomes.jsonl" ]; then
    echo "FAIL: счётчик увеличен, а записи об исходе нет — база и журнал разошлись на одном событии"
    rc=1
    if [ "$brc" -eq 0 ]; then
        echo "FAIL: и код возврата 0, то есть вызывающий не узнает о потере. Вывод:"
        printf '%s\n' "$out" | sed 's|^|        |'
    fi
fi

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: каталог состояния создаётся (как в соседних хуках) либо отказ ненулевым кодом."
    echo "Факт:     запись потеряна, успех отчитан."
    echo "adv bump missing-state-dir: КРАСНЫЙ"
else
    echo "adv bump missing-state-dir: 1/1 passed"
fi
exit "$rc"
