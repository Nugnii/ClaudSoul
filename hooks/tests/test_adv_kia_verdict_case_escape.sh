#!/usr/bin/env bash
# test_adv_kia_verdict_case_escape.sh — АТАКА: `Candidate` с заглавной выпускает пункт из
# очереди — тот самый D106, ради закрытия которого очередь и переделывали.
#
# Скрипт (knowledge-instrument-audit.sh:141) сравнивает вердикт с литералом побайтово:
#   if verdict and verdict != "candidate":
# Всё, что не совпало посимвольно, считается ОТКАЗНЫМ вердиктом («инструментом не станет»)
# — включая написание того же слова с заглавной и написание с приставшей пунктуацией.
# Пункт уходит из очереди, ничего не построив, и печатается в таблице с заголовком
# «Оценены: инструментом не станут» — дословно то, на что жалуется комментарий строк 133-140:
# «pattern-subject-of-measurement-mismatch простоял так с 29 июля в таблице с заголовком
# "инструментом не станут", хотя вердикт означал "станет"».
#
# Разбор ставит вердикт рукой: в боевой базе 15 строк `instrument_verdict`, все написаны
# рукой, 12 из них с комментарием через `#`. Опечатка в регистре одного слова возвращает дефект
# целиком, и в отчёте это выглядит как законный разбор, а не как ошибка.
#
# Ожидание: пункт с вердиктом «кандидат» остаётся в очереди при любом регистре и не
# объявляется отказным при неизвестном написании.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

probe() {   # probe <метка> <строка вердикта>
    local T; T=$(mktemp -d); mkdir -p "$T/l" "$T/s"
    cat > "$T/l/pattern-x.md" <<KN
---
type: pattern
confirmed_count: 9
outcome: error
status: active
$2
description: "проба"
---
# Тело
KN
    LESSONS_DIR="$T/l" STATE_DIR="$T/s" bash "$AUDIT" >"$T/out" 2>&1
    Q=$(sed -n 's/.*очередь на производство: \([0-9]*\);.*/\1/p' "$T/out")
    A=$(sed -n 's/.*оценены и не станут: \([0-9]*\).*/\1/p' "$T/out")
    echo "  $1 → очередь=$Q, «не станут»=$A"
    LAST_REPORT="$T/s/knowledge-instrument.md"
    [ "$Q" = "1" ]
}

echo "эталон — вердикт как в базе (строчными, с комментарием):"
probe "candidate   # выразим" 'instrument_verdict: candidate   # выразим, инструмента нет' \
    && ok base || { echo "SKIP: базовый случай сломан, сравнивать не с чем"; exit 0; }

echo "атака 1 — та же буква, другой регистр:"
if probe "Candidate" 'instrument_verdict: Candidate   # выразим, инструмента нет'; then
    ok C1
else
    bad C1 "заглавная выпустила пункт из очереди; в отчёте он попал под «инструментом не станут»: $(grep -c 'Candidate' "$LAST_REPORT" 2>/dev/null) упоминаний"
fi

echo "атака 2 — верхний регистр целиком:"
probe "CANDIDATE" 'instrument_verdict: CANDIDATE' && ok C2 || bad C2 "CANDIDATE выпустил пункт из очереди"

echo "атака 3 — пунктуация прилипла к слову:"
probe "candidate, но" 'instrument_verdict: candidate, но признак ещё не написан' \
    && ok C3 || bad C3 "запятая после слова выпустила пункт из очереди"

echo "атака 4 — неизвестное написание молча становится отказом:"
probe "candidate_pending" 'instrument_verdict: candidate_pending' \
    && ok C4 || bad C4 "неизвестный вердикт объявлен отказным вместо того чтобы быть названным"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
