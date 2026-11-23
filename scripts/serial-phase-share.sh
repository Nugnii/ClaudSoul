#!/usr/bin/env bash
# serial-phase-share.sh — доля последовательной фазы набора: тесты, взявшие общий ресурс, и их время.
# Результат: названы доля тестов последовательной фазы и доля их времени в базисе; рост выше порога —
#            находка, а не молчание
# Проверка результата: bash scripts/serial-phase-share.sh печатает обе доли и даёт 0; 1 — доля
#            последовательных тестов выше SERIAL_SHARE_MAX (20%); 2 — раннера или базиса нет
#
# Зачем (D363, слово владельца 8 сентября 2026: «нужно описать, куда попадает новый тест и как,
# чтобы скорость не проседала и потом не оптимизировать»). Раннер делит тесты на фазы правилом
# needs_serial ИЗ ТЕКСТА теста и делает это молча: автор узнаёт о решении, только прочитав раннер,
# и очередь последовательных растёт вместе с набором. Правило описано в docs/development.md
# («Новый тест»), а этот замер — его страж: доля и время последовательной фазы названы числом и
# не растут незамеченными.
#
# ПРАВИЛО ФАЗЫ НЕ КОПИРУЕТСЯ: фазу печатает сам раннер (`run_all.sh --phases`), здесь она только
# читается (род K). Время — из базиса персональных сроков `state/suite-baseline.tsv` (пишет раннер
# после полного прогона); теста без записи в базисе время неизвестно, и он считается только в
# доле по числу.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
TESTS_DIR="${TESTS_DIR:-$REPO/hooks/tests}"
BASELINE="${SUITE_BASELINE_FILE:-${STATE_DIR:-$HOME/.claude/hooks/state}/suite-baseline.tsv}"
MAX="${SERIAL_SHARE_MAX:-20}"
[ -f "$TESTS_DIR/run_all.sh" ] || { echo "serial-phase-share: нет $TESTS_DIR/run_all.sh — не измерено"; exit 2; }
PHASES=$(cd "$TESTS_DIR" && bash run_all.sh --phases 2>/dev/null)
[ -n "$PHASES" ] || { echo "serial-phase-share: раннер не напечатал фаз (режим --phases) — не измерено"; exit 2; }
TOTAL=$(printf '%s\n' "$PHASES" | grep -c .)
SERIAL=$(printf '%s\n' "$PHASES" | awk -F'\t' '$1 == "serial"' | grep -c . || true)
case "$SERIAL" in ''|*[!0-9]*) SERIAL=0 ;; esac
SHARE=$(( SERIAL * 100 / TOTAL ))
echo "Последовательная фаза набора: тестов $SERIAL из $TOTAL ($SHARE%), порог $MAX%"
if [ -f "$BASELINE" ]; then
    read -r T_SER T_ALL N_SER <<< "$(printf '%s\n' "$PHASES" | awk -F'\t' 'NR == FNR { ph[$2] = $1; next } !/^#/ && ($2 in ph) { all += $1; if (ph[$2] == "serial") { ser += $1; n++ } } END { printf "%d %d %d", ser + 0, all + 0, n + 0 }' - "$BASELINE")"
    if [ "${T_ALL:-0}" -gt 0 ]; then
        echo "  время по базису: последовательные $T_SER с из $T_ALL с ($(( T_SER * 100 / T_ALL ))%), с записью в базисе $N_SER"
    else
        echo "  время по базису: записей нет — полный прогон ещё не писал базис"
    fi
else
    echo "  время по базису: базиса нет ($BASELINE) — считается только доля по числу"
fi
printf '%s\n' "$PHASES" | awk -F'\t' '$1 == "serial" { print "  · " $2 }' | head -${SERIAL_SHARE_LIST:-8}
[ "$SERIAL" -gt 8 ] && echo "  … всего последовательных $SERIAL (полный список: bash hooks/tests/run_all.sh --phases)"
if [ "$SHARE" -gt "$MAX" ]; then
    echo "[замер: находки, не сбой] доля последовательных выше порога — новые тесты берут общий ресурс без нужды; правило — docs/development.md, «Новый тест»"
    exit 1
fi
exit 0
