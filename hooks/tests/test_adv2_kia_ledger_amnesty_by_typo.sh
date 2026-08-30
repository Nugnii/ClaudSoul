#!/usr/bin/env bash
# АТАКА: опечатка в знании списывает накопленный срок очереди, и замер из красного
# становится зелёным.
#
# knowledge-instrument-audit.sh:261 — `ledger = {k: v for k, v in ledger.items() if k in in_queue}`.
# Отметку входа теряет ЛЮБОЙ пункт, выпавший из очереди, а не только получивший
# вердикт. Комментарий выше (строки 196-198) заявляет единственную причину потери:
# «знание, покинувшее очередь (получило instrument_verdict)».
#
# Но выпасть можно и по нечитаемому полю: `confirmed_count: девять` даёт cc = 0
# (строка 140), пункт не проходит порог и исчезает из in_queue. В ТОМ ЖЕ прогоне
# скрипт сам печатает «НЕ ПРОЧИТАНО полей: 1» — то есть знает, что выпадение вызвано
# нечитаемостью, а не разбором, — и всё равно стирает отметку.
#
# Итог: 99 дней просрочки исчезают, код возврата падает с 1 («есть находки») до 0
# («находок нет»), а measurement-due.sh при 0 ставит отметку прогона и уводит вывод
# в /dev/null. Просроченный пункт становится невидим.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
FAILED=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s: %s\n' "$1" "$2"; FAILED=1; }

T=$(mktemp -d); L="$T/l"; S="$T/s"; mkdir -p "$L" "$S"
trap 'rm -rf "$T"' EXIT

OLD=$(python3 -c "import datetime;print((datetime.date.today()-datetime.timedelta(days=99)).isoformat())")
write_knowledge() {
    cat > "$L/pattern-aged.md" <<EOF
---
outcome: error
status: active
confidence: 4
impact: 5
confirmed_count: $1
description: Стоит в очереди 99 дней, вердикта не получал
---
EOF
}
printf '{"pattern-aged": "%s"}' "$OLD" > "$S/knowledge-instrument-queue.json"

run() { LESSONS_DIR="$L" STATE_DIR="$S" bash "$AUDIT" >/dev/null 2>&1; RC=$?; }

write_knowledge 9;        run; RC_A=$RC; LED_A=$(cat "$S/knowledge-instrument-queue.json")
write_knowledge "девять"; run; RC_B=$RC; LED_B=$(cat "$S/knowledge-instrument-queue.json")
write_knowledge 9;        run; RC_C=$RC; LED_C=$(cat "$S/knowledge-instrument-queue.json")
ROW_C=$(grep 'pattern-aged' "$S/knowledge-instrument.md" 2>/dev/null)

echo "A (поле цело):        rc=$RC_A реестр=$(tr -d '\n ' <<< "$LED_A")"
echo "B (опечатка в поле):  rc=$RC_B реестр=$(tr -d '\n ' <<< "$LED_B")"
echo "C (опечатку убрали):  rc=$RC_C реестр=$(tr -d '\n ' <<< "$LED_C")"
echo "C, строка отчёта:     $ROW_C"

if [ "$RC_A" -eq 1 ]; then
    ok "T1 до опечатки пункт просрочен (rc=1)"
else
    bad "T1" "атака собрана неверно: ожидался rc=1 на шаге A, получен $RC_A"
fi

# T2: прогон, который САМ признал поле нечитаемым, не имеет права списывать срок —
# выпадение вызвано не разбором.
if grep -q 'pattern-aged' <<< "$LED_B"; then
    ok "T2 отметка входа пережила нечитаемое поле"
else
    bad "T2" "нечитаемое поле стёрло дату входа $OLD; реестр после прогона B: $(tr -d '\n ' <<< "$LED_B")"
fi

# T3: после починки опечатки возраст обязан остаться 99, а не начаться заново.
if grep -q "$OLD" <<< "$LED_C"; then
    ok "T3 после починки пункт помнит свой срок"
else
    bad "T3" "срок начат заново: реестр после C = $(tr -d '\n ' <<< "$LED_C") (ожидалось $OLD)"
fi

# T4: и замер обязан остаться красным — пункт как стоял 99 дней, так и стоит.
if [ "$RC_C" -eq 1 ]; then
    ok "T4 замер остался красным"
else
    bad "T4" "замер позеленел (rc=$RC_C): 99 дней просрочки списаны опечаткой, которую уже исправили"
fi

echo
[ "$FAILED" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL"; exit 1; }
