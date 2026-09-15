#!/usr/bin/env bash
# test_adv_irm_rename_witness_stale_name.sh — АТАКА: переименование свидетеля не обесценивает
# снимок — `--check` зелен, а в снимке стоит имя файла, которого в дереве нет.
#
# Ключ в scripts/instrument-result-measured.sh — хеш содержимого инструмента и кандидатов;
# ИМЕНА кандидатов в ключ не входят. `git mv test_good.sh test_renamed.sh` при том же
# содержимом оставляет ключ прежним: строка снимка «измерен ← test_good.sh» свежа, хотя
# test_good.sh не существует, а шапка good.sh по-прежнему называет его проверкой результата.
# Прибор обещает «снимок совпадает с деревом» — снимок называет свидетеля, которого нет.
#
# Ожидание: либо «УСТАРЕЛ» (перемерить), либо свидетель в снимке существует в дереве.
# Факт: --check даёт 0, столбец «свидетель» — несуществующий файл.
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
SNAP="${TMP}/state/instrument-result-measured.tsv"

printf '#!/usr/bin/env bash\n# good.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_good.sh даёт 0\necho ok\n' > "${FX}/scripts/good.sh"
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/good.sh")\n[ "$out" = ok ] || exit 1\nexit 0\n' > "${FX}/hooks/tests/test_good.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT=$(bash "${IRM}" 2>&1)
if grep -q '^измерен .*scripts/good.sh ← test_good.sh' <<< "${OUT}"; then ok; else bad T0 "good.sh не измерен: ${OUT}"; fi

git -C "${FX}" mv hooks/tests/test_good.sh hooks/tests/test_renamed.sh || { echo "FAIL: git mv"; exit 1; }
OUT=$(bash "${IRM}" --check 2>&1); RC=$?
WIT=$(awk -F'\t' '$1 == "scripts/good.sh" { print $4 }' "${SNAP}")

# T1: свидетель, названный свежим снимком, обязан существовать в дереве — либо снимок обязан устареть.
if [ "${RC}" -eq 0 ] && [ ! -f "${FX}/hooks/tests/${WIT}" ]; then
    bad T1 "--check зелен (rc=0), а свидетель из снимка «${WIT}» в дереве отсутствует; в hooks/tests: $(ls "${FX}/hooks/tests" | tr '\n' ' ')"
else ok; fi

echo ""
echo "adv irm rename witness: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
