#!/usr/bin/env bash
# test_adv_irm_order_dependent_test_is_witness.sh — АТАКА: тест, красный на первом прогоне и
# зелёный на втором, объявляется свидетелем, хотя инструмент не зовёт вовсе.
#
# Прибор scripts/instrument-result-measured.sh гонит кандидата дважды — под заглушкой и без —
# в ОДНОМ каталоге сессий (SR_SESSIONS_DIR="${W}/sessions/${t}") и без изоляции HOME. Тест,
# чьё второе исполнение отличается от первого (оставленный маркер, дроссель, «уже напоминал»),
# краснеет в первом плече и зеленеет во втором по своей причине, а прибор читает один бит —
# код возврата — и пишет «измерен». Это ровно маркер формы, а не роли, против которого прибор
# построен (T4 его собственного теста), только на другом канале.
#
# Ожидание: «НЕ ИЗМЕРЕН» — инструмент ни разу не исполнен свидетелем.
# Факт: «измерен … ← test_tool.sh», журнал вызовов инструмента пуст.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
FX="${TMP}/fx"; mkdir -p "${FX}/scripts" "${FX}/hooks/tests" "${TMP}/state"
export IRM_ROOT="${FX}" STATE_DIR="${TMP}/state" SUITE_BASELINE_FILE="${TMP}/нет-базиса" IRM_TIMEOUT=2
CALLS="${TMP}/tool-calls.log"; : > "${CALLS}"

# Инструмент пишет в журнал каждый свой вызов — по нему видно, звал ли его «свидетель».
printf '#!/usr/bin/env bash\n# tool.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_tool.sh даёт 0\necho called >> "%s"\necho ok\n' "${CALLS}" > "${FX}/scripts/tool.sh"
# Тест: первый прогон красен, второй зелен; инструмент не упоминается нигде, кроме имени файла теста.
printf '#!/usr/bin/env bash\nd="${SR_SESSIONS_DIR:-.}"; mkdir -p "$d"\n[ -f "$d/seen" ] && exit 0\ntouch "$d/seen"\nexit 1\n' > "${FX}/hooks/tests/test_tool.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT=$(bash "${IRM}" 2>&1); RC=$?
L=$(grep 'scripts/tool.sh' <<< "${OUT}" | head -1)

# T1: свидетель, ни разу не исполнивший инструмент, свидетелем быть не может.
case "${L}" in
    "НЕ ИЗМЕРЕН "*) ok ;;
    *) bad T1 "порядок-зависимый тест засчитан свидетелем: «${L}»" ;;
esac
# T2: доказательство, что инструмент не исполнялся ни в одном плече.
if [ -s "${CALLS}" ]; then bad T2 "инструмент всё же вызывался: $(wc -l < "${CALLS}") раз — атака не о том"; else ok; fi
# T3: код возврата при не измеренном инструменте — 1.
if [ "${RC}" -eq 1 ]; then ok; else bad T3 "rc=${RC}, ждали 1"; fi

echo ""
echo "adv irm order-dependent: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
