#!/usr/bin/env bash
# communication-cap-check.sh — знание об ОДНОМ собеседнике не растёт выше потолка n=1.
# Результат: в базе нет per-speaker знаний с одним собеседником и confidence выше 2
# Проверка результата: bash scripts/communication-cap-check.sh даёт 0
#
# Повод (D251). Собственное правило проекта: «Communication knowledge is additionally
# limited: confidence capped at 2 until confirmed by different interlocutors. One opinion ≠
# universal rule» (rules/CLAUDE.md, «Principle of uncertainty»). Механизма, проверяющего
# потолок, не было ни одного — правило жило текстом, и замер 1 сентября 2026 нашёл четыре
# нарушения, самое старое с confidence 5.
#
# ПРИЗНАК И ЕГО ГРАНИЦА. Ловится не «домен communication», а ЗАЯВЛЕННАЯ односторонность:
# `scope: per-speaker` либо `mixed` при `valid_for` короче двух собеседников. Именно это
# поле говорит «знание про конкретного собеседника», и именно тогда confidence выше 2
# утверждает больше, чем видел автор.
#
# КОНТРПРИМЕР (признак обязан НЕ поймать): знание, у которого communication — один из
# нескольких доменов, а per-speaker scope не объявлен вовсе. Пример в базе:
# `principle-continuous-learning-gated-action` (domain: cognitive_architecture, agent_design,
# communication; confidence 5) — это утверждение об устройстве обучения, а не об одном
# собеседнике. Признак по домену поймал бы его и был бы неправ: замер по базе даёт 6
# совпадений по домену против 4 по scope, то есть треть была бы ложной.
#
# НАЗВАННЫЙ ПРЕДЕЛ: второй собеседник виден только там, где кто-то заполнил `valid_for`.
# База одного собеседника не отличима от базы, где поле просто не ведут. Условие снятия:
# когда speaker_id начнёт проставляться механически при записи знания.
set -uo pipefail

LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
MAX="${COMM_CAP_MAX:-2}"
[ -d "$LESSONS" ] || { echo "базы знаний нет: $LESSONS"; exit 0; }

N=0
for f in "$LESSONS"/*.md; do
    [ -f "$f" ] || continue
    sc=$(awk -F': *' '/^scope:/ {print $2; exit}' "$f" 2>/dev/null | tr -d ' ')
    case "$sc" in per-speaker|mixed) ;; *) continue ;; esac
    cf=$(awk -F': *' '/^confidence:/ {print $2; exit}' "$f" 2>/dev/null | tr -d ' ')
    case "${cf:-}" in ''|*[!0-9]*) continue ;; esac
    [ "$cf" -gt "$MAX" ] || continue
    # Число собеседников: элементы valid_for. Пустой список и одиночка равны по смыслу —
    # подтверждение получено от одного источника.
    vf=$(awk -F'[][]' '/^valid_for:/ {print $2; exit}' "$f" 2>/dev/null)
    # `printf '%s\n'`, а не `printf '%s'`: wc -l считает ПЕРЕВОДЫ строк, и без хвостового
    # перевода одиночный собеседник давал 0 — знание с двумя было бы обвинено так же, как
    # знание без единого. Поймано прогоном на живой базе до первого замера.
    cnt=$(printf '%s\n' "${vf:-}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
    [ "${cnt:-0}" -ge 2 ] && continue
    N=$((N + 1))
    printf '  · %-58s confidence=%s scope=%s собеседников=%s\n' \
        "$(basename "$f" .md)" "$cf" "$sc" "${cnt:-0}"
done

if [ "$N" -eq 0 ]; then
    printf 'потолок n=1 соблюдён: per-speaker знаний выше confidence %s нет\n' "$MAX"
    exit 0
fi
printf 'нарушений потолка n=1: %s (правило: confidence ≤ %s, пока подтверждение от одного собеседника)\n' \
    "$N" "$MAX"
printf 'Исполнимо без разрешения: снизить confidence до %s либо внести второго собеседника в valid_for.\n' "$MAX"
exit 1
