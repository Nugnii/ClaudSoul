#!/usr/bin/env bash
# test_adv3_vacuous_green.sh — страж зеленеет, когда не нашёл ни одного файла.
#
# test_hook_header_contract.sh считает только PASS и FAIL. При пустой выборке обе
# переменные нули, печатается «0/0 passed», и последняя строка `[ "$FAIL" -eq 0 ]`
# отдаёт 0. «Нарушений нет» и «файлов не нашлось» дают дословно один вердикт.
#
# Достижимость (проверено на живом репозитории, без подмен):
#   cd <repo> && bash < hooks/tests/test_hook_header_contract.sh
#   → «hook header contract: 0/0 passed», rc=0
# При чтении со stdin $0 равен «bash», dirname даёт «.», и HOOKS_DIR уезжает
# в родителя cwd. Тот же эффект даёт запуск через симлинк или копию файла —
# каталог хуков выводится из $0, а не из содержимого репозитория.
# Здесь воспроизведено симлинком: результат не зависит от соседей репозитория.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_hook_header_contract.sh"
TMP="$(mktemp -d)"
mkdir -p "$TMP/hooks/tests"
ln -s "$GUARD" "$TMP/hooks/tests/test_hook_header_contract.sh"

out=$(bash "$TMP/hooks/tests/test_hook_header_contract.sh" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
    echo "PASS: пустая выборка отвергнута (rc=$rc): $out"
    echo "adv3 vacuous green: 1/1 passed"
    exit 0
fi

echo "FAIL [test_hook_header_contract.sh:74-75]: проверка прошла ВХОЛОСТУЮ и вернула успех."
echo "     Каталог хуков пуст, проверено 0 файлов, вывод: «$(printf '%s' "$out" | tr -d '\n')», rc=$rc."
echo "     Ожидалось: ненулевой код и явная жалоба «файлов не нашлось» — иначе"
echo "     зелёный страж неотличим от отсутствующего."
echo "adv3 vacuous green: 0/1 passed"
exit 1
