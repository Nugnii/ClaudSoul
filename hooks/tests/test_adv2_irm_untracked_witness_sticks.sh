#!/usr/bin/env bash
# test_adv2_irm_untracked_witness_sticks.sh — АТАКА: свидетель, ещё не добавленный в индекс git,
# попадает в кандидаты (прибор ищет их на ДИСКЕ: `[ -f hooks/tests/… ]`, `grep -l … hooks/tests/test_*.sh`),
# но в копии дерева его нет (копия собирается из `git ls-files`). `bash test_tool.sh` в копии
# отвечает 127 «No such file», прибор читает 127 как «красен под заглушкой», прогоняет без
# заглушки — снова 127 — и пишет в снимок вердикт «красен_и_без_заглушки»: отказ прибора
# (кандидата нет в копии) записан как вердикт о тесте, который ни разу не исполнялся.
# Ключ снимка — хеш инструмента и хеши кандидатов; `git add` теста хеша не меняет, поэтому
# после добавления свидетеля в индекс строка берётся «из снимка» и инструмент остаётся
# «НЕ ИЗМЕРЕН» без `--all`; `--check` отвечает 1.
#
# Ожидание: после `git add` свидетеля инструмент измерен, `--check` даёт 0; а до того причина
#            называет отказ прибора, а не тест.
# Факт:      «НЕ ИЗМЕРЕН … красен_и_без_заглушки (из снимка)», `--check` даёт 1, тест не запускался.
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
RUNS="${TMP}/test-runs.log"; : > "${RUNS}"

printf '#!/usr/bin/env bash\n# tool.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_tool.sh даёт 0\necho ok\n' > "${FX}/scripts/tool.sh"
# Настоящий свидетель по поведению: сверяет вывод; каждый запуск отмечает в журнале.
printf '#!/usr/bin/env bash\necho run >> "%s"\nout=$(bash "$(dirname "$0")/../../scripts/tool.sh")\n[ "$out" = ok ] || exit 1\nexit 0\n' "${RUNS}" > "${FX}/hooks/tests/test_tool.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add scripts/tool.sh || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }
# test_tool.sh НЕ добавлен в индекс — обычное состояние между «написал тест» и «git add».

OUT1=$(bash "${IRM}" 2>&1); RC1=$?
L1=$(grep 'scripts/tool.sh' <<< "${OUT1}" | head -1)

# T1: тест не исполнялся ни разу (в копии его нет) — вердикт о нём выносить не из чего:
#     причина обязана назвать отказ прибора, а не «красен_и_без_заглушки».
if [ -s "${RUNS}" ]; then
    bad T1 "свидетель всё же исполнялся ($(wc -l < "${RUNS}") раз) — атака не о том"
else
    case "${L1}" in
        *"красен_и_без_заглушки"*) bad T1 "отказ прибора (кандидата нет в копии) записан вердиктом о тесте: «${L1}»" ;;
        *) ok ;;
    esac
fi

# Свидетель добавлен в индекс. Хеш файла тот же — ключ снимка не меняется.
git -C "${FX}" add -A
OUT2=$(bash "${IRM}" 2>&1); RC2=$?
L2=$(grep 'scripts/tool.sh' <<< "${OUT2}" | head -1)

# T2: теперь свидетель в копии есть, он красен под заглушкой и зелен без неё — инструмент измерен.
case "${L2}" in
    "измерен "*"← test_tool.sh"*) ok ;;
    *) bad T2 "после git add свидетель не признан: «${L2}» (rc=${RC2})" ;;
esac
# T3: --check по дереву со свидетелем в индексе обязан дать 0.
OUT3=$(bash "${IRM}" --check 2>&1); RC3=$?
if [ "${RC3}" -eq 0 ]; then ok; else bad T3 "--check rc=${RC3}: $(grep 'scripts/tool.sh' <<< "${OUT3}" | head -1)"; fi

echo ""
echo "adv2 irm untracked witness sticks: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
