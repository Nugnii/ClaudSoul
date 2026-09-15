#!/usr/bin/env bash
# test_adv_irm_sourced_tool_false_negative.sh — АТАКА: настоящий свидетель, который берёт
# инструмент через `source`, отвергается — заглушка `exit 0` гасит сам тест кодом 0.
#
# Заглушка scripts/instrument-result-measured.sh — `exit 0`. Исполненная через `.`/`source`
# внутри теста, она завершает ПРОЦЕСС ТЕСТА с кодом 0 прежде любых утверждений. Прибор видит
# «зелёный под заглушкой» и пишет «НЕ ИЗМЕРЕН … =зелёный», хотя тот же тест краснеет на
# любом настоящем дефекте библиотеки (контроль T0 ниже). Инструмент-библиотека — законная
# форма в scripts/ (функции + запуск при прямом вызове), и её свидетель иначе как через
# source устроен быть не может.
#
# Ожидание: «измерен … ← test_lib.sh». Факт: «НЕ ИЗМЕРЕН … test_lib.sh=зелёный».
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

{
    printf '#!/usr/bin/env bash\n# lib.sh — библиотека с запуском при прямом вызове\n# Результат: lib_answer печатает 42\n# Проверка результата: bash hooks/tests/test_lib.sh даёт 0\n'
    printf 'lib_answer() { echo 42; }\n[ "${BASH_SOURCE[0]}" != "$0" ] || lib_answer\n'
} > "${FX}/scripts/lib.sh"
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/../../scripts/lib.sh"\n[ "$(lib_answer 2>/dev/null)" = 42 ] || { echo "FAIL: lib_answer не 42"; exit 1; }\nexit 0\n' > "${FX}/hooks/tests/test_lib.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

# T0 (контроль): тест — настоящий свидетель: красен на библиотеке без функции, зелен на живой.
BROKEN="${TMP}/broken"; mkdir -p "${BROKEN}/scripts" "${BROKEN}/hooks/tests"
printf '#!/usr/bin/env bash\n# lib.sh выпотрошена, но без exit\n' > "${BROKEN}/scripts/lib.sh"
cp "${FX}/hooks/tests/test_lib.sh" "${BROKEN}/hooks/tests/test_lib.sh"
( cd "${BROKEN}/hooks/tests" && bash test_lib.sh >/dev/null 2>&1 ); RB=$?
( cd "${FX}/hooks/tests" && bash test_lib.sh >/dev/null 2>&1 ); RG=$?
if [ "${RB}" -ne 0 ] && [ "${RG}" -eq 0 ]; then ok; else bad T0 "контроль: на сломанной библиотеке rc=${RB}, на живой rc=${RG}"; fi

# T1: прибор обязан признать такого свидетеля.
OUT=$(bash "${IRM}" 2>&1); RC=$?
L=$(grep 'scripts/lib.sh' <<< "${OUT}" | head -1)
case "${L}" in
    "измерен "*"← test_lib.sh"*) ok ;;
    *) bad T1 "свидетель через source отвергнут: «${L}»" ;;
esac
if [ "${RC}" -eq 0 ]; then ok; else bad T2 "rc=${RC}, ждали 0"; fi

echo ""
echo "adv irm sourced tool: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
