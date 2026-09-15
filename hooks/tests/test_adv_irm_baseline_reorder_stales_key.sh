#!/usr/bin/env bash
# test_adv_irm_baseline_reorder_stales_key.sh — АТАКА: ключ снимка зависит от базиса набора,
# а не только от инструмента и кандидатов.
#
# Прибор scripts/instrument-result-measured.sh обещает: «Ключ — хеш инструмента и всех его
# кандидатов: правка любого из них обесценивает строку». На деле хеши кандидатов склеиваются
# В ПОРЯДКЕ, который задаёт цена из suite-baseline.tsv. Базис перезаписывается после каждого
# полного прогона набора (hooks/tests/run_all.sh) измеренными секундами, и стоит двум
# кандидатам поменяться местами по цене — ключ меняется, `--check` отвечает «УСТАРЕЛ» при
# нетронутом дереве, а следующий замер гонит инструмент заново.
#
# Ожидание: --check даёт 0 и не печатает «УСТАРЕЛ», если ни инструмент, ни кандидаты не менялись.
# Факт: «УСТАРЕЛ», код 1 — и при перестановке цен, и при исчезновении базиса.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
FX="${TMP}/fx"; mkdir -p "${FX}/scripts" "${FX}/hooks/tests" "${TMP}/state"
export IRM_ROOT="${FX}" STATE_DIR="${TMP}/state" IRM_TIMEOUT=2

printf '#!/usr/bin/env bash\n# tool.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_tool.sh даёт 0\necho ok\n' > "${FX}/scripts/tool.sh"
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/tool.sh")\n[ "$out" = ok ] || exit 1\nexit 0\n' > "${FX}/hooks/tests/test_tool.sh"
# Два кандидата по упоминанию — зелёные, порядок между ними задаёт только цена базиса.
printf '#!/usr/bin/env bash\n# упоминает tool.sh\nexit 0\n' > "${FX}/hooks/tests/test_m1.sh"
printf '#!/usr/bin/env bash\n# тоже упоминает tool.sh\nexit 0\n' > "${FX}/hooks/tests/test_m2.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

printf '1\ttest_m1.sh\n2\ttest_m2.sh\n' > "${TMP}/base1.tsv"
printf '2\ttest_m1.sh\n1\ttest_m2.sh\n' > "${TMP}/base2.tsv"

OUT=$(SUITE_BASELINE_FILE="${TMP}/base1.tsv" bash "${IRM}" 2>&1); RC=$?
if grep -q '^измерен .*scripts/tool.sh' <<< "${OUT}" && [ "${RC}" -eq 0 ]; then ok; else bad T0 "замер с базисом 1 не измерил tool.sh: rc=${RC}: ${OUT}"; fi

# T1: цены поменялись местами, дерево нетронуто — снимок обязан остаться свежим.
OUT=$(SUITE_BASELINE_FILE="${TMP}/base2.tsv" bash "${IRM}" --check 2>&1); RC=$?
if [ "${RC}" -eq 0 ] && ! grep -q '^УСТАРЕЛ' <<< "${OUT}"; then ok; else bad T1 "перестановка цен в базисе обесценила снимок при нетронутом дереве: rc=${RC}: $(grep -E '^(УСТАРЕЛ|инструментов)' <<< "${OUT}" | tr '\n' ' ')"; fi

# T2: базис исчез (как у чистого клона или после сноса снимков состояния) — дерево то же.
OUT=$(SUITE_BASELINE_FILE="${TMP}/нет-базиса" bash "${IRM}" --check 2>&1); RC=$?
if [ "${RC}" -eq 0 ] && ! grep -q '^УСТАРЕЛ' <<< "${OUT}"; then ok; else bad T2 "отсутствие базиса обесценило снимок при нетронутом дереве: rc=${RC}: $(grep -E '^(УСТАРЕЛ|инструментов)' <<< "${OUT}" | tr '\n' ' ')"; fi

echo ""
echo "adv irm baseline-reorder: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
