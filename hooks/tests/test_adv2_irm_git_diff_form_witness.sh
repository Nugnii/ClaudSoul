#!/usr/bin/env bash
# test_adv2_irm_git_diff_form_witness.sh — АТАКА: тест, который инструмент не исполняет, а
# сверяет рабочее дерево с индексом (`git diff --quiet -- scripts/tool.sh`), объявляется
# свидетелем. Заглушка меняет СОДЕРЖИМОЕ файла в копии, а `.git` копии несёт индекс настоящего
# дерева: под заглушкой файл расходится с индексом — тест красен; после `cp -p orig` сходится —
# зелен. Прибор читает один бит и пишет «измерен». Сохранённая шапка (раунд 1, атака 4) здесь
# не помогает: канал не текст файла, а его хеш в индексе git — любое изменение тела различимо.
# Тот же канал у теста, сверяющего размер, md5 или mtime инструмента.
#
# Ожидание: «НЕ ИЗМЕРЕН» — инструмент ни разу не исполнен.
# Факт:      «измерен … ← test_tool.sh», журнал вызовов инструмента пуст.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
FX="${TMP}/fx"; mkdir -p "${FX}/scripts" "${FX}/hooks/tests" "${TMP}/state"
export IRM_ROOT="${FX}" STATE_DIR="${TMP}/state" SUITE_BASELINE_FILE="${TMP}/нет-базиса" IRM_TIMEOUT=5
CALLS="${TMP}/tool-calls.log"; : > "${CALLS}"

printf '#!/usr/bin/env bash\n# tool.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_tool.sh даёт 0\necho called >> "%s"\necho ok\n' "${CALLS}" > "${FX}/scripts/tool.sh"
# Тест «дерево чистое»: инструмент не зовёт, только спрашивает git, совпадает ли файл с индексом.
printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/../.." || exit 1\ngit diff --quiet -- scripts/tool.sh\nexit $?\n' > "${FX}/hooks/tests/test_tool.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT=$(bash "${IRM}" 2>&1); RC=$?
L=$(grep 'scripts/tool.sh' <<< "${OUT}" | head -1)

# T1: тест, не исполнивший инструмент, свидетелем быть не может.
case "${L}" in
    "НЕ ИЗМЕРЕН "*) ok ;;
    *) bad T1 "тест «дерево чистое» засчитан свидетелем поведения: «${L}»" ;;
esac
# T2: доказательство — инструмент не вызывался ни в одном плече.
if [ -s "${CALLS}" ]; then bad T2 "инструмент вызывался $(wc -l < "${CALLS}") раз — атака не о том"; else ok; fi
# T3: код возврата при не измеренном — 1.
if [ "${RC}" -eq 1 ]; then ok; else bad T3 "rc=${RC}, ждали 1"; fi

echo ""
echo "adv2 irm git-diff form witness: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
