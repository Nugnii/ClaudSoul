#!/usr/bin/env bash
# test_adv3_bump_pending_no_trailing_newline.sh — «погашено записей: 1» должно означать, что
# запись погашена.
#
# Результат: после вызова, отчитавшегося о гашении, dis_scan_open этой записи в открытых
# не показывает, а файл очереди остаётся построчным (одна запись — одна строка).
# Проверка результата: bash hooks/tests/test_adv3_bump_pending_no_trailing_newline.sh даёт 0
#
# Атака. dis_close_outcome дописывает строку через `>>` (строка 145), не проверяя, чем
# кончается файл. Если последняя строка очереди не завершена переводом строки, закрывающая
# запись приклеивается К НЕЙ ЖЕ: получается одна строка с двумя объектами JSON. Читатель
# очереди построчный (hooks/disagreement-lib.sh:88, awk по строкам, `$0 ~ /"outcome":"pending"/`)
# — он видит в этой строке `pending` и продолжает считать запись ОТКРЫТОЙ, хотя скрипт уже
# отчитался «погашено записей: 1». Тот же счёт по строкам ведёт metrics-collector.sh:553.
#
# Достижимость: продюсер (throttle_mark, hooks/throttle-lib.sh:105) перевод строки пишет,
# поэтому вход возникает при обрыве записи (ENOSPC, убитый процесс) или правке журнала
# рукой. Скрипт от такого входа не защищается никак и молча отчитывается об успехе.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$HOOKS_DIR/knowledge-counter-bump.sh"
LIB="$HOOKS_DIR/disagreement-lib.sh"
[ -f "$BUMP" ] || { echo "FAIL: $BUMP не найден"; exit 1; }
[ -f "$LIB" ] || { echo "FAIL: $LIB не найден"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

unset CLAUDE_STATE_DIR
export LESSONS_DIR="$TMP/lessons"
export STATE_DIR="$TMP/state"
export CLAUDE_CODE_SESSION_ID="adv3-nl"
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

cat > "$LESSONS_DIR/pattern-tail.md" <<'EOF'
---
name: pattern-tail
type: pattern
confidence: 4
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
---

тело
EOF

PEND="$STATE_DIR/disagreement-pending-SIDX.jsonl"
# Последняя строка БЕЗ перевода строки в конце.
printf '{"date":"2026-08-28T10:00:00Z","key":"pattern-tail","outcome":"pending","confidence":4,"tool":"Edit"}' > "$PEND"

OUT=$(DIS_SESSION=SIDX bash "$BUMP" pattern-tail not_applicable "мимо" 2>&1); RC=$?
echo "--- код возврата: $RC"
echo "--- вывод: $OUT"

OPEN=$(bash -c 'set -uo pipefail; source "$1"; dis_scan_open "$2"' _ "$LIB" "$STATE_DIR" 2>/dev/null)
LINES=$(grep -c '' "$PEND")

echo "--- очередь после вызова (строк: $LINES):"
sed 's/^/    /' "$PEND"
echo "--- dis_scan_open:"; printf '%s\n' "$OPEN" | sed 's/^/    /'

if grep -Fq "pattern-tail" <<< "$OUT"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: не тот вывод"; fi

if grep -Fq "pattern-tail" <<< "${OPEN:-}"; then
    FAIL=$((FAIL+1))
    echo "FAIL [ложное гашение]: скрипт отчитался о гашении, а dis_scan_open по-прежнему"
    echo "  считает запись открытой — алерт session-collector будет печататься дальше,"
    echo "  и каждый следующий вызов будет снова дописывать в файл ту же закрывающую строку."
else
    PASS=$((PASS+1))
fi

if [ "$LINES" -eq 2 ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [склейка]: в файле $LINES строк(и) вместо 2 — закрывающая запись приклеена"
    echo "  к незавершённой предыдущей, и построчные читатели (disagreement-lib.sh:88,"
    echo "  metrics-collector.sh:553) видят один объект вместо двух."
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
