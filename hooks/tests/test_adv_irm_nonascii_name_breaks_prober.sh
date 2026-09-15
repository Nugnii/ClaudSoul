#!/usr/bin/env bash
# test_adv_irm_nonascii_name_breaks_prober.sh — АТАКА: один инструмент с не-ASCII именем
# роняет прибор целиком — ни замера, ни снимка, ни `--check` для остальных.
#
# Универсум в scripts/instrument-result-measured.sh берётся из `git ls-files` без `-z`; при
# core.quotePath (умолчание git) не-ASCII путь приходит в кавычках с восьмеричными escape:
# "scripts/\320\277\321\200\320\276\320\261\320\260.sh". Такого файла нет, `hash_file`
# отвечает 1, `key_of` — «не посчитан ключ», и прибор выходит кодом 2 ДО записи снимка.
# Соседи с обычными именами теряют замер вместе с ним, а «Проверка» пункта D282 краснеет
# кодом «прибор сломан» при живом дереве. Тот же класс, что онемил пять стражей на не-ASCII
# имени скилла 28 августа 2026; для скиллов стоит страж имени, для scripts/ — нет.
#
# Ожидание: инструмент с кириллицей в имени замерен или честно назван; good.sh измерен,
# снимок записан, --check отвечает 0 или 1. Факт: код 2 в обоих режимах, снимка нет.
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
printf '#!/usr/bin/env bash\n# проба.sh\n# Результат: печать ok\n# Проверка результата: bash scripts/проба.sh даёт 0\necho ok\n' > "${FX}/scripts/проба.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" config core.quotePath true && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

# T1: замер — прибор не сломан, дерево законно; код 0 или 1.
OUT=$(bash "${IRM}" 2>&1); RC=$?
if [ "${RC}" -ne 2 ]; then ok; else bad T1 "замер упал кодом 2 на живом дереве: $(grep -v 'базиса' <<< "${OUT}" | tr '\n' ' ')"; fi
# T2: сосед с обычным именем измерен и попал в снимок.
if [ -f "${SNAP}" ] && grep -q '^scripts/good.sh	' "${SNAP}"; then ok; else bad T2 "снимок не записан или без good.sh: $(ls "${TMP}/state" | tr '\n' ' ')"; fi
# T3: --check исполним (0 или 1).
OUT=$(bash "${IRM}" --check 2>&1); RC=$?
if [ "${RC}" -ne 2 ]; then ok; else bad T3 "--check упал кодом 2: $(grep -v 'базиса' <<< "${OUT}" | tr '\n' ' ')"; fi

echo ""
echo "adv irm non-ascii name: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
