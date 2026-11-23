#!/usr/bin/env bash
# test_adv_irm_perl_absent_poisons_snapshot.sh — АТАКА: без perl прибор не «сломан», а пишет
# в снимок ложные вердикты, которые потом отдаёт «из снимка».
#
# Сторож свидетеля в scripts/instrument-result-measured.sh — perl (run_test). Если perl в
# PATH нет, оболочка отвечает 127; прибор читает это как «тест красен под заглушкой», гонит
# второе плечо — снова 127 — и записывает «красен_и_без_заглушки». Код возврата 1 (есть не
# измеренные), а не 2 (прибор сломан); строка ложится в снимок и на следующем прогоне с
# perl, без --all, берётся оттуда как готовый вердикт. Среда без perl не выдумана: рецепт
# контейнера scripts/measure-linux-parity.sh ставит perl отдельно, потому что в
# debian:stable-slim его нет.
#
# Ожидание: код 2, снимок не записан. Факт: код 1, снимок с «красен_и_без_заглушки», и
# следующий прогон с perl отдаёт эту строку «(из снимка)».
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

command -v perl >/dev/null 2>&1 || { echo "SKIP: perl нет и в этой среде — нечего прятать"; exit 0; }

TMP=$(mktemp -d)
FX="${TMP}/fx"; mkdir -p "${FX}/scripts" "${FX}/hooks/tests" "${TMP}/state" "${TMP}/bin"
export IRM_ROOT="${FX}" STATE_DIR="${TMP}/state" SUITE_BASELINE_FILE="${TMP}/нет-базиса" IRM_TIMEOUT=2
SNAP="${TMP}/state/instrument-result-measured.tsv"

# PATH без perl: те же каталоги, что сейчас, но каждая утилита — ссылкой, кроме perl.
OLDIFS="${IFS}"; IFS=:
for d in ${PATH}; do
    [ -d "${d}" ] || continue
    for x in "${d}"/*; do
        [ -e "${x}" ] || continue
        n=$(basename "${x}")
        case "${n}" in perl|perl5*) continue ;; esac
        [ -e "${TMP}/bin/${n}" ] || { ln -s "${x}" "${TMP}/bin/${n}" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_irm_perl_absent_poisons_snapshot.sh:$LINENO" >&2; exit 1; }; }
    done
done
IFS="${OLDIFS}"
[ -e "${TMP}/bin/bash" ] && [ -e "${TMP}/bin/git" ] && [ -e "${TMP}/bin/tar" ] || { echo "FAIL: песочница PATH не собралась"; exit 1; }

printf '#!/usr/bin/env bash\n# good.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_good.sh даёт 0\necho ok\n' > "${FX}/scripts/good.sh"
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/good.sh")\n[ "$out" = ok ] || exit 1\nexit 0\n' > "${FX}/hooks/tests/test_good.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

# Контроль: с perl инструмент измерен — свидетель настоящий.
OUT=$(bash "${IRM}" --all 2>&1); RC=$?
if grep -q '^измерен .*scripts/good.sh' <<< "${OUT}"; then ok; else bad T0 "с perl good.sh не измерен: ${OUT}"; fi
: > "${SNAP}"

# T1: perl спрятан — прибор обязан объявить себя сломанным (2), а не мир не измеренным (1).
OUT=$(PATH="${TMP}/bin" bash "${IRM}" --all 2>&1); RC=$?
if [ "${RC}" -eq 2 ]; then ok; else bad T1 "без perl rc=${RC}, ждали 2 (прибор сломан): $(grep -E '^(НЕ ИЗМЕРЕН|измерен)' <<< "${OUT}")"; fi

# T2: снимок не должен нести вердикт, вынесенный сломанным сторожем.
if grep -q 'красен_и_без_заглушки' "${SNAP}" 2>/dev/null; then bad T2 "снимок отравлен вердиктом без perl: $(cut -f1,3,7 "${SNAP}")"; else ok; fi

# T3: следующий прогон с perl, без --all, обязан измерить, а не отдать отраву «из снимка».
OUT=$(bash "${IRM}" 2>&1)
if grep -q '^измерен .*scripts/good.sh' <<< "${OUT}"; then ok; else bad T3 "после возвращения perl вердикт взят из отравленного снимка: $(grep 'scripts/good.sh' <<< "${OUT}")"; fi

echo ""
echo "adv irm perl-absent: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
