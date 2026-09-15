#!/usr/bin/env bash
# test_instrument_result_measured.sh — свидетель инструмента устанавливается ПОВЕДЕНИЕМ, а не упоминанием.
#
# Результат: прибор scripts/instrument-result-measured.sh называет инструмент измеренным только тогда,
#            когда есть тест, красный на заглушке и зелёный на живом инструменте; упоминание имени,
#            тест «только код 0», сломанный тест и зависание измерением не считаются; снимок
#            обесценивается правкой инструмента либо кандидата; --check ничего не пишет.
# Проверка результата: этот тест.
#
# Предмет (D282, 12 сентября 2026). Класс «маркер совпадает с формой, не с ролью» инжектился в тот
# день четырежды без исхода; замер по дереву: 25 инструментов упомянуты ровно одним тестом, и по
# упоминанию их сочли бы измеренными. Ноги T2 и T4 — ровно те два кандидата, которых форма
# пропустила бы: тест, спрашивающий только код возврата, и тест, упоминающий имя в комментарии.
#
# Фикстура — свой git-репозиторий: универсум прибора выводится из индекса git (universe-lib), и
# дерево копируется из индекса же. Библиотеки прибор берёт рядом с СОБОЙ (настоящие), а
# инструменты и тесты — из IRM_ROOT (фикстура). Базис набора отключён (SUITE_BASELINE_FILE в
# несуществующий файл), срок свидетеля без базиса — IRM_TIMEOUT=2, чтобы нога «завис» шла две
# секунды, а не две минуты.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "${TMP}"' EXIT
FX="${TMP}/fx"; mkdir -p "${FX}/scripts" "${FX}/hooks/tests" "${TMP}/state"
export IRM_ROOT="${FX}" STATE_DIR="${TMP}/state" SUITE_BASELINE_FILE="${TMP}/нет-базиса" IRM_TIMEOUT=2
SNAP="${TMP}/state/instrument-result-measured.tsv"

hdr() { printf '#!/usr/bin/env bash\n# %s\n# Результат: печать ok\n# Проверка результата: %s даёт 0\n' "$1" "$2"; }
# good: тест сверяет ВЫВОД — красный на заглушке.
{ hdr good.sh "bash hooks/tests/test_good.sh"; echo 'echo ok'; } > "${FX}/scripts/good.sh"
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/good.sh")\n[ "$out" = ok ] || { echo "FAIL: good.sh молчит"; exit 1; }\nexit 0\n' > "${FX}/hooks/tests/test_good.sh"
# weak: тест спрашивает только код возврата — заглушка его не роняет.
{ hdr weak.sh "bash scripts/weak.sh"; echo 'echo ok'; } > "${FX}/scripts/weak.sh"
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/../../scripts/weak.sh" >/dev/null\nexit $?\n' > "${FX}/hooks/tests/test_weak.sh"
# lonely: ни одного кандидата.
{ hdr lonely.sh "bash scripts/lonely.sh"; echo 'echo ok'; } > "${FX}/scripts/lonely.sh"
# noted: имя стоит в КОММЕНТАРИИ теста, тест ничего не гоняет.
{ hdr noted.sh "bash scripts/noted.sh"; echo 'echo ok'; } > "${FX}/scripts/noted.sh"
printf '#!/usr/bin/env bash\n# здесь упомянут noted.sh, но он не вызывается\nexit 0\n' > "${FX}/hooks/tests/test_noted_mention.sh"
# envred: тест исполняет инструмент и красен всегда — не свидетель, а сломанный тест.
# Инструмент исполняется намеренно: тест, красный БЕЗ исполнения, с раунда 2 прожарки
# отсеивается раньше — как «красен, не исполнив инструмент» (след заглушки пуст).
{ hdr envred.sh "bash hooks/tests/test_envred.sh"; echo 'echo ok'; } > "${FX}/scripts/envred.sh"
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/../../scripts/envred.sh" >/dev/null\necho "FAIL: среда"; exit 1\n' > "${FX}/hooks/tests/test_envred.sh"
# tool.py: заглушка для python — с шебангом; тест сверяет вывод.
printf '#!/usr/bin/env python3\n# Результат: печать 42\n# Проверка результата: bash hooks/tests/test_tool.sh даёт 0\nprint(42)\n' > "${FX}/scripts/tool.py"
printf '#!/usr/bin/env bash\nout=$(python3 "$(dirname "$0")/../../scripts/tool.py")\n[ "$out" = 42 ] || { echo "FAIL: tool.py не 42"; exit 1; }\nexit 0\n' > "${FX}/hooks/tests/test_tool.sh"
# hang: под заглушкой тест ждёт вывода вечно — сторож снимает, зависание не вердикт.
{ hdr hang.sh "bash hooks/tests/test_hang.sh"; echo 'echo ok'; } > "${FX}/scripts/hang.sh"
printf '#!/usr/bin/env bash\nwhile [ "$(bash "$(dirname "$0")/../../scripts/hang.sh")" != ok ]; do sleep 1; done\nexit 0\n' > "${FX}/hooks/tests/test_hang.sh"
chmod +x "${FX}"/scripts/* "${FX}"/hooks/tests/*
git init -q "${FX}" && git -C "${FX}" add -A || { echo "FAIL: фикстура не стала git-репозиторием"; exit 1; }

out=$(bash "${IRM}" 2>&1); rc=$?
line() { printf '%s\n' "${out}" | grep -F -- "$1" | head -1; }

# T1: свидетель по поведению — тест, красный на заглушке и зелёный без неё.
l=$(line 'scripts/good.sh')
case "${l}" in "измерен "*"← test_good.sh"*) ok ;; *) bad T1 "good.sh не измерен: «${l}»" ;; esac

# T2: тест «только код 0» свидетелем не считается — заглушка отвечает 0.
l=$(line 'scripts/weak.sh')
case "${l}" in "НЕ ИЗМЕРЕН "*"test_weak.sh=зелёный"*) ok ;; *) bad T2 "weak.sh: «${l}»" ;; esac

# T3: кандидатов нет — названо так, а не «зелёный».
l=$(line 'scripts/lonely.sh')
case "${l}" in "НЕ ИЗМЕРЕН "*"кандидатов нет"*) ok ;; *) bad T3 "lonely.sh: «${l}»" ;; esac

# T4: упоминание имени в тесте — не свидетель (маркер формы, не роль).
l=$(line 'scripts/noted.sh')
case "${l}" in "НЕ ИЗМЕРЕН "*"test_noted_mention.sh=зелёный"*) ok ;; *) bad T4 "noted.sh: «${l}»" ;; esac

# T5: красный и без заглушки — сломанный тест, не свидетель.
l=$(line 'scripts/envred.sh')
case "${l}" in "НЕ ИЗМЕРЕН "*"test_envred.sh=красен_и_без_заглушки"*) ok ;; *) bad T5 "envred.sh: «${l}»" ;; esac

# T6: python-инструмент — заглушка с шебангом, свидетель по выводу.
l=$(line 'scripts/tool.py')
case "${l}" in "измерен "*"← test_tool.sh"*) ok ;; *) bad T6 "tool.py: «${l}»" ;; esac

# T7: зависший под заглушкой тест снят сторожем и не засчитан.
l=$(line 'scripts/hang.sh')
case "${l}" in "НЕ ИЗМЕРЕН "*"test_hang.sh=завис"*) ok ;; *) bad T7 "hang.sh: «${l}»" ;; esac

# T8: код возврата — 1 при неизмеренных, 0 когда все названные измерены.
if [ "${rc}" -eq 1 ]; then ok; else bad T8a "полный прогон фикстуры: rc=${rc}, ждали 1"; fi
bash "${IRM}" scripts/good.sh scripts/tool.py >/dev/null 2>&1; rc2=$?
if [ "${rc2}" -eq 0 ]; then ok; else bad T8b "прогон по двум измеренным: rc=${rc2}, ждали 0"; fi

# T9: снимок: повтор без правок ничего не гоняет.
out=$(bash "${IRM}" 2>&1)
case "$(line 'прогнано:')" in *"прогнано: 0;"*) ok ;; *) bad T9 "повтор гонял тесты: «$(line 'прогнано:')»" ;; esac
case "$(line 'scripts/good.sh')" in *"(из снимка)"*) ok ;; *) bad T9b "good.sh не из снимка" ;; esac

# T10: ключ обесценивается правкой инструмента И правкой кандидата.
echo '# правка' >> "${FX}/scripts/good.sh"; git -C "${FX}" add -A
out=$(bash "${IRM}" 2>&1)
case "$(line 'прогнано:')" in *"прогнано: 1;"*) ok ;; *) bad T10a "правка инструмента не обесценила снимок: «$(line 'прогнано:')»" ;; esac
echo '# правка теста' >> "${FX}/hooks/tests/test_good.sh"; git -C "${FX}" add -A
out=$(bash "${IRM}" 2>&1)
case "$(line 'прогнано:')" in *"прогнано: 1;"*) ok ;; *) bad T10b "правка кандидата не обесценила снимок: «$(line 'прогнано:')»" ;; esac

# T11: --check после правки без замера — «УСТАРЕЛ», код 1, снимок не тронут.
cp "${SNAP}" "${TMP}/snap.before"
echo '# ещё правка' >> "${FX}/scripts/good.sh"; git -C "${FX}" add -A
out=$(bash "${IRM}" --check 2>&1); rc=$?
case "$(line 'scripts/good.sh')" in "УСТАРЕЛ "*) ok ;; *) bad T11a "--check не назвал устаревшего: «$(line 'scripts/good.sh')»" ;; esac
if [ "${rc}" -eq 1 ]; then ok; else bad T11b "--check при устаревшем: rc=${rc}, ждали 1"; fi
if cmp -s "${SNAP}" "${TMP}/snap.before"; then ok; else bad T11c "--check изменил снимок"; fi

# T12: --check после замера: неизмеренные названы, устаревших нет.
bash "${IRM}" >/dev/null 2>&1
out=$(bash "${IRM}" --check 2>&1)
case "$(line 'scripts/lonely.sh')" in "НЕ ИЗМЕРЕН "*) ok ;; *) bad T12a "--check не назвал неизмеренного: «$(line 'scripts/lonely.sh')»" ;; esac
if grep -q '^УСТАРЕЛ' <<< "${out}"; then bad T12b "после замера остались устаревшие"; else ok; fi

# T13: пустой универсум (каталог без git) — отказ кодом 2, а не зелёный вердикт о нуле файлов.
mkdir -p "${TMP}/nogit/scripts"
out=$(IRM_ROOT="${TMP}/nogit" bash "${IRM}" --check 2>&1); rc=$?
if [ "${rc}" -eq 2 ]; then ok; else bad T13 "универсум пуст, а rc=${rc}: ${out}"; fi

# T14: живое дерево: --check исполним (0 или 1, не 2) и видит десятки инструментов. Только чтение.
out=$(IRM_ROOT="${ROOT}" STATE_DIR="${STATE_DIR}" bash "${IRM}" --check 2>&1); rc=$?
n=$(printf '%s\n' "${out}" | sed -n 's/^инструментов: \([0-9]*\);.*/\1/p')
if [ "${rc}" -ne 2 ] && [ "${n:-0}" -ge 40 ]; then ok; else bad T14 "живое дерево: rc=${rc}, инструментов «${n:-}»"; fi

echo ""
echo "instrument-result-measured tests: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
