#!/usr/bin/env bash
# test_adv2_irm_exit_ge128_read_as_hang.sh — АТАКА: сторож-perl отдаёт 128+сигнал, когда убил
# тест по сроку, и прибор читает ЛЮБОЙ код ≥ 128 как «завис» (`[ "${_rc}" -ge 128 ] → завис`).
# Но код ≥ 128 отдаёт и сам тест: `exit $?` после команды, снятой сигналом (141 от SIGPIPE в
# трубе под pipefail — форма, о которой контракт дерева предупреждает; 137/143 от своего
# сторожа над инструментом). Такой свидетель — настоящий, красный под заглушкой и зелёный без
# неё — пишется «завис» и отвергается: плечо без заглушки не запускается вовсе.
#
# Ожидание: красный код под заглушкой любой величины ведёт к плечу без заглушки; свидетель признан.
# Факт:      «НЕ ИЗМЕРЕН … test_tool.sh=завис», второе плечо не запущено.
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
# Свидетель по поведению: под заглушкой инструмент молчит, тест снимает себя сигналом
# (как снял бы ребёнка свой сторож) и отдаёт 128+сигнал; без заглушки — 0. Каждый запуск отмечен.
printf '#!/usr/bin/env bash\necho run >> "%s"\nout=$(bash "$(dirname "$0")/../../scripts/tool.sh")\n[ "$out" = ok ] || kill -TERM $$\nexit 0\n' "${RUNS}" > "${FX}/hooks/tests/test_tool.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT=$(bash "${IRM}" 2>&1); RC=$?
L=$(grep 'scripts/tool.sh' <<< "${OUT}" | head -1)

# T1: тест, красный под заглушкой и зелёный без неё, — свидетель, каким бы кодом он ни краснел.
case "${L}" in
    "измерен "*"← test_tool.sh"*) ok ;;
    *) bad T1 "свидетель отвергнут: «${L}»" ;;
esac
# T2: плечо без заглушки обязано запуститься (два запуска в журнале), иначе вердикт вынесен по одному плечу.
N=$(grep -c run "${RUNS}")
if [ "${N}" -ge 2 ]; then ok; else bad T2 "запусков свидетеля ${N}, второе плечо не гонялось" ; fi

echo ""
echo "adv2 irm exit>=128 read as hang: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
