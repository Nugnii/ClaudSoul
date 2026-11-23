#!/usr/bin/env bash
# cross-contour-lib.sh — отбор кросс-контурных упоминаний (паттерн ↔ entity).
# en: picks cross-contour mentions to surface, shared by the activator and its witness.
#
# ПРЕФИКСЫ: cc_
# Результат: у отбора «какие пары показать» ОДИН владелец — и потребитель инжекта, и его
#   свидетель зовут эту функцию, а не свою копию.
# Проверка результата: bash hooks/tests/test_cross_contour_consumer.sh даёт 0
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. Логика жила ДВУМЯ копиями: блоком внутри
# `hooks/knowledge-activator.sh` и зеркалом внутри `hooks/tests/test_cross_contour_consumer.sh`
# («mirrors the block», строка 23 того файла). Судьба предшественников названа: обе копии
# сняты, оба места ЗОВУТ эту функцию.
#
# ЗАЧЕМ ВЫНЕСЕНО (23 сентября 2026, D474, род K, корень R1). Свидетель судил СВОЮ копию:
# выхолащивание `hooks/knowledge-activator.sh` не меняло его вердикта (прогон: живой 0,
# выхолощенный 0), то есть поломка боевого отбора прошла бы мимо него незамеченной. Копия
# разошлась бы с оригиналом молча — у факта «какие пары показать» было два владельца.
#
# cc_consume <журнал> <SORTED> [ранжированные] [порог] [файл-дедуп]
#   печатает строки вида «  - <знание> ↔ <сущность> (упомянуто: …)», не более трёх;
#   дописывает показанные ключи в файл-дедуп, если он назван.
#   Код 0 всегда: «нечего показать» — не ошибка.
cc_consume() {
    local log="$1" sorted="$2" ranked="${3:-}" threshold="${4:-0.6}" surfaced="${5:-}"
    [ -f "$log" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    local injected_kfs high_sim_pairs surfaced_existing
    injected_kfs=$(echo "$sorted" | awk -F'|' 'NF>=2 && $2 != ""{print $2}' | sort -u)
    high_sim_pairs=""
    if [ -n "$ranked" ] && [ -f "$ranked" ]; then
        high_sim_pairs=$(jq -rR --arg t "$threshold" \
            'fromjson? | select(.similarity != null and (.similarity | tonumber?) >= ($t | tonumber)) | "\(.knowledge_file)|\(.entity_file)"' \
            "$ranked" 2>/dev/null | sort -u)
    fi
    [ -n "$injected_kfs" ] || [ -n "$high_sim_pairs" ] || return 0

    surfaced_existing=""
    [ -n "$surfaced" ] && [ -f "$surfaced" ] && surfaced_existing=$(cat "$surfaced" 2>/dev/null)

    local all count=0 kf ef matched key keep
    # Журнал читается ЦЕЛИКОМ (D1006, 19-20 октября 2026). Прежде брались последние 200 строк, и это
    # держалось на том, что писатель дописывал на каждом прогоне весь набор пар: хвост и был
    # последним прогоном. Теперь журнал САМ — снимок последнего прогона (`mcp-server/ingest/discovery.py`:
    # пары, которые детектор находит сейчас, по строке на пару), и окно в 200 строк уронило бы пары
    # сверх двухсотой, как только их станет больше.
    all=$(cat "$log" 2>/dev/null \
        | jq -rR 'fromjson? | select(.knowledge_file and .entity_file) | "\(.knowledge_file)|\(.entity_file)|\(.matched // "")"' 2>/dev/null \
        | awk -F'|' '!seen[$1"|"$2]++' || true)
    while IFS='|' read -r kf ef matched; do
        [ -z "$kf" ] && continue
        [ "$count" -ge 3 ] && break
        key="${kf}|${ef}"
        if [ -n "$surfaced_existing" ] && grep -Fxq "$key" <<< "$surfaced_existing"; then
            continue
        fi
        keep=false
        if [ -n "$injected_kfs" ] && grep -Fxq "$kf" <<< "$injected_kfs"; then
            keep=true
        elif [ -n "$high_sim_pairs" ] && grep -Fxq "$key" <<< "$high_sim_pairs"; then
            keep=true
        fi
        if [ "$keep" = "true" ]; then
            printf '  - %s ↔ %s%s\n' "${kf%.md}" "${ef%.md}" "${matched:+ (упомянуто: ${matched})}"
            count=$((count + 1))
            if [ -n "$surfaced" ]; then
                mkdir -p "$(dirname "$surfaced")" 2>/dev/null || true
                printf '%s\n' "$key" >> "$surfaced" 2>/dev/null || true
            fi
        fi
    done <<< "$all"
}
