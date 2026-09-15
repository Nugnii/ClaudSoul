#!/usr/bin/env bash
# costly-tests.sh — дорогие тесты набора: процессорное время ПООДИНОЧКЕ выше порога без оправданной цены.
# Результат: у каждого теста, чья цена поодиночке ≥ COSTLY_CPU_MAX с CPU, есть строка реестра
#            оправданной цены с измеренным числом и причиной; устаревшая строка (тест подешевел
#            или исчез) названа находкой, а не оставлена
# Проверка результата: bash scripts/costly-tests.sh даёт 0 — дорогих без оправдания нет и реестр
#            свеж; 1 — находки названы поимённо; 2 — замера поодиночке нет (не измерено)
#
# Зачем (D392). Девять тестов из 434 съедали 46% времени набора, потому что звали прибор
# целиком вместо своего предмета. Мерить это по журналу полного прогона нельзя: он идёт в
# восемь потоков, и цена в нём завышена дважды — стенные секунды соседями по ядру, процессорные
# разнородными ядрами машины (тест кэша реестра: 38 с в одиночку, 123 с CPU и 282 с стенных в
# прогоне). Предикат «дороже 20 с» на таком журнале нестабилен по построению.
#
# ДВЕ СТАДИИ. Журнал полного прогона (копия `state/suite-run-full.tsv`, четвёртая колонка CPU —
# пишет `hooks/tests/run_all.sh`; сам `suite-run.tsv` стирает каждый выборочный прогон) служит
# только ФИЛЬТРОМ кандидатов: завышение делает его надмножеством
# дорогих, а не подмножеством. Цена меряется режимом `--measure`: каждый кандидат исполняется
# поодиночке, разность `times` до запуска и после ожидания идёт в `state/suite-cost.tsv` (код,
# CPU с, стенных с, тест) с шапкой, называющей журнал-источник. Проверка (режим по умолчанию)
# судит этот файл. Вторая половина результата D392 — «записано ЧИСЛОМ, почему цена неустранима»
# — живёт строкой реестра `hooks/tests/costly-justified.tsv` (имя ⇥ цена с датой ⇥ причина).
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. 1. CPU считается по детям, которых оболочка дождалась: процесс, убитый
# сторожем до ожидания, в цену входит не весь — он виден кодом 124/137, а не ценой. 2. Спящий
# тест дёшев по CPU и дорог стенными секундами; его предмет — D340, не этот прибор. 3. Замер
# стареет с каждым полным прогоном: новый дорогой тест виден в журнале, но не в замере, пока
# `--measure` не повторён; проверка называет таких кандидатов предупреждением, а не находкой —
# иначе закрытый пункт краснел бы от каждого прогона; срок держит реестр замеров (50 коммитов).
# 4. Числа — с машины, где мерили; на другой они иные, порог тот же. 5. ГИСТЕРЕЗИС: замер
#    поодиночке шумит до ±50% между прогонами на одной машине (13 сентября 2026: 67 и 46 с у
#    одного теста, 36 и 18 у другого), поэтому строка реестра устаревает лишь при цене НИЖЕ
#    ПОЛОВИНЫ порога, а не ниже порога — иначе оправдание мигало бы от прогона к прогону.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
LOG="${SUITE_RUN_FULL_LOG:-$STATE/suite-run-full.tsv}"   # копия журнала ПОЛНОГО прогона; suite-run.tsv стирает каждый выборочный
COST="${SUITE_COST_FILE:-$STATE/suite-cost.tsv}"
REG="${COSTLY_JUSTIFIED:-$REPO/hooks/tests/costly-justified.tsv}"
MAX="${COSTLY_CPU_MAX:-20}"
TESTS_DIR="${TESTS_DIR:-$REPO/hooks/tests}"
MODE="${1:-check}"
[ -f "$REG" ] || REG=/dev/null

_cpu_of() {  # секунды user+sys детей из файла, куда `times` писала САМА оболочка (в `$(…)` счётчик нулевой)
    awk 'NR == 2 { s = 0; for (i = 1; i <= 2; i++) { split($i, a, /[ms]/); s += a[1] * 60 + a[2] } printf "%d", s }' "$1" 2>/dev/null
}

if [ "$MODE" = "--measure" ]; then
    [ -s "$LOG" ] || { echo "costly-tests: копии журнала полного прогона нет ($LOG) — сперва полный прогон набора, он её пишет"; exit 2; }
    grep -q "полнота полный" <<< "$(head -1 "$LOG")" || { echo "costly-tests: последний прогон выборочный — кандидатов не выбрать, нужен полный"; exit 2; }
    TL="${TIMEOUT_LIB:-$REPO/hooks/timeout-lib.sh}"
    [ -f "$TL" ] || { echo "costly-tests: нет $TL — мерить без сторожа нельзя"; exit 2; }
    # shellcheck source=/dev/null
    . "$TL"
    JHDR=$(head -1 "$LOG")
    CANDS=$(awk -F'\t' -v m="$MAX" '!/^#/ && NF >= 4 && $4+0 >= m { print $3 }' "$LOG")
    NC=$(printf '%s\n' "$CANDS" | grep -c . || true); case "${NC:-}" in ''|*[!0-9]*) NC=0 ;; esac
    TMPD=$(mktemp -d)
    mkdir -p "$(dirname "$COST")" 2>/dev/null
    printf '# замер поодиночке начат %s, по журналу «%s», кандидатов %s, порог %s с CPU\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$JHDR" "$NC" "$MAX" > "$COST.tmp"
    echo "costly-tests: кандидатов $NC (CPU ≥ $MAX с в журнале прогона), меряю поодиночке…"
    for t in $CANDS; do
        if [ ! -f "$TESTS_DIR/$t" ]; then printf '127\t0\t0\t%s\n' "$t" >> "$COST.tmp"; echo "  $t: файла нет"; continue; fi
        times > "$TMPD/t0"; s0=$(date +%s)
        ( cd "$TESTS_DIR" && SR_SESSIONS_DIR="$TMPD/sessions/$t" run_with_timeout "${COSTLY_MEASURE_TIMEOUT:-600}" bash "$t" >/dev/null 2>&1 ); rc=$?
        times > "$TMPD/t1"
        c0=$(_cpu_of "$TMPD/t0"); c1=$(_cpu_of "$TMPD/t1"); cpu=$(( ${c1:-0} - ${c0:-0} )); [ "$cpu" -ge 0 ] || cpu=0
        wall=$(( $(date +%s) - s0 ))
        printf '%s\t%s\t%s\t%s\n' "$rc" "$cpu" "$wall" "$t" >> "$COST.tmp"
        echo "  $t: CPU $cpu с, стенных $wall с, код $rc"
    done
    mv "$COST.tmp" "$COST"
    echo "costly-tests: замер записан в $COST"
    echo ""
fi

[ -s "$COST" ] || { echo "costly-tests: замера поодиночке нет ($COST) — bash scripts/costly-tests.sh --measure; НЕ ИЗМЕРЕНО"; exit 2; }
CHDR=$(head -1 "$COST")
FIND=0; WARN=""
if [ -s "$LOG" ] && grep -q "полнота полный" <<< "$(head -1 "$LOG")"; then
    JHDR=$(head -1 "$LOG")
    case "$CHDR" in *"$JHDR"*) ;; *) WARN="  ⚠️ замер старше журнала последнего полного прогона — перемерь: bash scripts/costly-tests.sh --measure" ;; esac
    NEWC=$(awk -F'\t' -v m="$MAX" 'NR == FNR { if ($0 !~ /^#/) seen[$4] = 1; next }
                                    !/^#/ && NF >= 4 && $4+0 >= m && !($3 in seen) { print "    " $3 " (в журнале " $4 " с CPU)" }' "$COST" "$LOG")
    [ -n "$NEWC" ] && WARN="${WARN:+$WARN
}  ⚠️ кандидаты журнала, не мерянные поодиночке (новые дорогие?):
$NEWC"
fi
UNJ=$(awk -F'\t' -v m="$MAX" 'NR == FNR { if ($0 !~ /^#/ && NF >= 3) j[$1] = 1; next }
                               !/^#/ && $2+0 >= m && !($4 in j) { printf "  %4d с CPU  %s  (стенных %s с, код %s)\n", $2, $4, $3, $1 }' \
      "$REG" "$COST" | sort -rn)
STALE=$(awk -F'\t' -v m="$MAX" '
    NR == FNR { if ($0 !~ /^#/) cpu[$4] = $2 + 0; next }
    /^#/ || NF == 0 { next }
    { name = $1; num = $2; why = $3
      if (NF < 3 || why == "" || num !~ /[0-9]+/) { printf "  %s: строка без числа или причины\n", name; next }
      if (!(name in cpu)) { printf "  %s: теста в замере поодиночке нет (подешевел ниже порога журнала либо исчез) — строку снять\n", name; next }
      if (cpu[name] < m / 2) { printf "  %s: цена упала до %d с CPU (ниже половины порога %d) — оправдание устарело, строку снять\n", name, cpu[name], m } }' \
    "$COST" "$REG")
JUST=$(awk -F'\t' -v m="$MAX" 'NR == FNR { if ($0 !~ /^#/ && NF >= 3) why[$1] = $3; next }
                                !/^#/ && $2+0 >= m && ($4 in why) { printf "  %4d с CPU  %s — %s\n", $2, $4, why[$4] }' \
      "$REG" "$COST" | sort -rn)
echo "Цена тестов поодиночке: ${CHDR#\# }; порог $MAX с CPU"
if [ -n "$JUST" ]; then echo "  дорогие с оправданной ценой (реестр $REG):"; printf '%s\n' "$JUST"; fi
if [ -n "$UNJ" ]; then FIND=1; echo "  ДОРОГИЕ БЕЗ ОПРАВДАНИЯ — сузить предмет либо добавить строку реестра с числом и причиной:"; printf '%s\n' "$UNJ"; fi
if [ -n "$STALE" ]; then FIND=1; echo "  РЕЕСТР УСТАРЕЛ:"; printf '%s\n' "$STALE"; fi
[ -n "$WARN" ] && printf '%s\n' "$WARN"
[ "$FIND" -eq 0 ] && echo "  дорогих без оправдания нет, реестр свеж"
exit "$FIND"
