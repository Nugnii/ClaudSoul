#!/usr/bin/env bash
# test_adv2_irm_substring_candidate_stales_key.sh — АТАКА: кандидат «упоминает имя инструмента»
# ищется подстрокой (`grep -l -F -- "${b}"` по basename), поэтому тест хука `activity-log.sh`
# становится кандидатом инструмента `scripts/log.sh` («log.sh» — суффикс чужого имени), входит в
# его КЛЮЧ снимка и гонится под его заглушкой. Правка чужого теста обесценивает строку
# инструмента: `--check` отвечает «УСТАРЕЛ» и кодом 1 при нетронутых инструменте и свидетеле.
# В настоящем дереве у `scripts/outcome.sh` 8 кандидатов из 14 упоминают только хуки
# `code-review-outcome.sh`, `subagent-outcome.sh`, `injection-outcome.sh`; у
# `scripts/ablation/snapshot.sh` — `test_mutation_snapshot.sh` и `test_adv_irm_perl_absent_poisons_snapshot.sh`.
#
# Ожидание: правка теста чужого механизма ключ инструмента не трогает, `--check` даёт 0.
# Факт:      «УСТАРЕЛ scripts/log.sh», `--check` даёт 1; чужой тест исполнялся под заглушкой log.sh.
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
FOREIGN_RUNS="${TMP}/foreign-runs.log"; : > "${FOREIGN_RUNS}"

# Инструмент log.sh и его настоящий свидетель test_log.sh.
printf '#!/usr/bin/env bash\n# log.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_log.sh даёт 0\necho ok\n' > "${FX}/scripts/log.sh"
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/log.sh")\n[ "$out" = ok ] || exit 1\nexit 0\n' > "${FX}/hooks/tests/test_log.sh"
# Хук activity-log.sh (не инструмент) и его тест — упоминает ТОЛЬКО имя хука.
printf '#!/usr/bin/env bash\necho hook\n' > "${FX}/hooks/activity-log.sh"
printf '#!/usr/bin/env bash\necho run >> "%s"\nout=$(bash "$(dirname "$0")/../activity-log.sh")\n[ "$out" = hook ] || exit 1\nexit 0\n' "${FOREIGN_RUNS}" > "${FX}/hooks/tests/test_activity_log.sh"
chmod +x "${FX}"/scripts/* "${FX}/hooks/activity-log.sh" "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT1=$(bash "${IRM}" 2>&1); RC1=$?
L1=$(grep 'scripts/log.sh' <<< "${OUT1}" | head -1)
case "${L1}" in "измерен "*) : ;; *) echo "FAIL: фикстура: log.sh не измерен своим свидетелем: «${L1}»"; exit 1 ;; esac

# T1: тест чужого механизма не должен исполняться под заглушкой log.sh — он не о нём.
if [ -s "${FOREIGN_RUNS}" ]; then
    bad T1 "test_activity_log.sh гонялся как кандидат log.sh: $(wc -l < "${FOREIGN_RUNS}") раз"
else
    ok
fi

# Правка ЧУЖОГО теста: инструмент и его свидетель нетронуты.
printf '# правка теста хука\n' >> "${FX}/hooks/tests/test_activity_log.sh"; git -C "${FX}" add -A
OUT2=$(bash "${IRM}" --check 2>&1); RC2=$?
L2=$(grep 'scripts/log.sh' <<< "${OUT2}" | head -1)

# T2: --check при нетронутых инструменте и свидетеле — 0, строка не «УСТАРЕЛ».
case "${L2}" in
    "УСТАРЕЛ "*) bad T2 "правка теста хука activity-log.sh обесценила снимок log.sh: «${L2}»" ;;
    *) ok ;;
esac
if [ "${RC2}" -eq 0 ]; then ok; else bad T3 "--check rc=${RC2}, ждали 0"; fi

echo ""
echo "adv2 irm substring candidate stales key: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
