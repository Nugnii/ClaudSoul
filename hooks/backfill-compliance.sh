#!/usr/bin/env bash
# backfill-compliance.sh — восстановить ЗАВИСИМУЮ ПЕРЕМЕННУЮ из архивных транскриптов.
# en: restores the DEPENDENT VARIABLE from archived transcripts (offline, read-only).
#
# НЕ хук. Разовый офлайн-прогон, читает только транскрипты, не трогает живое состояние.
#
#   bash hooks/backfill-compliance.sh --dry-run          # посчитать транскрипты
#   bash hooks/backfill-compliance.sh --limit 20         # частичный прогон
#   bash hooks/backfill-compliance.sh --class A          # только класс A
#   bash hooks/backfill-compliance.sh                    # полный прогон
#   bash hooks/backfill-compliance.sh --report           # кросс-таб по собранному
#   bash hooks/backfill-compliance.sh --verify-log       # ГЕЙТ: round-trip против логов
#
# Порядок применения: --verify-log → полный прогон → --report. Пока round-trip не
# сходится, остальное считать бессмысленно: парсер может выдумывать события.
#
# Отчёт НЕ считает p-value намеренно. Наблюдения кластеризованы по (сессия, файл),
# 70% событий приходятся на четыре документа одного проекта — наивный бином завысит
# значимость примерно вдвое. Кластерные ошибки — работа аналитика, не скрипта.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER="$HOOKS_DIR/lib/backfill-compliance-one.py"
PROJECTS_DIR="${BACKFILL_PROJECTS_DIR:-$HOME/.claude/projects}"
OUT_FILE="${COMPLIANCE_OUT:-$HOME/.claude/hooks/state/compliance-backfill.jsonl}"
STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
PARALLEL="${COMPLIANCE_PARALLEL:-4}"
CLASSES="${COMPLIANCE_CLASSES:-A,B,C}"

DRY_RUN=false
LIMIT=""
REPORT_ONLY=false
VERIFY_LOG=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --limit)   LIMIT="${2:-}"; shift 2 ;;
        --class)   CLASSES="${2:-A,B,C}"; shift 2 ;;
        --report)  REPORT_ONLY=true; shift ;;
        --verify-log) VERIFY_LOG=true; shift ;;
        *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
    esac
done

# --- Preflight ---
[ -f "$WORKER" ] || { echo "воркер не найден: $WORKER" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "нужен python3" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "нужен jq" >&2; exit 1; }
[ -d "$PROJECTS_DIR" ] || { echo "нет каталога транскриптов: $PROJECTS_DIR" >&2; exit 1; }

# Абсолютные пути обязательны: имена проектных каталогов начинаются с «-»
# («-Users-user-My-Project-ClaudSoul»), относительный путь jq/python примут за флаг.
TRANSCRIPTS=$(find "$PROJECTS_DIR" -name "*.jsonl" -type f 2>/dev/null | sort)
COUNT=$(printf '%s\n' "$TRANSCRIPTS" | grep -c '.' || echo 0)
if [ -n "$LIMIT" ]; then
    TRANSCRIPTS=$(printf '%s\n' "$TRANSCRIPTS" | head -n "$LIMIT")
    COUNT=$(printf '%s\n' "$TRANSCRIPTS" | grep -c '.' || echo 0)
fi

# --- Режим отчёта: только читает уже собранное ---
report() {
    [ -s "$OUT_FILE" ] || { echo "нет данных: $OUT_FILE" >&2; exit 1; }
    echo "=== Класс A: блокер long_lived_markdown_doc_edit ==="
    echo "Единица — интервал между двумя правками одного файла. FRESH = после маркера."
    echo "Три критерия печатаются вместе намеренно: это межкритериальное согласие вместо"
    echo "второго кодировщика. Вывод, выживающий только под одним из трёх, — артефакт границы."
    echo "  loose  — было любое чтение того же файла"
    echo "  main   — чтение целиком (без offset/limit), как просит blocker_reminder"
    echo "  strict — чтение целиком ДО любой другой правки в интервале"
    echo ""
    printf '%-16s %-8s %6s %7s %7s %7s %8s\n' "плечо" "экспозиц" "n" "loose" "main" "strict" "кластеров"
    jq -rs '
      [ .[] | select(.cls=="A" and .outcome != "na") ]
      | group_by([.arm, .exposure])
      | .[]
      | { arm: .[0].arm, exp: .[0].exposure, n: length,
          lo: ([.[] | select(.v_loose == true)] | length),
          mn: ([.[] | select(.v_main  == true)] | length),
          st: ([.[] | select(.v_strict == true)] | length),
          cl: ([.[].cluster] | unique | length) }
      | "\(.arm)\t\(.exp)\t\(.n)\t\(.lo)\t\(.mn)\t\(.st)\t\(.cl)"
    ' "$OUT_FILE" 2>/dev/null | while IFS=$'\t' read -r a e n lo mn st cl; do
        pl=$([ "$n" -gt 0 ] && echo "$((lo * 100 / n))%" || echo "-")
        printf '%-16s %-8s %6s %4s%-3s %7s %7s %8s\n' "$a" "$e" "$n" "$lo" " ($pl)" "$mn" "$st" "$cl"
    done
    NA=$(jq -rs '[.[]|select(.cls=="A" and .outcome=="na")]|length' "$OUT_FILE" 2>/dev/null || echo 0)
    echo ""
    echo "исключено как n/a (сброс контекста внутри интервала): $NA"
    echo ""
    echo "Плечи: treated = имя файла матчит сигнал И маркер найден по toolUseID;"
    echo "treated_unknown = имя матчит, маркера нет (хук выключен / файл короче порога);"
    echo "placebo = прочие .md, где маркер структурно невозможен."
    echo "Сливать treated_unknown с placebo нельзя — это разные причины отсутствия маркера."
    echo ""
    SUB_N=$(jq -rs '[.[]|select(.cls=="A" and .sub==true)]|length' "$OUT_FILE" 2>/dev/null || echo 0)
    SUB_OK=$(jq -rs '[.[]|select(.cls=="A" and .sub==true and .v_loose==true)]|length' "$OUT_FILE" 2>/dev/null || echo 0)
    echo "Субагентские сессии: $SUB_N интервалов, из них с перечитыванием $SUB_OK."
    echo "Это отдельная популяция (у субагента нет ни маркера, ни продолжения работы с файлом) —"
    echo "смешивать с основной нельзя; при анализе фильтровать по .sub."
    echo ""
    echo "⚠️ ОГРАНИЧЕНИЕ, известное до прогона и подтверждённое им."
    echo "Сигнал блокера срабатывает по порогу длины файла (≥300 строк). Длина файла"
    echo "независимо предсказывает и вероятность перечитать его целиком. То есть назначение"
    echo "в treated и исход имеют общую причину — сравнение treated с treated_unknown"
    echo "НЕ идентифицирует эффект маркера, оно измеряет разницу между длинными и короткими"
    echo "документами. Разность разностей здесь читать нельзя. Идентифицирующий дизайн —"
    echo "разрыв вокруг самого порога 300 строк (файлы 280-320), данных на него пока нет."

    echo ""
    echo "=== Класс B: расстояние от инжекта знаний до действия ==="
    printf '%-8s %6s %6s %6s\n' "бин" "n" "verif" "%"
    jq -rs '
      [ .[] | select(.cls=="B") ] | group_by(.exposure) | .[]
      | { e: .[0].exposure, n: length, ok: ([.[]|select(.outcome=="compliant")]|length) }
      | "\(.e)\t\(.n)\t\(.ok)\t\(if .n>0 then (.ok*1000/.n|floor|./10) else 0 end)"
    ' "$OUT_FILE" 2>/dev/null | sort | while IFS=$'\t' read -r e n ok pct; do
        printf '%-8s %6s %6s %5s%%\n' "$e" "$n" "$ok" "$pct"
    done

    echo ""
    echo "=== Класс C: негативный контроль (предупреждение о языке) ==="
    printf '%-10s %6s %10s %10s\n' "плечо" "ходов" "ср.токенов" "внутрисл."
    jq -rs '
      [ .[] | select(.cls=="C") ] | group_by(.exposure) | .[]
      | { e: .[0].exposure, n: length,
          t: ([.[].tokens_total]|add // 0), iw: ([.[].tokens_intraword]|add // 0) }
      | "\(.e)\t\(.n)\t\(if .n>0 then (.t*100/.n|floor|./100) else 0 end)\t\(.iw)"
    ' "$OUT_FILE" 2>/dev/null | while IFS=$'\t' read -r e n t iw; do
        printf '%-10s %6s %10s %10s\n' "$e" "$n" "$t" "$iw"
    done
    echo ""
    echo "p-value не считается: наблюдения кластеризованы, наивный бином завысит значимость."
}

if [ "$REPORT_ONLY" = true ]; then report; exit 0; fi

# --- Гейт: сходится ли восстановленное с тем, что писали хуки в своё время ---
if [ "$VERIFY_LOG" = true ]; then
    echo "=== Round-trip: транскрипты против blocker-fired-*.jsonl ==="
    MATCHED=0; TRANSCRIPT_ONLY=0; LOG_ONLY=0; CHECKED=0
    for log in "$STATE_DIR"/blocker-fired-*.jsonl; do
        [ -f "$log" ] || continue
        sid=$(basename "$log" .jsonl); sid="${sid#blocker-fired-}"
        tr_path=$(printf '%s\n' "$TRANSCRIPTS" | grep -F "/${sid}.jsonl" | head -1)
        # `grep -c` САМ печатает 0 и выходит с единицей, поэтому `|| echo 0` дописывал
        # второй ноль: значение выходило двухстрочным «0\n0», и арифметика ниже падала
        # с «integer expression expected». На живых данных не проявлялось — там совпадения
        # были всегда, и дефект ждал первой сессии без единого срабатывания.
        LOG_N=$({ jq -rR 'fromjson? // empty | .signal' "$log" 2>/dev/null | grep -c '.'; } || true)
        LOG_N=$(printf '%s' "${LOG_N:-0}" | tr -dc '0-9'); : "${LOG_N:=0}"
        if [ -z "$tr_path" ]; then
            LOG_ONLY=$((LOG_ONLY + LOG_N)); continue
        fi
        CHECKED=$((CHECKED + 1))
        TR_N=$({ python3 "$WORKER" "$tr_path" --events 2>/dev/null | grep -c '.'; } || true)
        TR_N=$(printf '%s' "${TR_N:-0}" | tr -dc '0-9'); : "${TR_N:=0}"
        if [ "$TR_N" -ge "$LOG_N" ]; then
            MATCHED=$((MATCHED + LOG_N)); TRANSCRIPT_ONLY=$((TRANSCRIPT_ONLY + TR_N - LOG_N))
        else
            MATCHED=$((MATCHED + TR_N)); LOG_ONLY=$((LOG_ONLY + LOG_N - TR_N))
        fi
    done
    echo "сессий с живым транскриптом: $CHECKED"
    echo "matched:          $MATCHED"
    echo "log_only:         $LOG_ONLY   (ожидаемо: транскрипты стёрты по сроку хранения)"
    echo "transcript_only:  $TRANSCRIPT_ONLY"
    if [ "$TRANSCRIPT_ONLY" -gt 0 ]; then
        echo ""
        echo "⚠️ transcript_only > 0 — парсер видит события, которых хук не писал."
        echo "   Это значит, что восстановление недостоверно. Дальше не считать."
        exit 1
    fi
    # Гейт минимальной выборки (D58). Без него «пройден» на ДВУХ сессиях звучит с той же
    # уверенностью, что на двадцати шести, — а именно столько было до 2026-08-01, когда
    # уборка throttle снесла 122 файла `blocker-fired-*` (D57). Утверждение «парсер не
    # выдумывает событий» проверяется отсутствием расхождений; при крошечной выборке
    # отсутствие расхождений не отличимо от отсутствия данных.
    #
    # Тот же приём уже применён к метрикам вмешательства в v1.12.0: процент не
    # показывается без n, а вывод не делается ниже порога выборки.
    MIN_SESSIONS="${COMPLIANCE_MIN_SESSIONS:-10}"
    if [ "$CHECKED" -lt "$MIN_SESSIONS" ]; then
        echo ""
        echo "⚠️ Расхождений нет, но выборка мала: ${CHECKED} сессий против порога ${MIN_SESSIONS}."
        echo "   Это НЕ «гейт пройден» — при такой выборке отсутствие расхождений не отличимо"
        echo "   от отсутствия данных. Вывод о достоверности парсера не делается."
        exit 2
    fi
    echo ""
    echo "✅ Гейт пройден: парсер не выдумывает событий (сессий в выборке: ${CHECKED})."
    exit 0
fi

echo "=== Backfill compliance ==="
echo "источник:   $PROJECTS_DIR"
echo "транскриптов: $COUNT"
echo "классы:     $CLASSES"
echo "выход:      $OUT_FILE"

if [ "$DRY_RUN" = true ]; then
    echo "(dry-run — ничего не записано)"
    exit 0
fi

# Бэкап предыдущего прогона: файл намеренно отдельный от живых логов, чтобы
# бэкфилл не отравлял метрики (та же дисциплина, что у backfill-intrusiveness).
if [ -s "$OUT_FILE" ]; then
    mv "$OUT_FILE" "${OUT_FILE}.bak.$(date +%s)"
fi
mkdir -p "$(dirname "$OUT_FILE")"
: > "$OUT_FILE"

T0=$(date +%s)
printf '%s\n' "$TRANSCRIPTS" | grep -v '^$' | \
    xargs -n 1 -P "$PARALLEL" -I {} python3 "$WORKER" {} --classes "$CLASSES" 2>/dev/null | \
    grep -v '^$' > "$OUT_FILE"
T1=$(date +%s)

TOTAL=$(grep -c '' "$OUT_FILE" 2>/dev/null || echo 0)
echo ""
echo "наблюдений:  $TOTAL   за $((T1 - T0))с"
for c in A B C; do
    N=$(jq -rR 'fromjson? // empty | select(.cls=="'"$c"'") | .cls' "$OUT_FILE" 2>/dev/null | grep -c '.' || echo 0)
    echo "  класс $c:  $N"
done
echo ""
echo "Дальше: bash hooks/backfill-compliance.sh --report"
