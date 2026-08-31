#!/usr/bin/env bash
# anchor-review-queue.sh — знания, стабильно всплывающие не к месту: очередь на сужение якорей (D229).
#
# Результат: у шума доставки есть владелец — знание с N и больше исходами «не к месту»
#            за окно названо кандидатом на пересмотр якорей, а не растворено в общей доле
# Проверка результата: bash scripts/anchor-review-queue.sh печатает очередь и даёт 0;
#            при непустой очереди — 1 (находка)
#
# Зачем (D229). Замер 31 августа 2026: 84 исхода из 216 (39%) — «не к месту». Это не
# приговор знанию (оно может быть верным) — это приговор его ЯКОРЯМ: они совпадают с
# ситуациями, где знание ни при чём. Исход not_applicable писался и никем не потреблялся.
#
# ЧТО РЕШАЕТ ЭТО ЧИСЛО. Знание из очереди — кандидат на сужение якорей через /retro
# (анализ, в каких ситуациях всплывало мимо, лежит в поле case записей журнала).
# Сужение делает человек; скрипт даёт имя, счёт и последние поводы.
#
# ОКНО В СЕССИЯХ, А НЕ В ДНЯХ: мера опыта — события, не календарь; журнал един,
# но несёт поле session — окно есть «последние K уникальных сессий журнала».
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SESSIONS="${ANCHOR_REVIEW_SESSIONS:-30}"
MIN_NA="${ANCHOR_REVIEW_MIN_NA:-3}"
command -v jq >/dev/null 2>&1 || { echo "нет jq"; exit 0; }

OUTCOMES="$STATE/disagreement-outcomes.jsonl"
[ -f "$OUTCOMES" ] || { echo "журнала исходов нет (STATE=$STATE)"; exit 0; }

QUEUE=$(jq -rRn --argjson sessions "$SESSIONS" --argjson minna "$MIN_NA" '
    [inputs | fromjson? // empty] as $all |
    # Свежесть сессии — дата её ПОСЛЕДНЕЙ записи. Прежняя форма `reverse | unique`
    # была дефектом: jq unique СОРТИРУЕТ, и «окно последних K» на деле было K
    # лексикографически первых сессий за всю историю — бэкфилл-батч 08.08 (116 записей
    # одной секунды) занимал очередь тремя неделями позже. Та же правка — в
    # scripts/injection-outcome.sh (общий шаблон окна, менять синхронно).
    ($all | group_by(.session) | map({s: .[0].session, last: (map(.date) | max)})
          | sort_by(.last) | reverse | .[0:$sessions] | map(.s)) as $recent |
    [$all[] | select((.session as $s | $recent | index($s)) and .outcome == "not_applicable")] as $na |
    ($na | group_by(.knowledge) | map(select(length >= $minna))
         | sort_by(-length) | .[]
         | "  \(.[0].knowledge): не к месту \(length) раз; последний повод: \(.[-1].case // "не назван" | .[0:100])")
' "$OUTCOMES" 2>/dev/null)

if [ -z "${QUEUE:-}" ]; then
    echo "очередь пересмотра якорей пуста (окно ${SESSIONS} сессий, порог ${MIN_NA})"
    exit 0
fi
N=$(printf '%s\n' "$QUEUE" | grep -c . 2>/dev/null || printf '0')
case "${N:-}" in ''|*[!0-9]*) N=0 ;; esac
echo "Очередь пересмотра якорей (окно ${SESSIONS} сессий, порог ${MIN_NA} «не к месту»):"
printf '%s\n' "$QUEUE"
echo "[замер: находки, не сбой] кандидатов на сужение якорей: $N — разбор через /retro"
exit 1
