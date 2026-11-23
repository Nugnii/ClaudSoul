#!/usr/bin/env bash
# СУДИТ: scripts/knowledge-instrument-audit.sh
# test_kia_lock_lib_found.sh — прибор «знание → инструмент» находит библиотеку замка,
# а сообщение о её отсутствии означает ОТСУТСТВИЕ, а не промах пути.
#
# Результат: при живой hooks/lib/state_lock.py прибор молчит о замке; при снятой — говорит.
# Проверка результата: bash hooks/tests/test_kia_lock_lib_found.sh даёт 0
#
# Повод (10 сентября 2026). Прибор ДВАЖДЫ ЗА ПРОГОН печатал «нет hooks/lib/state_lock.py —
# реестры пишутся БЕЗ замка» при библиотеке, лежащей на месте в обоих деревьях (3874 байта).
# Питон в этом скрипте читается со stdin (`python3 - <<PY`), и `__file__` там не путь
# скрипта: путь поиска уезжал мимо `hooks/lib`, импорт падал, замка не было по-настоящему —
# два реестра писались без взаимного исключения при семи параллельных сессиях.
# Дефект жил незамеченным, потому что «библиотеки нет» и «путь построен неверно» шли ОДНИМ
# каналом (корень R6): сообщение читалось как честное «инструмента здесь нет».
#
# Ноги держат ОБЕ стороны различения — без второй тест зеленел бы у прибора, который просто
# никогда не говорит о замке.
#
# Состояние уводится к себе (STATE_DIR/KIA_OUTPUT): прибор пишет отчёт в общий путь, и
# прогон на фикстуре затирает рабочий — поймано 10 сентября 2026 на соседнем тесте
# (отчёт стал «хранится 1, 100% базы»). Из 23 тестов прибора так делали 21.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

command -v git >/dev/null 2>&1 || { echo "нет git — пропуск"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3 — пропуск"; exit 0; }

# --- T1: библиотека НА МЕСТЕ → о замке ни слова ---
W1=$(mktemp -d)
( cd "$REPO" && git archive HEAD ) 2>/dev/null | tar -x -C "$W1" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_kia_lock_lib_found.sh:$LINENO" >&2; exit 1; }
cp "$REPO/scripts/knowledge-instrument-audit.sh" "$W1/scripts/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_kia_lock_lib_found.sh:$LINENO" >&2; exit 1; }
N1=$(cd "$W1" && CLAUDSOUL_REPO="$W1" LESSONS_DIR="$W1/knowledge" \
     STATE_DIR="$W1/state" KIA_OUTPUT="$W1/report.md" \
     bash scripts/knowledge-instrument-audit.sh 2>&1 | grep -c 'БЕЗ замка')
[ "${N1:-1}" -eq 0 ] && ok \
    || bad T1 "при живой state_lock.py прибор $N1 раз сказал «БЕЗ замка» — путь ищется не там"

# --- T2: библиотека СНЯТА → прибор обязан сказать ---
# Положительный контроль: без него T1 зелен и у прибора, который о замке молчит всегда.
W2=$(mktemp -d)
( cd "$REPO" && git archive HEAD ) 2>/dev/null | tar -x -C "$W2" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_kia_lock_lib_found.sh:$LINENO" >&2; exit 1; }
cp "$REPO/scripts/knowledge-instrument-audit.sh" "$W2/scripts/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_kia_lock_lib_found.sh:$LINENO" >&2; exit 1; }
rm -f "$W2/hooks/lib/state_lock.py"
N2=$(cd "$W2" && CLAUDSOUL_REPO="$W2" LESSONS_DIR="$W2/knowledge" \
     STATE_DIR="$W2/state" KIA_OUTPUT="$W2/report.md" \
     bash scripts/knowledge-instrument-audit.sh 2>&1 | grep -c 'БЕЗ замка')
[ "${N2:-0}" -gt 0 ] && ok \
    || bad T2 "библиотека снята, а прибор промолчал — отсутствие замка стало невидимым"

rm -rf "$W1" "$W2" 2>/dev/null
echo "kia lock lib: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
