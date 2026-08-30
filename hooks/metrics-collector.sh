#!/usr/bin/env bash
# metrics-collector.sh — вызывается auto-scanner / /knowledge-audit: считает метрики здоровья базы, пишет в state/metrics.md.
# en: called by auto-scanner / /knowledge-audit: computes knowledge-base health metrics, writes state/metrics.md.
# Считает статические метрики из файлов global-lessons/
# Результаты пишет в ~/.claude/hooks/state/metrics.md
# Вызывается из auto-scanner или вручную через /knowledge-audit

set -euo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

# Разбор дат — через portable-lib: у BSD и GNU date разный синтаксис, и `date -j` роняет
# этот хук на Linux. Запасная ветка повторяет ту же пробу GNU → BSD, чтобы незадеплоенная
# библиотека не превращала все даты в «без даты» и не занижала freshness молча.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then source "$PORTABLE_LIB"; else iso_epoch() { date -d "${1:-}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${1:-}" +%s 2>/dev/null || echo 0; }; fi

# Мост L4↔L5 (v1.19.0): агрегация точности предсказаний из SESSION.md проектов.
# Библиотека ищется сначала рядом, потом в установленном каталоге (обратный порядок
# молча выключает секцию на чистой машине — case-2026-06-20-hook-dependency-install-drift).
for _pred_lib in "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/prediction-calibration-lib.sh" \
                 "$HOME/.claude/hooks/prediction-calibration-lib.sh"; do
    [ -f "$_pred_lib" ] && { . "$_pred_lib"; break; }
done

# Мост L2↔L7 (v1.20.0): доля и глубина со-эволюционного знания.
for _cocog_lib in "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/co-cognition-lib.sh" \
                  "$HOME/.claude/hooks/co-cognition-lib.sh"; do
    [ -f "$_cocog_lib" ] && { . "$_cocog_lib"; break; }
done

KNOWLEDGE_DIR="$LESSONS_DIR"
# STATE_DIR — из paths-lib (источается выше)
METRICS_FILE="$STATE_DIR/metrics.md"
INJECTION_LOG="$STATE_DIR/injection-log.jsonl"
# Архив ротации (D45): писатель уносит туда строки старше окна хранения, чтобы файл не
# рос третий месяц. Суммарные показатели считаются по логу И архиву — иначе ротация
# уронила бы «Инжекций (из лога)» без объяснения, и число выглядело бы регрессом.
INJECTION_ARCHIVE="${INJECTION_LOG%.jsonl}-archive.jsonl"
# ВСЕ читатели лога идут через этот источник, а не только счётчик строк. Первая версия
# подключила к архиву один `LOG_LINES`, а `VALID_LINES` оставила на голом логе — разница
# знаменателей дала «битых строк: 3432», ровно размер архива. Выдуманное число, попавшее
# в живые метрики: смешение знаменателей — тот же класс, что чинился весь релиз.
_inj_all() { cat "$INJECTION_ARCHIVE" "$INJECTION_LOG" 2>/dev/null; }
ITR_HISTORY="$STATE_DIR/intrusiveness-history.jsonl"

mkdir -p "$STATE_DIR"

# --- Counts ---
CASES=0
PATTERNS=0
PRINCIPLES=0
TOTAL=0
ACTIVE=0
WEAKENED=0
DEPRECATED=0

TOTAL_CONFIRMED=0
UNREADABLE_FIELDS=0
TOTAL_CONTRADICTED=0

FRESH_COUNT=0       # last_confirmed < 30 days
STALE_COUNT=0       # last_confirmed >= 30 days
NO_DATE_COUNT=0     # no last_confirmed

TODAY_EPOCH=$(date +%s)
THIRTY_DAYS=$((30 * 86400))

for file in "$KNOWLEDGE_DIR"/*.md; do
    [ -f "$file" ] || continue
    BASENAME=$(basename "$file")
    [ "$BASENAME" = "META.md" ] && continue

    TOTAL=$((TOTAL + 1))

    # Count by type
    case "$BASENAME" in
        case-*)      CASES=$((CASES + 1)) ;;
        pattern-*)   PATTERNS=$((PATTERNS + 1)) ;;
        principle-*) PRINCIPLES=$((PRINCIPLES + 1)) ;;
    esac

    # Read frontmatter
    FRONTMATTER=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$file")

    # Status
    STATUS=$(echo "$FRONTMATTER" | grep '^status:' | sed 's/^status:[[:space:]]*//' | tr -d '"' || true)
    case "$STATUS" in
        active|"")  ACTIVE=$((ACTIVE + 1)) ;;
        weakened)   WEAKENED=$((WEAKENED + 1)) ;;
        deprecated) DEPRECATED=$((DEPRECATED + 1)) ;;
    esac

    # Confirmed/contradicted totals
    CONF=$(echo "$FRONTMATTER" | grep '^confirmed_count:' | grep -oE '[0-9]+' | head -1 || true)
    CONTR=$(echo "$FRONTMATTER" | grep '^contradicted_count:' | grep -oE '[0-9]+' | head -1 || true)
    # Нечитаемое поле считается ОТДЕЛЬНО, а не складывается нулём в итог. Ноль правдив
    # там, где читается СЧЁТ (пустой вход честно равен нулю), и лжив там, где читается
    # ЗНАЧЕНИЕ поля: отсутствие значения не есть значение «ноль». Итог «подтверждений
    # всего» иначе занижается молча, а печатается как измеренный.
    #
    # Считается только у ОПЕРАЦИОННОГО контура (case/pattern/principle), где поле
    # предусмотрено схемой. У энциклопедического (entity/fact/relation) его нет по
    # построению — 104 записи из 395, — и «поля нет» там не равно «поле не прочитано».
    # Первая редакция этого счётчика различия не делала и дала 212 при двух настоящих:
    # предмет счёта не совпал с предметом утверждения.
    case "$BASENAME" in
        case-*|pattern-*|principle-*)
            [ -z "$CONF" ] && UNREADABLE_FIELDS=$((UNREADABLE_FIELDS + 1))
            [ -z "$CONTR" ] && UNREADABLE_FIELDS=$((UNREADABLE_FIELDS + 1))
            ;;
    esac
    CONF="${CONF:-0}"
    CONTR="${CONTR:-0}"
    TOTAL_CONFIRMED=$((TOTAL_CONFIRMED + CONF))
    TOTAL_CONTRADICTED=$((TOTAL_CONTRADICTED + CONTR))

    # Freshness: last_confirmed within 30 days
    LAST_CONF=$(echo "$FRONTMATTER" | grep '^last_confirmed:' | sed 's/^last_confirmed:[[:space:]]*//' | tr -d '"' || true)
    if [ -n "$LAST_CONF" ] && [ "$LAST_CONF" != "YYYY-MM-DD" ]; then
        # Parse date to epoch. Формат не передаём: голую дату iso_epoch сам приводит к
        # полуночи, тогда как `-f "%Y-%m-%d"` на BSD дописал бы текущее время суток.
        # Ноль при неразобранной дате даёт сама iso_epoch — отдельный `|| echo 0` не нужен.
        CONF_EPOCH=$(iso_epoch "$LAST_CONF")
        if [ "$CONF_EPOCH" -gt 0 ]; then
            AGE=$((TODAY_EPOCH - CONF_EPOCH))
            if [ "$AGE" -lt "$THIRTY_DAYS" ]; then
                FRESH_COUNT=$((FRESH_COUNT + 1))
            else
                STALE_COUNT=$((STALE_COUNT + 1))
            fi
        else
            NO_DATE_COUNT=$((NO_DATE_COUNT + 1))
        fi
    else
        NO_DATE_COUNT=$((NO_DATE_COUNT + 1))
    fi
done

# --- Calculate metrics ---

# depth_ratio: доля ОБОБЩЕНИЙ в операционной базе — (patterns + principles) /
# (cases + patterns + principles), целевой коридор 10-20%.
#
# До 2026-08-09 здесь стояло `principles / (cases + patterns)`: паттерны не
# входили в числитель, но раздували знаменатель, поэтому метрика измеряла не
# глубину базы, а долю принципов в ней. Давало 4.92% → целочисленное деление до
# 4 → предупреждение «мало обобщений» на пороге 5, при том что обобщений было
# 16.7% — внутри коридора, который обещал соседний комментарий. Расходились три
# определения сразу: здесь, в skills/knowledge-audit/SKILL.md (`principles /
# total`) и в постановке задачи — ровно principle-single-source-of-truth.
# Пороги приведены к заявленному коридору: ниже 10 — мало, выше 30 — обобщения
# без опоры на кейсы.
if [ $((CASES + PATTERNS + PRINCIPLES)) -gt 0 ]; then
    DEPTH_RATIO=$(( ((PATTERNS + PRINCIPLES) * 100) / (CASES + PATTERNS + PRINCIPLES) ))
else
    DEPTH_RATIO=0
fi

# freshness: % of knowledge confirmed within 30 days — target > 40%
DATABLE=$((FRESH_COUNT + STALE_COUNT))
if [ "$DATABLE" -gt 0 ]; then
    FRESHNESS=$(( (FRESH_COUNT * 100) / DATABLE ))
else
    FRESHNESS=0
fi

# contradiction_ratio: contradictions / confirmations — target < 20%
if [ "$TOTAL_CONFIRMED" -gt 0 ]; then
    CONTRADICTION_RATIO=$(( (TOTAL_CONTRADICTED * 100) / TOTAL_CONFIRMED ))
else
    CONTRADICTION_RATIO=0
fi

# --- Hit rate from injection log ---
HIT_RATE="n/a"
INJECTIONS_TOTAL=0
UNIQUE_INJECTED=0
UNIQUE_SCORABLE=0
MALFORMED=0
NEVER_INJECTED=""
TOP_INJECTED=""
AVG_SCORE="n/a"
if [ -f "$INJECTION_LOG" ]; then
    LOG_LINES=$({ _inj_all | grep -c '' || true; })
    LOG_LINES="${LOG_LINES:-0}"
    INJ_FILES=""
    INJ_SCORES=""
    if command -v jq &>/dev/null; then
        # `jq -rR 'fromjson? // empty'` — канонический устойчивый разбор jsonl проекта.
        # Голый `jq -r '.file'` обрывался на первой битой строке (286 из 7665) и молча
        # отдавал огрызок: 10 уникальных знаний вместо 99, hit_rate 34% вместо реального.
        # `select(.injected != false)` — обратная совместимость: у старых записей поля
        # нет (null != false → true), новые ранги 4-6 (контрольная группа) отсеиваются.
        INJ_FILES=$({ _inj_all | jq -rR 'fromjson? // empty | select(.injected != false) | .file' 2>/dev/null || true; })
        # score 99 — синтетический маркер mcp-semantic fallback, не оценка релевантности;
        # это половина записей, и в среднем они дают 52 вместо реальных ~4.6.
        INJ_SCORES=$({ _inj_all | jq -rR 'fromjson? // empty | select(.injected != false and .score != 99) | .score' 2>/dev/null || true; })
        VALID_LINES=$({ _inj_all | jq -rR 'fromjson? // empty | "x"' 2>/dev/null || true; } | grep -c '' || true)
        MALFORMED=$((LOG_LINES - ${VALID_LINES:-0}))
        # Второй режим отказа, невидимый счётчику битых строк. Разделитель `|` кладётся
        # поверх свободного текста, и если санитизация регрессирует, строка останется
        # ВАЛИДНЫМ JSON, а поля сдвинутся: confidence и impact станут нулями. Счётчик
        # битых такого не увидит вовсе. Сегодня таких записей 0 из 816 у нового писателя,
        # минимальные значения в базе — confidence 2 и impact 3, поэтому ноль здесь
        # означает поломку, а не редкий валидный случай.
        FIELD_SHIFT=$({ _inj_all | jq -rR 'fromjson? // empty | select(.via != null and (.confidence == 0 or .impact == 0)) | "x"' 2>/dev/null || true; } | grep -c '' || true)
        FIELD_SHIFT="${FIELD_SHIFT:-0}"
    else
        # Деградация без jq: та же семантика грубо, средний score недоступен.
        INJ_FILES=$({ _inj_all | grep -v '"injected":false' 2>/dev/null || true; } | \
            grep -oE '"file":"[^"]+"' | cut -d'"' -f4 || true)
    fi

    if [ -n "$INJ_FILES" ]; then
        INJECTIONS_TOTAL=$({ printf '%s\n' "$INJ_FILES" | grep -c '' || true; })
        INJECTIONS_TOTAL="${INJECTIONS_TOTAL:-0}"
        INJECTED_FILES=$(printf '%s\n' "$INJ_FILES" | sort -u)
        UNIQUE_INJECTED=$({ printf '%s\n' "$INJECTED_FILES" | grep -c '' || true; })
        UNIQUE_INJECTED="${UNIQUE_INJECTED:-0}"

        # Top-5 most injected (file + count)
        TOP_INJECTED=$(printf '%s\n' "$INJ_FILES" | sort | uniq -c | sort -rn | head -5 | \
            awk '{printf "  %s (%d раз)\n", $2, $1}' || true)

        # hit_rate И never_injected — один проход по реально существующим на диске
        # pattern/principle. Лог содержит ещё case/fact/relation (их кладёт mcp-fallback),
        # и деление всех уникальных на PATTERNS+PRINCIPLES дало бы 341%. Пересечение с
        # диском заодно отбрасывает призраков — знания, удалённые после инжекта.
        SCORABLE=$((PATTERNS + PRINCIPLES))
        for file in "$KNOWLEDGE_DIR"/pattern-*.md "$KNOWLEDGE_DIR"/principle-*.md; do
            [ -f "$file" ] || continue
            BN=$(basename "$file")
            if grep -Fqx "$BN" 2>/dev/null <<< "$INJECTED_FILES"; then
                UNIQUE_SCORABLE=$((UNIQUE_SCORABLE + 1))
            else
                NEVER_INJECTED="${NEVER_INJECTED}  ${BN}\n"
            fi
        done
        if [ "$SCORABLE" -gt 0 ]; then
            HIT_RATE="$((UNIQUE_SCORABLE * 100 / SCORABLE))%"
        fi

        if [ -n "$INJ_SCORES" ]; then
            AVG_SCORE=$(printf '%s\n' "$INJ_SCORES" | \
                awk '{s+=$1; n++} END{if(n>0) printf "%.1f", s/n; else printf "n/a"}' || echo "n/a")
        fi
    fi
fi

# --- Health assessment ---
HEALTH="✅ Здоровая"
WARNINGS=""

if [ "$DEPTH_RATIO" -lt 10 ]; then
    WARNINGS="${WARNINGS}\n- ⚠️ depth_ratio ${DEPTH_RATIO}% < 10% — мало обобщений, только частные случаи"
fi
if [ "$DEPTH_RATIO" -gt 30 ]; then
    WARNINGS="${WARNINGS}\n- ⚠️ depth_ratio ${DEPTH_RATIO}% > 30% — слишком много обобщений без кейсов"
fi
if [ "$FRESHNESS" -lt 20 ]; then
    WARNINGS="${WARNINGS}\n- ⚠️ freshness ${FRESHNESS}% < 20% — знания устаревают быстрее чем обновляются"
fi
if [ "$CONTRADICTION_RATIO" -gt 20 ]; then
    WARNINGS="${WARNINGS}\n- ⚠️ contradiction_ratio ${CONTRADICTION_RATIO}% > 20% — много противоречий"
fi
if [ "$WEAKENED" -gt 0 ]; then
    WARNINGS="${WARNINGS}\n- ⚠️ ${WEAKENED} weakened знаний — требуют ревью"
fi

if [ -n "$WARNINGS" ]; then
    HEALTH="⚠️ Требует внимания"
fi

# --- Здоровье контура опровержения (v1.12.0) ---
# Читаем через общую библиотеку, чтобы алерт в session-collector, закрытие в /learn
# и эта метрика видели контур одинаково. Три разных способа смотреть на один контур
# уже дали три разных ответа в истории intrusiveness — второй раз не повторяем.
DIS_CLOSED=0; DIS_EXPIRED=0; DIS_OPEN=0; DIS_TOTAL=0; DIS_RATE=0
DIS_LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/disagreement-lib.sh"
if [ -f "$DIS_LIB_PATH" ]; then
    # shellcheck source=/dev/null
    source "$DIS_LIB_PATH"
    read -r DIS_CLOSED DIS_EXPIRED DIS_OPEN <<EOF
$(dis_stats "$STATE_DIR" 2>/dev/null || echo "0 0 0")
EOF
    DIS_CLOSED="${DIS_CLOSED:-0}"; DIS_EXPIRED="${DIS_EXPIRED:-0}"; DIS_OPEN="${DIS_OPEN:-0}"
    DIS_TOTAL=$(( DIS_CLOSED + DIS_EXPIRED + DIS_OPEN ))
    [ "$DIS_TOTAL" -gt 0 ] && DIS_RATE=$(( DIS_CLOSED * 100 / DIS_TOTAL ))
fi

# --- Intrusiveness trends (v1.3.2, дедупликация v1.12.0) ---
# Reads ~/.claude/hooks/state/intrusiveness-history.jsonl. Computes last-20
# aggregates and trend vs prev-20.
# Feeds H13 (gentle_acceptance_rate), H14 (override_freq), H15 (debt_carryover).
#
# ВАЖНО про источник. Шапка до v1.12.0 обещала «one JSON line per closed session»,
# и весь расчёт на это опирался. Неправда: `itr_append_history` дописывает строку на
# КАЖДЫЙ Stop, а строка — накопительный снимок сессии целиком. На живых данных
# 2879 строк это 213 сессий (в среднем 13,5 строк, максимум 156 на одну).
#
# Последствия, пока считали по строкам:
#   1. Суммирование считало одни и те же события столько раз, сколько было Stop.
#   2. Сессии взвешивались по болтливости, а не одинаково.
#   3. `tail -20` брал 20 строк = ~5 сессий, одну из них по 8 раз; prev-20 перекрывался
#      с last-20 внутри одной сессии, и «тренд» сравнивал сессию сама с собой.
# Итог: метрика показывала gentle_acceptance_rate 0% там, где честный счёт даёт 19%.
#
# Свёртка: берём ПОСЛЕДНЮЮ запись на session_id — она и есть итог сессии.
#
# Output: global ITR_TRENDS_BLOCK (markdown, injected below), plus warnings.
ITR_TRENDS_BLOCK=""
ITR_SESSIONS_TOTAL=0
ITR_ACCEPTANCE_RATE="n/a"
ITR_SESSIONS_JSONL=""

# Минимальные выборки перед тем, как назвать метрику разкалиброванной. Алерт на
# n=4 — не сигнал, а шум: ровно с таким горело «0% < 30%» до v1.12.0.
ITR_MIN_GENTLE="${ITR_MIN_GENTLE:-20}"
ITR_MIN_INTERVENTIONS="${ITR_MIN_INTERVENTIONS:-30}"

# Свёртка истории к одной записи на сессию, в хронологическом порядке.
# Сортировка по closed_at с падением на date — записи старой схемы closed_at не имеют.
_itr_sessions() {
    jq -sc '
        group_by(.session_id)
        | map(sort_by(.closed_at // .date // "") | last)
        | sort_by(.closed_at // .date // "")
        | .[]
    ' "$ITR_HISTORY" 2>/dev/null || true
}

if [ -f "$ITR_HISTORY" ] && command -v jq >/dev/null 2>&1; then
    ITR_SESSIONS_JSONL=$(_itr_sessions)
    if [ -n "$ITR_SESSIONS_JSONL" ]; then
        ITR_SESSIONS_TOTAL=$(printf '%s\n' "$ITR_SESSIONS_JSONL" | grep -c '' || echo 0)
    fi
fi

# Helper: compute aggregates for a JSONL slice on stdin → emits space-separated
# fields (17): sessions gentle_accepted gentle_ignored proactive override
# debt_surfaced debt_pending_sessions acceptance_pct avg_events avg_duration
# timing_peak_avg silence_peak_avg closing_avg
# focus_pct stuck_pct exploration_pct idle_pct
#
# State distribution percentages (fields 14-17, v1.3.3) are computed across
# all classified prompts in the slice — sum(distribution[state]) / sum(all).
# Sessions closed under schema < v3 contribute zeros and don't distort ratios.
_itr_aggregate() {
    jq -sr '
        . as $s
        | ($s | length) as $n
        | if $n == 0 then
            "0 0 0 0 0 0 0 n/a 0 0 0 0 0 n/a n/a n/a n/a"
          else
            (([.[] | .state_distribution.focus       // 0] | add)) as $sf
            | (([.[] | .state_distribution.stuck       // 0] | add)) as $ss
            | (([.[] | .state_distribution.exploration // 0] | add)) as $se
            | (([.[] | .state_distribution.idle        // 0] | add)) as $si
            | ($sf + $ss + $se + $si) as $st
            | [
              $n,
              ([.[] | .metrics.gentle_accepted       // 0] | add),
              ([.[] | .metrics.gentle_ignored        // 0] | add),
              ([.[] | .metrics.proactive_events      // 0] | add),
              ([.[] | .metrics.override_events       // 0] | add),
              ([.[] | .metrics.silence_debt_surfaced // 0] | add),
              ([.[] | select((.debt.pending // 0) > 0)] | length),
              (
                ([.[] | .metrics.gentle_accepted // 0] | add) as $a
                | ([.[] | .metrics.gentle_ignored // 0] | add) as $i
                | if ($a + $i) == 0 then "n/a"
                  else (($a * 100) / ($a + $i) | floor | tostring) end
              ),
              (([.[] | .events_total // 0] | add) / $n | floor),
              (([.[] | .duration_min // 0] | add) / $n | floor),
              (([.[] | .cost_peaks.timing_max // 0]  | add) * 10 / $n | floor / 10),
              (([.[] | .cost_peaks.silence_max // 0] | add) * 10 / $n | floor / 10),
              (([.[] | .cost_peaks.closing // 0]     | add) * 10 / $n | floor / 10),
              (if $st == 0 then "n/a" else (($sf * 100) / $st | floor | tostring) end),
              (if $st == 0 then "n/a" else (($ss * 100) / $st | floor | tostring) end),
              (if $st == 0 then "n/a" else (($se * 100) / $st | floor | tostring) end),
              (if $st == 0 then "n/a" else (($si * 100) / $st | floor | tostring) end)
            ] | join(" ")
          end
    ' 2>/dev/null || echo "0 0 0 0 0 0 0 n/a 0 0 0 0 0 n/a n/a n/a n/a"
}

if [ "$ITR_SESSIONS_TOTAL" -gt 0 ] && command -v jq >/dev/null 2>&1; then
    # Срезы берутся из СВЁРНУТОГО списка: 20 сессий, а не 20 строк лога.
    # Slice 1: last 20 sessions
    LAST20=$(printf '%s\n' "$ITR_SESSIONS_JSONL" | tail -20 | _itr_aggregate)
    # Slice 2: prev 20 (sessions 21..40 from the end)
    PREV20=""
    if [ "$ITR_SESSIONS_TOTAL" -gt 20 ]; then
        PREV20=$(printf '%s\n' "$ITR_SESSIONS_JSONL" | tail -40 | head -20 | _itr_aggregate)
    fi

    # Parse last20 fields (13 legacy + 4 state-distribution percentages)
    read -r L_N L_ACC L_IGN L_PRO L_OVR L_SURF L_DEBTS L_ACCPCT L_AVGEV L_AVGDUR L_TIM L_SIL L_CLO L_FOC L_STK L_EXP L_IDL <<< "$LAST20"
    ITR_ACCEPTANCE_RATE="${L_ACCPCT}%"

    # Trend arrow helper: compare last vs prev for a numeric field.
    # Echoes "↑", "↓", "→", or "" (no prev).
    _itr_arrow() {
        local cur="$1" prev="$2"
        [ -z "$prev" ] && { echo ""; return; }
        [ "$cur" = "$prev" ] && { echo "→"; return; }
        # awk handles floats from the aggregates above
        awk -v c="$cur" -v p="$prev" 'BEGIN { if (c+0 > p+0) print "↑"; else if (c+0 < p+0) print "↓"; else print "→" }'
    }

    ARROW_ACCPCT=""
    ARROW_OVR=""
    ARROW_DEBTS=""
    if [ -n "$PREV20" ]; then
        read -r P_N P_ACC P_IGN P_PRO P_OVR P_SURF P_DEBTS P_ACCPCT P_AVGEV P_AVGDUR P_TIM P_SIL P_CLO P_FOC P_STK P_EXP P_IDL <<< "$PREV20"
        # Acceptance arrow: only if both have numeric value
        if [ "$L_ACCPCT" != "n/a" ] && [ "$P_ACCPCT" != "n/a" ]; then
            ARROW_ACCPCT=$(_itr_arrow "$L_ACCPCT" "$P_ACCPCT")
        fi
        ARROW_OVR=$(_itr_arrow "$L_OVR" "$P_OVR")
        # debt_carryover trend: compare % of sessions with pending debt
        L_DEBTPCT=$(awk -v d="$L_DEBTS" -v n="$L_N" 'BEGIN { if (n>0) print int(d*100/n); else print 0 }')
        P_DEBTPCT=$(awk -v d="$P_DEBTS" -v n="$P_N" 'BEGIN { if (n>0) print int(d*100/n); else print 0 }')
        ARROW_DEBTS=$(_itr_arrow "$L_DEBTPCT" "$P_DEBTPCT")
    fi

    # Warnings for intrusiveness trends.
    # Порог без минимальной выборки — генератор ложных тревог: до v1.12.0 «0% < 30%»
    # горело при четырёх наблюдениях. Процент без n не выводим нигде.
    GENTLE_N=$(( L_ACC + L_IGN ))
    if [ "$L_ACCPCT" != "n/a" ] && [ "$GENTLE_N" -lt "$ITR_MIN_GENTLE" ]; then
        WARNINGS="${WARNINGS}\n- ℹ️ gentle_acceptance_rate ${L_ACCPCT}% — выборка мала (n=${GENTLE_N} < ${ITR_MIN_GENTLE}), вывод не делаем"
    elif [ "$L_ACCPCT" != "n/a" ] && [ "$L_ACCPCT" -lt 30 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- ⚠️ gentle_acceptance_rate ${L_ACCPCT}% (${L_ACC}/${GENTLE_N}) < 30% — cost model miscalibrated, слишком много gentle игнорируется"
    fi
    # Override budget audit: per risk table in PLAN Phase 13
    # If overrides > 20% of (gentle+proactive+override) — miscalibrated
    OVR_TOTAL=$((L_ACC + L_IGN + L_PRO + L_OVR))
    if [ "$OVR_TOTAL" -gt 0 ] && [ "$L_OVR" -gt 0 ]; then
        OVR_PCT=$(( L_OVR * 100 / OVR_TOTAL ))
        if [ "$OVR_TOTAL" -lt "$ITR_MIN_INTERVENTIONS" ]; then
            WARNINGS="${WARNINGS}\n- ℹ️ override rate ${OVR_PCT}% — выборка мала (n=${OVR_TOTAL} < ${ITR_MIN_INTERVENTIONS}), вывод не делаем"
        elif [ "$OVR_PCT" -gt 20 ]; then
            # Строка называет ФАКТ и не называет причину. Прежняя утверждала «cost model
            # miscalibrated» — это интерпретация, а не измерение, и она неверна для сессии,
            # где собеседник раз за разом говорит «делай»: бюджет в 3 проактивных действия
            # рассчитан на разговор, а не на длинную авторизованную работу, и превышение
            # там ожидаемо. Разобрать, ЧТО именно оверрайдит, можно только вместе с
            # калибровкой порогов (BACKLOG D16), которая ждёт gentle-выборки.
            WARNINGS="${WARNINGS}\n- ⚠️ бюджет проактивных действий превышен в ${OVR_PCT}% случаев (${L_OVR}/${OVR_TOTAL}). Это факт, не диагноз: высокая доля ожидаема в длинной авторизованной работе. Причину можно называть только после калибровки порогов (BACKLOG D16)"
        fi
    fi

    # State-distribution warnings (v1.3.3): persistent stuck signal or
    # missing classifier data both deserve attention.
    if [ "$L_STK" != "n/a" ] && [ "$L_STK" -gt 30 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- ⚠️ state stuck ${L_STK}% > 30% — агент видит собеседника застрявшим чаще, чем нормально. Проверить: повторяющиеся ошибки, пропущенные root-cause расследования"
    fi

    # --- Условия возврата отложенных пунктов BACKLOG (v1.14.0) ---
    #
    # «Отложено» без проверяемого условия — это фраза, которую некому перечитать. За одну
    # сессию так накопилось 30 незакрытых пунктов, и большинство были названы вслух в тот
    # же момент, когда пропущены. Поэтому откладывание теперь обязано нести условие, а
    # условие обязано проверяться здесь — иначе оно тоже станет прозой.
    #
    # Проверяются те условия, для которых числа уже считаются выше. Пункт без числа сюда
    # не попадает: лучше пусто, чем ложный сигнал «пора».
    # Условие «данных хватит на калибровку» проверяется по ВСЕМУ корпусу, а не по окну
    # последних сессий. `GENTLE_N` — окно (для доли принятия это верно: она про свежее
    # поведение). Но готовность к калибровке — про объём корпуса, и на этом гейт
    # промахивался: в окне было 4 события при 2645 за всю историю, поэтому условие
    # возврата D16 «не выполнялось» месяцами при более чем стократном запасе.
    # Тот же класс, что D19: условие сработало и никем не читалось.
    # Условие возврата — сигнал ТОЛЬКО для открытого долга. Урок 2026-08-07: строки
    # «📋 BACKLOG D16/D17 … можно калибровать» горели после закрытия пунктов (v1.17.1),
    # и на протухшем сигнале была построена рекомендация «калибруй» — а калибровка уже
    # проведена с вердиктом «менять нечего». Сигнал проверял объём данных и не проверял
    # состояние долга: предмет замера не тот, о котором утверждение
    # (pattern-subject-of-measurement-mismatch, 5-й кейс формы).
    # Открыт = ☐ или ◐ (перевод в работу не гасит долг — v1.15.1). Альтернация, не класс
    # символов: не-ASCII в [...] читается как диапазон байтов (pattern-shell-portability).
    CLAUDSOUL_BACKLOG="${CLAUDSOUL_BACKLOG:-$CLAUDSOUL_ROOT/BACKLOG.md}"
    _backlog_open() {
        [ -n "${1:-}" ] && [ -f "$CLAUDSOUL_BACKLOG" ] || return 1
        grep -E "^- (☐|◐) \*\*${1}\*\*" "$CLAUDSOUL_BACKLOG" >/dev/null 2>&1
    }

    GENTLE_CORPUS=$({ cat "$STATE_DIR/intrusiveness-history.jsonl" 2>/dev/null || true; } \
        | jq -s '[.[] | (.metrics.gentle_accepted // 0) + (.metrics.gentle_ignored // 0)] | add // 0' 2>/dev/null)
    GENTLE_CORPUS=$(printf '%s' "${GENTLE_CORPUS:-0}" | tr -dc '0-9'); : "${GENTLE_CORPUS:=0}"
    if { _backlog_open D16 || _backlog_open D17; } && [ "${GENTLE_CORPUS:-0}" -ge "$ITR_MIN_GENTLE" ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D16/D17: gentle-событий в корпусе ${GENTLE_CORPUS} ≥ ${ITR_MIN_GENTLE} — условие возврата выполнено, пороги можно калибровать (в окне последних сессий: ${GENTLE_N})"
    fi
    if _backlog_open D19 && [ "$OVR_TOTAL" -ge "$ITR_MIN_INTERVENTIONS" ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D19: вмешательств ${OVR_TOTAL} ≥ ${ITR_MIN_INTERVENTIONS} — override rate можно оценивать"
    fi

    # D18 — порог rework-detector калибруется после накопления срабатываний.
    REWORK_FIRED=$({ cat "$STATE_DIR"/rework-fired-*.jsonl 2>/dev/null || true; } | grep -c '' || true)
    REWORK_FIRED=$(printf '%s' "${REWORK_FIRED:-0}" | tr -d '[:space:]')
    if _backlog_open D18 && [ "${REWORK_FIRED:-0}" -ge "${REWORK_MIN_SAMPLE:-30}" ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D18: срабатываний rework-detector ${REWORK_FIRED} ≥ ${REWORK_MIN_SAMPLE:-30} — порог можно калибровать"
    fi

    # --- Условия, у которых до 2026-08-01 не было проверяющего вовсе ---------------
    #
    # Замер: из 13 отложенных пунктов девять несли условие возврата ПРОЗОЙ. Правило
    # самого BACKLOG это запрещает («откладывание без проверяемого условия запрещено»),
    # и цена уже измерена: условие D16 было выполнено в 132 раза и лежало непрочитанным,
    # потому что гейт смотрел в окно последних сессий вместо корпуса.
    #
    # Сюда попадают только те условия, которые ВЫРАЖАЮТСЯ ЧИСЛОМ. Пункт, ждущий решения
    # собеседника, числом не выражается и здесь не появляется — иначе список условий
    # снова станет прозой, только в коде.

    # D25 — контекстный сигнал поправки: калибруется после накопления срабатываний.
    CORR_FIRED=$({ cat "$STATE_DIR"/correction-fired-*.jsonl 2>/dev/null || true; } | grep -c '' || true)
    CORR_FIRED=$(printf '%s' "${CORR_FIRED:-0}" | tr -d '[:space:]')
    if _backlog_open D25 && [ "${CORR_FIRED:-0}" -ge "${CORRECTION_MIN_SAMPLE:-30}" ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D25: срабатываний сигнала поправки ${CORR_FIRED} ≥ ${CORRECTION_MIN_SAMPLE:-30} — классификатор можно оценивать"
    fi

    # D57 — выборка round-trip гейта, уничтоженная уборкой 2026-07-31 (122 файла → 3).
    # Гейт снова начнёт что-то доказывать, когда сессий накопится заново.
    BLOCKER_SESSIONS=$({ ls "$STATE_DIR"/blocker-fired-*.jsonl 2>/dev/null || true; } | grep -c '' || true)
    BLOCKER_SESSIONS=$(printf '%s' "${BLOCKER_SESSIONS:-0}" | tr -d '[:space:]')
    if _backlog_open D57 && [ "${BLOCKER_SESSIONS:-0}" -ge "${COMPLIANCE_MIN_SESSIONS:-10}" ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D57: сессий с blocker-fired ${BLOCKER_SESSIONS} ≥ ${COMPLIANCE_MIN_SESSIONS:-10} — выборка round-trip гейта восстановилась"
    fi

    # D50 — скрытый класс `cmd | grep -q` под pipefail. Условие: рост базы знаний вдвое,
    # то есть момент, когда `find | grep -q` в knowledge-capture-reminder начнёт выдавать
    # достаточно строк, чтобы producer не успел дописать до выхода потребителя.
    KB_NOW=$({ ls "$LESSONS_DIR"/*.md 2>/dev/null || true; } | grep -c '' || true)
    KB_NOW=$(printf '%s' "${KB_NOW:-0}" | tr -d '[:space:]')
    if _backlog_open D50 && [ "${KB_NOW:-0}" -ge "${KB_DOUBLE_THRESHOLD:-574}" ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D50: записей в базе ${KB_NOW} ≥ ${KB_DOUBLE_THRESHOLD:-574} — база выросла вдвое, скрытый SIGPIPE может стать действующим"
    fi

    # D51 — реестр даёт срок, но не исполнение. Условие: три замера просрочены дольше
    # двух своих периодов подряд, то есть режим `check` доказанно не побуждает к прогону.
    MDUE="${CLAUDSOUL_MEASURE_DUE:-$CLAUDSOUL_ROOT/scripts/measurement-due.sh}"
    if [ -f "$MDUE" ]; then
        # Разбор через sed, а не awk с трёхаргументным `match()`: это GNU-расширение,
        # BSD awk падает с «illegal statement». Тот же pattern-shell-portability, и здесь
        # он проявился в скрипте, а не в хуке — блокер смотрит только на правки хуков.
        LONG_OVERDUE=0
        while IFS=' ' read -r _per _age; do
            case "${_per:-}${_age:-}" in ''|*[!0-9]*) continue ;; esac
            [ "$_age" -gt $(( 2 * _per )) ] 2>/dev/null && LONG_OVERDUE=$((LONG_OVERDUE + 1))
        done <<EOF
$({ bash "$MDUE" check 2>/dev/null || true; } | sed -n 's/.*период \([0-9][0-9]*\) дн.*последний прогон: \([0-9][0-9]*\) дн\. назад.*/\1 \2/p')
EOF
        LONG_OVERDUE=$(printf '%s' "${LONG_OVERDUE:-0}" | tr -d '[:space:]')
        if _backlog_open D51 && [ "${LONG_OVERDUE:-0}" -ge 3 ] 2>/dev/null; then
            WARNINGS="${WARNINGS}\n- 📋 BACKLOG D51: замеров просрочено дольше двух периодов: ${LONG_OVERDUE} — режим check доказанно не побуждает к прогону"
        fi
    fi

    # D20 — контур опровержения оживает с ПЕРВОЙ записью «знание оказалось неверным».
    # До неё contradicted_count = 0 остаётся фактом об отсутствии данных, а не о знании.
    # Считается ТОЛЬКО долговременный журнал. `/learn` пишет исход в оба файла — и в
    # посессионный `disagreement-pending-*`, и в durable `disagreement-outcomes` — поэтому
    # счёт по обоим удваивал каждую запись, сделанную в текущей сессии. Обнаружено на новом
    # счётчике пропусков: записал один случай, метрика показала два.
    OUTDATED_N=$({ grep -h '"outcome":"outdated_knowledge"' "$STATE_DIR"/disagreement-outcomes.jsonl 2>/dev/null || true; } | grep -c '' || true)
    # Разрыв «знание → действие»: знание относилось к делу и не было применено.
    # Отдельная величина, а не часть confirmed/contradicted: пропуск не подтверждает и
    # не опровергает знание. До 2026-08-01 такой случай было некуда записать, и он
    # растворялся в `not_applicable` — то есть главный вопрос проекта («действует ли
    # знание») не имел прибора вовсе.
    # --- Смешение алфавитов: у журнала появился читатель (D43) ------------------
    #
    # 167 файлов / 2690 записей писались с апреля, и не читал их НИКТО. Разбор показал,
    # что 94% — вообще не нарушения: составные через дефис (`dev-БД`, `Telegram-бот`),
    # нормальное русское техническое письмо. Детектор считал их ошибкой до 25.07.2026,
    # когда исключение добавили; после этой даты таких записей ноль.
    #
    # Настоящих — смешение ВНУТРИ слова (`коммit`, `guard'ом`) — 166, и в них лежал
    # ответ на вопрос, который стоило задать: май 81 → июнь 66 → июль 9. Три месяца
    # ответ был записан и не прочитан.
    #
    # Читается только настоящее: токен без дефиса. Показывается за 30 дней — тренд,
    # а не накопленный итог, иначе число застынет и перестанет что-либо значить.
    LANG_RECENT=$({ cat "$STATE_DIR"/output-violations-*.jsonl 2>/dev/null || true; } \
        | jq -rR 'fromjson? // empty | select((.token // "") | contains("-") | not) | .ts' 2>/dev/null \
        | awk -v cut="$(date -u -v-30d '+%Y-%m-%d' 2>/dev/null || date -u -d '30 days ago' '+%Y-%m-%d' 2>/dev/null)" \
              'cut == "" || substr($0,1,10) >= cut' | grep -c '' || true)
    LANG_RECENT=$(printf '%s' "${LANG_RECENT:-0}" | tr -d '[:space:]')
    if [ "${LANG_RECENT:-0}" -ge 1 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- ℹ️ смешение алфавитов внутри слова за 30 дней: ${LANG_RECENT} (составные через дефис не считаются — это не нарушение)"
    fi

    IGNORED_N=$({ grep -h '"outcome":"applicable_not_followed"' "$STATE_DIR"/disagreement-outcomes.jsonl 2>/dev/null || true; } | grep -c '' || true)
    : "${IGNORED_N:=0}"
    OUTDATED_N=$(printf '%s' "${OUTDATED_N:-0}" | tr -d '[:space:]')
    if _backlog_open D20 && [ "${OUTDATED_N:-0}" -ge 1 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- 📋 BACKLOG D20: зафиксировано опровержений ${OUTDATED_N} — контур ожил, механизмы можно оценивать по данным"
    fi
    # Разрыв «знание → действие» — единственная величина, прямо отвечающая на вопрос,
    # ради которого проект существует. Показывается с n, без процента: доля от горстки
    # записей ввела бы в заблуждение (гейт минимальной выборки, v1.12.0).
    IGNORED_N=$(printf '%s' "${IGNORED_N:-0}" | tr -d '[:space:]')
    if [ "${IGNORED_N:-0}" -ge 1 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}\n- ⚠️ знание было уместно и не применено: ${IGNORED_N} случая(ев) — это и есть разрыв «знание → действие»"
    fi

    # Build markdown block
    {
        echo ""
        echo "## Intrusiveness trends (L6 gate)"
        echo "**Источник:** \`$ITR_HISTORY\`"
        echo "**Сессий всего:** $ITR_SESSIONS_TOTAL"
        echo ""
        if [ "$ITR_SESSIONS_TOTAL" -lt 20 ]; then
            echo "_Недостаточно данных для trend-анализа (нужно ≥ 20 закрытых сессий, есть $ITR_SESSIONS_TOTAL)._"
            echo ""
            echo "### Кумулятивные метрики"
        else
            echo "### Последние 20 сессий"
        fi
        echo ""
        echo "| Метрика | Last 20 | Prev 20 | Trend |"
        echo "|---------|---------|---------|-------|"
        echo "| gentle accepted / ignored | ${L_ACC} / ${L_IGN} | ${P_ACC:-—} / ${P_IGN:-—} | |"
        if [ "$L_ACCPCT" = "n/a" ]; then
            echo "| gentle_acceptance_rate | n/a | ${P_ACCPCT:-—} | |"
        else
            # Процент всегда с размером выборки: число без n уже один раз прочли как факт.
            echo "| gentle_acceptance_rate | ${L_ACCPCT}% (${L_ACC}/${GENTLE_N}) | ${P_ACCPCT:-—}${P_ACCPCT:+%} | ${ARROW_ACCPCT} |"
        fi
        echo "| proactive events | ${L_PRO} | ${P_PRO:-—} | |"
        echo "| override events | ${L_OVR} | ${P_OVR:-—} | ${ARROW_OVR} |"
        echo "| debt surfaced / pending sessions | ${L_SURF} / ${L_DEBTS} | ${P_SURF:-—} / ${P_DEBTS:-—} | ${ARROW_DEBTS} |"
        echo "| avg events/session | ${L_AVGEV} | ${P_AVGEV:-—} | |"
        echo "| avg duration (min) | ${L_AVGDUR} | ${P_AVGDUR:-—} | |"
        echo "| avg cost_peaks (timing/silence/closing) | ${L_TIM} / ${L_SIL} / ${L_CLO} | ${P_TIM:-—} / ${P_SIL:-—} / ${P_CLO:-—} | |"
        # State distribution (v1.3.3) — only surface if classifier has data.
        if [ "$L_FOC" != "n/a" ] || [ "$L_STK" != "n/a" ] || [ "$L_EXP" != "n/a" ] || [ "$L_IDL" != "n/a" ]; then
            _fmt_pct() { if [ "$1" = "n/a" ]; then echo "—"; else echo "${1}%"; fi; }
            echo "| state focus/stuck/exploration/idle | $(_fmt_pct "$L_FOC") / $(_fmt_pct "$L_STK") / $(_fmt_pct "$L_EXP") / $(_fmt_pct "$L_IDL") | $(_fmt_pct "${P_FOC:-n/a}") / $(_fmt_pct "${P_STK:-n/a}") / $(_fmt_pct "${P_EXP:-n/a}") / $(_fmt_pct "${P_IDL:-n/a}") | |"
        fi
    } > "$STATE_DIR/.itr-trends.md.tmp"
    ITR_TRENDS_BLOCK=$(cat "$STATE_DIR/.itr-trends.md.tmp")
    rm -f "$STATE_DIR/.itr-trends.md.tmp"
fi

# --- Prediction calibration (мост L4↔L5, v1.19.0) ---
# Блок берётся через command substitution (подоболочка), поэтому рекомендации
# библиотека пишет в файл — иначе они не выжили бы (тот же класс, что ITR-блок).
PRED_BLOCK=""
if command -v pred_calibration_block >/dev/null 2>&1; then
    _pred_warn_tmp=$(mktemp "${TMPDIR:-/tmp}/pred-warn.XXXXXX") || _pred_warn_tmp=""
    PRED_BLOCK=$(pred_calibration_block "" "$_pred_warn_tmp" 2>/dev/null || true)
    if [ -n "$_pred_warn_tmp" ] && [ -s "$_pred_warn_tmp" ]; then
        while IFS= read -r _pw; do
            WARNINGS="${WARNINGS}\n${_pw}"
        done < "$_pred_warn_tmp"
    fi
    [ -n "$_pred_warn_tmp" ] && rm -f "$_pred_warn_tmp"
fi

# --- Co-cognition health (мост L2↔L7, v1.20.0) ---
COCOG_BLOCK=""
if command -v cocog_block >/dev/null 2>&1; then
    COCOG_BLOCK=$(cocog_block "$KNOWLEDGE_DIR" 2>/dev/null || true)
fi

# --- Write results ---
{
    echo "# Метрики здоровья системы знаний"
    echo "**Дата:** $(date '+%Y-%m-%d %H:%M')"
    echo "**Оценка:** $HEALTH"
    echo ""
    echo "## Состав базы"
    echo "| Тип | Количество |"
    echo "|-----|------------|"
    echo "| Cases | $CASES |"
    echo "| Patterns | $PATTERNS |"
    echo "| Principles | $PRINCIPLES |"
    echo "| **Всего** | **$TOTAL** |"
    echo ""
    echo "| Статус | Количество |"
    echo "|--------|------------|"
    echo "| Active | $ACTIVE |"
    echo "| Weakened | $WEAKENED |"
    echo "| Deprecated | $DEPRECATED |"
    echo ""
    echo "## Метрики"
    echo "| Метрика | Значение | Норма | Статус |"
    echo "|---------|----------|-------|--------|"
    if [ "$DEPTH_RATIO" -ge 5 ] && [ "$DEPTH_RATIO" -le 30 ]; then
        echo "| depth_ratio | ${DEPTH_RATIO}% | 10-20% | ✅ |"
    else
        echo "| depth_ratio | ${DEPTH_RATIO}% | 10-20% | ⚠️ |"
    fi
    if [ "$FRESHNESS" -ge 40 ]; then
        echo "| freshness | ${FRESHNESS}% | >40% | ✅ |"
    elif [ "$FRESHNESS" -ge 20 ]; then
        echo "| freshness | ${FRESHNESS}% | >40% | ⚡ |"
    else
        echo "| freshness | ${FRESHNESS}% | >40% | ⚠️ |"
    fi
    if [ "$CONTRADICTION_RATIO" -le 20 ]; then
        echo "| contradiction_ratio | ${CONTRADICTION_RATIO}% | <20% | ✅ |"
    else
        echo "| contradiction_ratio | ${CONTRADICTION_RATIO}% | <20% | ⚠️ |"
    fi
    echo "| hit_rate | ${HIT_RATE} | >30% | $([ "$HIT_RATE" = "n/a" ] && echo "📋" || echo "✅") |"
    # Здоровье контура опровержения (v1.12.0). До него не было ни одного числа о том,
    # закрываются ли записи вообще — и разрыв между кросс-сессионным алертом и
    # сессионным закрытием жил незамеченным, пока contradicted_count стоял на нуле.
    if [ "$DIS_TOTAL" -gt 0 ]; then
        echo "| disagreement_resolution_rate | ${DIS_RATE}% (${DIS_CLOSED}/${DIS_TOTAL}) | >50% | $([ "$DIS_RATE" -ge 50 ] 2>/dev/null && echo "✅" || echo "⚠️") |"
    else
        echo "| disagreement_resolution_rate | n/a | >50% | 📋 |"
    fi
    echo ""
    echo "## Детали"
    echo "- Подтверждений всего: $TOTAL_CONFIRMED"
    [ "${UNREADABLE_FIELDS:-0}" -gt 0 ] && \
        echo "- ⚠️ полей не прочитано: $UNREADABLE_FIELDS — итог занижен на неизвестную величину"
    echo "- Противоречий всего: $TOTAL_CONTRADICTED"
    echo "- Свежих (<30д): $FRESH_COUNT"
    echo "- Устаревших (>30д): $STALE_COUNT"
    echo "- Без даты: $NO_DATE_COUNT"
    echo "- Инжекций (из лога): $INJECTIONS_TOTAL"
    echo "- Уникальных знаний инжектировано: $UNIQUE_INJECTED"
    echo "- Из них pattern/principle: $UNIQUE_SCORABLE из $((PATTERNS + PRINCIPLES)) (= hit_rate)"
    echo "- Средний score инжекции: $AVG_SCORE (keyword; mcp-fallback score=99 не учитан)"
    if [ "${MALFORMED:-0}" -gt 0 ]; then
        # Без этой строки поломка разбора невидима: hit_rate 34% выглядел правдоподобно
        # три месяца, пока считался по 285 строкам из 7665.
        echo "- ⚠️ Битых строк в injection-log: $MALFORMED (пропущены при разборе)"
    fi
    if [ "${FIELD_SHIFT:-0}" -gt 0 ]; then
        # Строка валидна, а поля сдвинулись — отказ, который счётчик битых не ловит.
        echo "- ⚠️ Записей с обнулёнными confidence/impact: $FIELD_SHIFT (сдвиг полей, разделитель попал в текст)"
    fi
    if [ "$DIS_TOTAL" -gt 0 ]; then
        echo "- Контур опровержения: закрыто $DIS_CLOSED, истекло $DIS_EXPIRED, открыто $DIS_OPEN"
        if [ "$DIS_EXPIRED" -gt "$DIS_CLOSED" ] 2>/dev/null; then
            # Истекает больше, чем закрывается — контур собирает стимулы и теряет исходы.
            echo "- ⚠️ Истекает чаще, чем закрывается: исходы не доезжают до счётчиков"
        fi
    fi
    echo ""
    echo "## Injection Analytics"
    if [ -n "$TOP_INJECTED" ]; then
        echo "### Top-5 инжектируемых знаний"
        echo "$TOP_INJECTED"
    fi
    if [ -n "$NEVER_INJECTED" ]; then
        echo ""
        echo "### Patterns/principles без инжекций (potential dead weight)"
        echo -e "$NEVER_INJECTED"
    fi
    if [ -n "$ITR_TRENDS_BLOCK" ]; then
        echo "$ITR_TRENDS_BLOCK"
    fi
    if [ -n "$PRED_BLOCK" ]; then
        echo "$PRED_BLOCK"
    fi
    if [ -n "$COCOG_BLOCK" ]; then
        echo "$COCOG_BLOCK"
    fi
    if [ -n "$WARNINGS" ]; then
        echo ""
        echo "## Предупреждения"
        echo -e "$WARNINGS"
    fi
} > "$METRICS_FILE"

# --- Calibration progress (v1.4.0 Phase 3 step 3.1) ---
# Counts "valid chunks" in intrusiveness-history.jsonl = entries with a
# chunk boundary (stop|precompact, added in v1.3.8) AND at least one
# gentle/proactive event. Writes state/calibration-progress.json for
# session-start.sh to surface as startup signal.
#
# Valid chunk ≠ closed session. A session may produce multiple chunks
# (PreCompact snapshots + final Stop). Empty chunks (events_total == 0
# or pre-v1.3.8 legacy lines without boundary) don't count — they carry
# no gate data.
#
# Threshold 30 comes from Phase 3 criterion. Once reached, /calibrate
# (scripts/calibrate.py, step 3.3) has enough distribution to recommend
# constants for intrusiveness-state-lib.sh.
CALIB_PROGRESS="$STATE_DIR/calibration-progress.json"
CALIB_VALID=0
CALIB_GENTLE=0
CALIB_PROACTIVE=0
if [ -f "$ITR_HISTORY" ] && command -v jq >/dev/null 2>&1; then
    CALIB_AGG=$(jq -sr '
        [.[]
         | select((.boundary // "") == "stop" or (.boundary // "") == "precompact")
         | select(((.metrics.gentle_accepted // 0)
                  + (.metrics.gentle_ignored // 0)
                  + (.metrics.proactive_events // 0)) > 0)
        ] as $chunks
        | {
            valid: ($chunks | length),
            gentle: ([$chunks[] | (.metrics.gentle_accepted // 0) + (.metrics.gentle_ignored // 0)] | add // 0),
            proactive: ([$chunks[] | .metrics.proactive_events // 0] | add // 0)
          }
        | "\(.valid) \(.gentle) \(.proactive)"
    ' "$ITR_HISTORY" 2>/dev/null || echo "0 0 0")
    read -r CALIB_VALID CALIB_GENTLE CALIB_PROACTIVE <<< "$CALIB_AGG"
    CALIB_VALID="${CALIB_VALID:-0}"
    CALIB_GENTLE="${CALIB_GENTLE:-0}"
    CALIB_PROACTIVE="${CALIB_PROACTIVE:-0}"
fi
CALIB_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"valid_chunks":%d,"gentle_events_total":%d,"proactive_events_total":%d,"threshold":30,"last_updated":"%s"}\n' \
    "$CALIB_VALID" "$CALIB_GENTLE" "$CALIB_PROACTIVE" "$CALIB_NOW" > "$CALIB_PROGRESS"

# Output for caller (auto-scanner or direct)
if [ "$ITR_SESSIONS_TOTAL" -gt 0 ]; then
    echo "Metrics collected: $TOTAL knowledge files, health: $HEALTH; intrusiveness: $ITR_SESSIONS_TOTAL sessions (gentle acceptance: $ITR_ACCEPTANCE_RATE); calibration: $CALIB_VALID/30 valid chunks"
else
    echo "Metrics collected: $TOTAL knowledge files, health: $HEALTH; calibration: $CALIB_VALID/30 valid chunks"
fi
