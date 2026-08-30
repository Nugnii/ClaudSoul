#!/usr/bin/env bash
# АТАКА: уровень «доходит» считает СТРОКИ ЖУРНАЛА, а не знания, и доля выходит за 100%.
#
# knowledge-instrument-audit.sh:93-107 набирает `reached` из значений поля `file`
# журнала инжектов КАК ЕСТЬ: без сверки с базой и без приведения формы. Дальше
# len(reached) делится на `stored` — число файлов базы (строка 316) и печатается
# колонкой «Доля базы».
#
# Знаменатель и числитель считают разное:
#   · знание удалили или переименовали — прежнее имя навсегда осталось в журнале
#     и продолжает считаться «дошедшим» (журнал накопительный, 3,3 МБ на 2026-08-29);
#   · одно знание, записанное в двух формах (`pattern-x.md` и `pattern-x`), даёт
#     ДВА пункта: сравнения имён нет нигде, множество хранит сырые строки.
#
# Заявлено «Доля базы» — доля тех, кто в базе есть. Показывается доля журнальных
# строк к размеру базы, и она не ограничена сотней процентов.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
FAILED=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s: %s\n' "$1" "$2"; FAILED=1; }

T=$(mktemp -d); L="$T/l"; S="$T/s"; mkdir -p "$L" "$S"
trap 'rm -rf "$T"' EXIT

cat > "$L/pattern-one.md" <<'EOF'
---
outcome: success
status: active
confidence: 3
impact: 3
confirmed_count: 3
description: единственное знание базы
---
EOF

TODAY=$(date +%Y-%m-%d)
{
  printf '{"date":"%sT10:00:00","file":"pattern-one.md"}\n' "$TODAY"
  printf '{"date":"%sT10:00:00","file":"pattern-one"}\n'    "$TODAY"   # то же знание, другая форма
  printf '{"date":"%sT10:00:00","file":"pattern-udalyonnoe.md"}\n' "$TODAY"  # знание удалено
  printf '{"date":"%sT10:00:00","file":"case-staroe-imya.md"}\n'    "$TODAY"  # знание переименовано
} > "$S/injection-log.jsonl"

STDOUT=$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$AUDIT" 2>&1); RC=$?
REPORT=$(cat "$S/knowledge-instrument.md")
echo "--- stdout ---"; printf '%s\n' "$STDOUT"
echo "--- таблица уровней ---"; sed -n '/^| Уровень/,/^$/p' <<< "$REPORT"

# T1: в базе одно знание, и оно одно могло дойти до контекста.
if grep -q 'доходит 1' <<< "$STDOUT"; then
    ok "T1 «доходит» считает знания базы"
else
    R=$(sed -n 's/.*доходит \([0-9]*\).*/\1/p' <<< "$STDOUT" | head -1)
    bad "T1" "«доходит» = ${R:-?} при одном знании в базе: считаются строки журнала, включая удалённые имена и вторую форму того же имени"
fi

# T2: колонка названа «Доля базы» — доля не может быть больше базы.
OVER=$(grep -oE '\| [0-9]+\.[0-9]%' <<< "$REPORT" | tr -d '| %' | awk '$1>100{print;exit}')
if [ -z "$OVER" ]; then
    ok "T2 ни одна доля не превышает 100%"
else
    bad "T2" "в колонке «Доля базы» стоит ${OVER}% — числитель взят не из базы:
       $(grep 'доходило до контекста' <<< "$REPORT")"
fi

echo
[ "$FAILED" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL"; exit 1; }
