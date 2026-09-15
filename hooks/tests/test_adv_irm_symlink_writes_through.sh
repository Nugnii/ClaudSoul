#!/usr/bin/env bash
# test_adv_irm_symlink_writes_through.sh — АТАКА: инструмент-симлинк — заглушка ложится
# СКВОЗЬ ссылку в настоящий файл вне копии дерева.
#
# Копия в scripts/instrument-result-measured.sh собирается tar-ом по индексу git; симлинк
# приходит в копию симлинком. `stub()` пишет `printf … > "$1"` и `cp -p` — оба следуют
# ссылке, то есть заглушка `exit 0` ложится в файл, на который ссылка указывает, а он
# лежит ВНЕ песочницы. На время прогона свидетеля настоящий инструмент выпотрошен; всё,
# что исполняет его в это окно (другая сессия, хук, cron), получает `exit 0`; убитый между
# stub и unstub прибор оставляет его таким навсегда. Восстановление `cp -p` возвращает и
# содержимое, и mtime, поэтому снаружи после прогона следа нет — только сам свидетель,
# читавший файл под заглушкой, может это засвидетельствовать.
#
# Ожидание: файл вне копии ни в один момент не содержит заглушку.
# Факт: свидетель под заглушкой читает во внешнем файле «exit 0».
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
FX="${TMP}/fx"; EXT="${TMP}/outside"
mkdir -p "${FX}/scripts" "${FX}/hooks/tests" "${TMP}/state" "${EXT}"
export IRM_ROOT="${FX}" STATE_DIR="${TMP}/state" SUITE_BASELINE_FILE="${TMP}/нет-базиса" IRM_TIMEOUT=2

# Настоящий файл — вне фикстуры; в фикстуре — симлинк на него по абсолютному пути.
printf '#!/usr/bin/env bash\n# real.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_link.sh даёт 0\necho ok\n' > "${EXT}/real.sh"
chmod +x "${EXT}/real.sh"
ln -s "${EXT}/real.sh" "${FX}/scripts/link.sh"
# Свидетель: перед проверкой записывает, что видит во ВНЕШНЕМ файле.
printf '#!/usr/bin/env bash\ncat "%s" >> "%s"\nprintf -- "----\\n" >> "%s"\nout=$(bash "$(dirname "$0")/../../scripts/link.sh")\n[ "$out" = ok ] || exit 1\nexit 0\n' \
    "${EXT}/real.sh" "${EXT}/seen.log" "${EXT}/seen.log" > "${FX}/hooks/tests/test_link.sh"
chmod +x "${FX}/hooks/tests/test_link.sh"
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

OUT=$(bash "${IRM}" 2>&1); RC=$?

# T1: внешний файл ни в один момент прогона не должен был содержать заглушку.
if grep -q '^exit 0$' "${EXT}/seen.log" 2>/dev/null; then
    bad T1 "заглушка легла сквозь симлинк во внешний файл ${EXT}/real.sh — свидетель прочитал: $(head -2 "${EXT}/seen.log" | tr '\n' ' ')"
else ok; fi
# T2: после прогона внешний файл цел (cp -p восстанавливает — эта нога зелёная и показывает, что след снаружи стёрт).
if grep -q '^echo ok$' "${EXT}/real.sh"; then ok; else bad T2 "внешний файл не восстановлен: $(cat "${EXT}/real.sh")"; fi
# T3: вердикт «измерен» получен мутацией файла вне песочницы.
# T3 (поправлена автором после починки 12 сентября 2026): до починки «измерен» получался
# только записью сквозь ссылку, и нога читала само слово как дефект. После разыменования
# ссылок при копировании (tar -h) заглушка ложится в копию, и «измерен» законен; дефект —
# «измерен» ПРИ следе заглушки во внешнем файле, что и утверждается.
if grep -q '^измерен .*scripts/link.sh' <<< "${OUT}" && grep -q '^exit 0$' "${EXT}/seen.log" 2>/dev/null; then
    bad T3 "«измерен» вынесен ценой записи вне копии дерева: $(grep 'scripts/link.sh' <<< "${OUT}")"
else ok; fi

echo ""
echo "adv irm symlink write-through: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
