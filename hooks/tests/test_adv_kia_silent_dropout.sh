#!/usr/bin/env bash
# test_adv_kia_silent_dropout.sh — АТАКА: знание пропадает из отчёта целиком, и ни одна
# строка вывода об этом не говорит.
#
# Число подтверждений читается так (knowledge-instrument-audit.sh:105-108):
#     try:    cc = int(field(t, "confirmed_count") or 0)
#     except ValueError: cc = 0
# `field` (строки 48-50) берёт ВЕСЬ хвост строки: `9   # уточнено 2026-08` целиком уходит в
# int(), тот падает, и обработчик подставляет НОЛЬ. Дальше проверка `cc >= min_conf`
# (строка 131) не проходит, и знание не попадает ни в очередь, ни в раздел «оценены».
# В отчёте его нет вообще — оно просто исчезает, как будто подтверждений не набрало.
#
# Ноль вместо «не смог прочитать» — это подстановка значения, которое ОТВЕЧАЕТ на вопрос
# замера, вместо признания, что ответа нет. Для замера, чей смысл — считать, сколько знаний
# ждёт производства, потеря пункта неотличима от его отсутствия.
#
# Достижимость. Комментарий через `#` — не выдумка теста, а принятая в проекте запись
# соседних полей: в боевой базе так написаны 12 строк `instrument_verdict` из 15, а
# `knowledge/META.md:85-86` показывает такую же запись прямо на числовых полях:
#     confidence: 1-5           # Уверенность (растёт с подтверждениями)
#     impact: 1-5               # Серьёзность последствий при игнорировании
# То есть образец формата предлагает ровно ту запись, на которой замер теряет знание.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

T=$(mktemp -d); L="$T/l"; S="$T/s"; mkdir -p "$L" "$S"
mk() {
    cat > "$L/$1.md" <<KN
---
type: pattern
confirmed_count: $2
outcome: error
status: active
description: "проба"
---
# Тело
KN
}

mk pattern-plain    '28'
mk pattern-comment  '28   # уточнено 2026-08'
mk pattern-quoted   '"28"  # так пишут в META'
mk pattern-float    '28.0'

OUT=$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$AUDIT" 2>&1); RC=$?
echo "rc=$RC"; echo "$OUT" | sed 's/^/    /'
echo "--- строки отчёта по каждому знанию ---"
for n in pattern-plain pattern-comment pattern-quoted pattern-float; do
    printf '    %-18s %s\n' "$n" "$(grep -c "\`$n\`" "$S/knowledge-instrument.md")"
done

seen() { grep -q "\`$1\`" "$S/knowledge-instrument.md"; }

seen pattern-plain || { echo "SKIP: базовый случай не попал в отчёт — сравнивать не с чем"; exit 0; }

if seen pattern-comment; then ok F1; else
    bad F1 "знание с 28 подтверждениями и комментарием через # исчезло из отчёта целиком: ни в очереди, ни в «оценены», ни строки о нечитаемом поле"
fi
if seen pattern-quoted; then ok F2; else
    bad F2 "кавычки плюс комментарий — то же исчезновение, вывод молчит"
fi
if seen pattern-float; then ok F3; else
    bad F3 "confirmed_count: 28.0 прочитан как 0 и знание выпало без единого слова"
fi

Q=$(sed -n 's/.*очередь на производство: \([0-9]*\);.*/\1/p' <<<"$OUT")
if [ "$Q" = "4" ]; then ok F4; else
    bad F4 "«очередь на производство: ${Q}» при 4 годных знаниях — счётчик замера показывает потерю как норму"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
