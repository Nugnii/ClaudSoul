#!/usr/bin/env bash
# test_adv_irm_form_only_test_is_witness.sh — АТАКА: тест, читающий только ШАПКУ инструмента
# и не исполняющий его, объявляется свидетелем.
#
# Заглушка прибора scripts/instrument-result-measured.sh — две строки без шапки: вместе с
# телом исчезают «# Результат:» и «# Проверка результата:». Тест формы (как
# hooks/tests/test_instrument_contract.sh, только с именем инструмента в тексте) краснеет на
# заглушке, зеленеет на живом файле — и по критерию «красен/зелен» становится свидетелем
# ПОВЕДЕНИЯ, хотя поведения не касался. Прибор строился, чтобы отвергать маркер формы
# (T4 его теста: упоминание в комментарии — не свидетель); мутация, задевающая форму,
# возвращает тот же класс с другого входа.
#
# Ожидание: «НЕ ИЗМЕРЕН». Факт: «измерен … ← test_tool_header.sh», журнал вызовов пуст.
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

printf '#!/usr/bin/env bash\n# tool.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_tool_header.sh даёт 0\necho called >> "%s"\necho ok\n' "${CALLS}" > "${FX}/scripts/tool.sh"
# Тест формы: есть ли в шапке tool.sh строка контракта. Инструмент не исполняется.
printf '#!/usr/bin/env bash\ngrep -q "^# Результат:" "$(dirname "$0")/../../scripts/tool.sh" || { echo "FAIL: у tool.sh нет контракта"; exit 1; }\nexit 0\n' > "${FX}/hooks/tests/test_tool_header.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT=$(bash "${IRM}" 2>&1); RC=$?
L=$(grep 'scripts/tool.sh' <<< "${OUT}" | head -1)

case "${L}" in
    "НЕ ИЗМЕРЕН "*) ok ;;
    *) bad T1 "тест формы засчитан свидетелем поведения: «${L}»" ;;
esac
if [ -s "${CALLS}" ]; then bad T2 "инструмент вызывался $(wc -l < "${CALLS}") раз — атака не о том"; else ok; fi
if [ "${RC}" -eq 1 ]; then ok; else bad T3 "rc=${RC}, ждали 1"; fi

echo ""
echo "adv irm form-only witness: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
