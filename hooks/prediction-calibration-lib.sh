#!/usr/bin/env bash
# prediction-calibration-lib.sh — мост L4↔L5: агрегация точности предсказаний.
# en: bridge L4<->L5 — aggregate prediction accuracy by type from SESSION.md files.
#
# Источник данных — таблицы `### Predictions` в SESSION.md проектов:
#   | P1:need | predicted | actual | exact|adjacent|miss|pending | lesson |
# Тип в номере (`P1:need`) введён v1.19.0; строки без типа считаются `untyped` —
# история не переписывается, типизация набирается вперёд (append-only журнал).
#
# Формула точности одна и названа: accuracy = (exact + 0.5×adjacent) / решённых.
# `pending` — не решение, в знаменатель не входит.
#
# Гейты выборки (v1.12.0: «вывод о достоверности не делается ниже порога»):
#   - всего секций Predictions < PRED_MIN_SESSIONS (5) → только счёт, без вердикта;
#   - по типу решённых < PRED_MIN_PER_TYPE (5) → строка есть, вердикта нет.
# Пороги правила моста: accuracy < 40% → снизить confidence типа, > 80% → повысить.
#
# «Не измеряли» отличается от «нет расхождения»: если SESSION.md не найдены вовсе —
# блок прямо говорит об этом, а не показывает нули.
#
# Разбор — awk по колонкам `|`, без классов символов с кириллицей
# (pattern-shell-portability): маркеры P/exact/adjacent/miss/pending — ASCII.

# pred_scan_files [roots] — список SESSION.md по корням (разделитель — двоеточие).
# ponytail: maxdepth 3 покрывает все известные проекты; глубже — не проект, а артефакт.
pred_scan_files() {
    local roots="${1:-${PRED_SCAN_ROOTS:-$HOME/My Project:$HOME/Documents/Claude/Projects}}"
    local IFS=':'
    local -a _r=()
    local d
    for d in $roots; do
        [ -d "$d" ] && _r+=("$d")
    done
    [ "${#_r[@]}" -gt 0 ] || return 0
    find "${_r[@]}" -maxdepth 3 -name SESSION.md -type f 2>/dev/null | sort
}

# pred_aggregate < список файлов на stdin, по одному пути на строку >
# Пути содержат пробелы («My Project») — поэтому файлы конкатенируются потоком,
# а не передаются awk аргументами: словоразбиение сломало бы каждый второй путь.
# stdout, поля через пробел, по строке на тип (+ итог):
#   TYPE decided exact adjacent miss acc_pct
#   TOTAL sections decided exact adjacent miss acc_pct
pred_aggregate() {
    local f
    { while IFS= read -r f; do [ -f "$f" ] && cat "$f"; done; } | awk -F'|' '
        /^### Predictions/ { sections++ }
        {
            # Колонка 2 = " P3:need ", колонка 5 = " exact "
            id = $2; gsub(/[[:space:]]/, "", id)
            if (id !~ /^P[0-9]+(:[a-z]+)?$/) next
            verdict = $5; gsub(/[[:space:]]/, "", verdict)
            if (verdict != "exact" && verdict != "adjacent" && verdict != "miss") next
            type = "untyped"
            if (index(id, ":") > 0) type = substr(id, index(id, ":") + 1)
            n[type]++; total++
            if (verdict == "exact")    { e[type]++; te++ }
            if (verdict == "adjacent") { a[type]++; ta++ }
            if (verdict == "miss")     { m[type]++; tm++ }
        }
        END {
            for (t in n) {
                acc = int((2 * e[t] + a[t]) * 50 / n[t])
                printf "%s %d %d %d %d %d\n", t, n[t], e[t], a[t], m[t], acc
            }
            if (total > 0) {
                tacc = int((2 * te + ta) * 50 / total)
                printf "TOTAL %d %d %d %d %d %d\n", sections, total, te, ta, tm, tacc
            } else if (sections > 0) {
                printf "TOTAL %d 0 0 0 0 0\n", sections
            }
        }
    ' 2>/dev/null
}

# pred_calibration_block [roots] [warnfile] — готовый markdown-блок для metrics.md.
# Строки-рекомендации `- ⚠️ …` дописываются в warnfile (если задан): блок обычно
# берут через command substitution, а это подоболочка — глобальная переменная
# оттуда не выживает, файл выживает.
pred_calibration_block() {
    local min_sessions="${PRED_MIN_SESSIONS:-5}"
    local min_per_type="${PRED_MIN_PER_TYPE:-5}"
    local warnfile="${2:-}"

    local files agg
    files=$(pred_scan_files "${1:-}")
    echo ""
    echo "## Prediction calibration (L4↔L5)"
    if [ -z "$files" ]; then
        echo "_Не измеряли: SESSION.md не найдены в корнях сканирования._"
        return 0
    fi
    agg=$(printf '%s\n' "$files" | pred_aggregate)
    if [ -z "$agg" ]; then
        echo "_Не измеряли: секций Predictions нет ни в одном SESSION.md ($(printf '%s\n' "$files" | grep -c '') файлов просмотрено)._"
        return 0
    fi

    local sections decided te ta tm tacc
    read -r _ sections decided te ta tm tacc <<EOF
$(printf '%s\n' "$agg" | grep '^TOTAL ')
EOF
    echo "**Формула:** accuracy = (exact + 0.5×adjacent) / решённых; pending не считается."
    echo "**Секций Predictions:** ${sections} · решённых предсказаний: ${decided} (exact ${te} / adjacent ${ta} / miss ${tm})"
    echo ""
    if [ "${sections:-0}" -lt "$min_sessions" ]; then
        echo "ℹ️ Секций ${sections} < ${min_sessions} — счёт ведётся, вердикт по правилу моста не выносится (гейт выборки)."
        return 0
    fi
    echo "| Тип | Решённых | exact | adjacent | miss | Accuracy | Вердикт (правило <40% ↓ / >80% ↑) |"
    echo "|-----|----------|-------|----------|------|----------|-----------------------------------|"
    local t n e a m acc verdict
    while read -r t n e a m acc; do
        [ "$t" = "TOTAL" ] && continue
        if [ "$n" -lt "$min_per_type" ]; then
            verdict="выборка мала (< ${min_per_type})"
        elif [ "$acc" -lt 40 ]; then
            verdict="снизить confidence типа"
            [ -n "$warnfile" ] && echo "- ⚠️ L4↔L5: предсказания типа «${t}» точны на ${acc}% (< 40%, n=${n}) — снизить confidence этого типа" >> "$warnfile"
        elif [ "$acc" -gt 80 ]; then
            verdict="повысить confidence типа"
            [ -n "$warnfile" ] && echo "- ⚠️ L4↔L5: предсказания типа «${t}» точны на ${acc}% (> 80%, n=${n}) — confidence этого типа можно повышать" >> "$warnfile"
        else
            verdict="в норме"
        fi
        echo "| ${t} | ${n} | ${e} | ${a} | ${m} | ${acc}% | ${verdict} |"
    done <<EOF
$(printf '%s\n' "$agg" | sort)
EOF
    echo "| **итого** | **${decided}** | ${te} | ${ta} | ${tm} | **${tacc}%** | — |"
}
