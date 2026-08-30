#!/usr/bin/env bash
# test_adv4_refusal_message_crash.sh — защита от холостого прогона сама не доживает
# до вердикта: ветка ОТКАЗ падает ошибкой интерпретатора и отдаёт не тот код.
#
# Страж, строки 114-118:
#     if [ "$CHECKED_FILES" -eq 0 ]; then
#         echo "hook header contract: ОТКАЗ — не найдено ни одного хука в «$HOOKS_DIR»"  # mb-ok: строка демонстрирует дефект
#         echo "  ноль проверенных файлов не есть успех: ..."
#         exit 2
# `«$HOOKS_DIR»` — та же ловушка bash 3.2, что и на строке 98: \xc2 из `»` попадает  # mb-ok: строка демонстрирует дефект
# в имя переменной, под `set -u` это «unbound variable». Оболочка выходит ПРИ РАЗБОРЕ
# аргументов первого echo, поэтому:
#   — ни одна из двух объяснительных строк не печатается;
#   — `exit 2` не выполняется, код становится 1.
# То есть единственный механизм, отличающий «нарушений нет» от «проверка не
# запустилась», молчит ровно в тот момент, ради которого написан.
#
# Почему это не поймал раунд 3: test_adv3_vacuous_green.sh утверждает только
# `[ "$rc" -ne 0 ]`. Падение под set -u тоже даёт ненулевой код, и тест зеленеет,
# считая защиту рабочей. Проверка, сверяющая лишь знак кода возврата, не отличает
# сработавшую защиту от сломанной.
#
# Вход намеренно НЕ пустой каталог, а неполный: один *-lib.sh, который страж
# осознанно пропускает. Так выглядит частичная выкладка или прогон по каталогу,
# куда хуки ещё не скопированы.
#
# Достижимость: macOS, системный /bin/bash 3.2.57. Ветку ОТКАЗ штатно вызывает
# запуск стража со stdin (`bash < hooks/tests/test_hook_header_contract.sh`),
# через копию или симлинк — способ, названный в шапке самого стража как повод.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_hook_header_contract.sh"
TMP="$(mktemp -d)"
mkdir -p "$TMP/hooks/tests"
ln -s "$GUARD" "$TMP/hooks/tests/test_hook_header_contract.sh"
printf '#!/usr/bin/env bash\n# only-lib.sh — библиотека, страж её пропускает.\n' \
    > "$TMP/hooks/only-lib.sh"

out="$(bash "$TMP/hooks/tests/test_hook_header_contract.sh" 2>&1)"
rc=$?

said_refusal=no
case "$out" in *"ОТКАЗ"*) said_refusal=yes ;; esac
crashed=no
case "$out" in *"unbound variable"*) crashed=yes ;; esac

if [ "$said_refusal" = yes ] && [ "$crashed" = no ] && [ "$rc" -eq 2 ]; then
    echo "PASS: холостой прогон назван ОТКАЗом, код 2"
    echo "adv4 refusal message crash: 1/1 passed"
    exit 0
fi

echo "FAIL [test_hook_header_contract.sh:115]: ветка ОТКАЗ падает раньше своего вердикта."
echo "     Вывод: «$(printf '%s' "$out" | LC_ALL=C tr '\n' ' ')»"
echo "     Слово ОТКАЗ произнесено: $said_refusal; ошибка интерпретатора: $crashed"
echo "     Код возврата: $rc (в коде написан exit 2, до него не доходит)"
echo "     Ожидалось: явная жалоба «не найдено ни одного хука» и код 2."
echo "     Получено: сообщение bash об unbound variable — оператор видит поломку"
echo "     стража, а не сообщение о том, что проверка прошла вхолостую."
echo "adv4 refusal message crash: 0/1 passed"
exit 1
