#!/usr/bin/env bash
# test_event_project_scope.sh — внешние поводы разбора не текут между проектами.
#
# Результат: событие видно только своему проекту; закрытие в одном проекте не гасит
#            чужие; закрытое событие того же вида заводится заново
# Проверка результата: bash hooks/tests/test_event_project_scope.sh даёт 0
#
# Повод, 9 сентября 2026. Журнал `pending-events.jsonl` один на все проекты и поля проекта
# не имел. Следствий два, оба измерены на живом журнале (62 записи):
#   · `rc_close_events` гасил ВСЕ открытые записи файла — пункт долга, записанный в одном
#     проекте, закрывал события всех остальных, ни одно из которых не разбирали;
#   · дедуп `rc_note_event` смотрел на весь файл НЕЗАВИСИМО от статуса, поэтому закрытое
#     событие с той же деталью не заводилось больше никогда.
# Вместе это давало «62 записи, все 62 closed»: сигнал `event` был мёртв по построению,
# и гейт не мог назвать поводом ни один красный прогон и ни один откат.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/root-cause-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() {  # ck <что> <ожидалось> <получено>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL: $1"; echo "   ожидалось: [$2]"; echo "   получено:  [$3]"; fi
}

A=/proj/A; B=/proj/B
RC_EVENT_PROJECT="$A" rc_note_event "$TMP" hotfix-repeat "a.ts чинился 2+ раз"
RC_EVENT_PROJECT="$B" rc_note_event "$TMP" hotfix-repeat "b.ts чинился 2+ раз"

ck "проект A видит только своё" \
   "hotfix-repeat: a.ts чинился 2+ раз" \
   "$(RC_EVENT_PROJECT="$A" rc_open_events "$TMP")"
ck "проект B видит только своё" \
   "hotfix-repeat: b.ts чинился 2+ раз" \
   "$(RC_EVENT_PROJECT="$B" rc_open_events "$TMP")"

RC_EVENT_PROJECT="$A" rc_close_events "$TMP"
ck "закрытие в A гасит A" "" "$(RC_EVENT_PROJECT="$A" rc_open_events "$TMP")"
ck "закрытие в A НЕ гасит B" \
   "hotfix-repeat: b.ts чинился 2+ раз" \
   "$(RC_EVENT_PROJECT="$B" rc_open_events "$TMP")"

# Событие мира, случившееся снова, есть НОВОЕ событие: тот же файл, чинённый повторно, —
# ровно тот повод, ради которого журнал заведён.
RC_EVENT_PROJECT="$A" rc_note_event "$TMP" hotfix-repeat "a.ts чинился 2+ раз"
ck "закрытое событие заводится заново" \
   "hotfix-repeat: a.ts чинился 2+ раз" \
   "$(RC_EVENT_PROJECT="$A" rc_open_events "$TMP")"

# Открытое не дублируется: повтор в том же открытом состоянии — тот же повод.
RC_EVENT_PROJECT="$A" rc_note_event "$TMP" hotfix-repeat "a.ts чинился 2+ раз"
ck "открытое не дублируется" "3" "$(wc -l < "$TMP/pending-events.jsonl" | tr -d ' ')"

# Запись без поля project (заведена до правки) принадлежит всем — историю не теряем.
printf '{"ts":"2026-09-01T00:00:00Z","kind":"ci-red","detail":"старое","status":"open"}\n' >> "$TMP/pending-events.jsonl"
ck "запись без проекта видна любому" \
   "ci-red: старое" \
   "$(RC_EVENT_PROJECT=/proj/C rc_open_events "$TMP")"

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
