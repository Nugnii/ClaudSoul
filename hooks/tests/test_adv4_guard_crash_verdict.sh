#!/usr/bin/env bash
# test_adv4_guard_crash_verdict.sh — страж падает ошибкой интерпретатора вместо вердикта
# и бросает недосмотренными все хуки после первого нарушителя.
#
# Строка 98 стража:
#     echo "FAIL [...]: строка 2 не даёт описания — генератор её выбросит («$line2»)"  # mb-ok: строка демонстрирует дефект
# Закрывающая ёлочка `»` в UTF-8 — байты \xc2\xbb. bash 3.2 включает \xc2 в ИМЯ
# переменной: `$line2»` читается как обращение к `line2\xc2`. Под `set -u` (строка 33)  # mb-ok: строка демонстрирует дефект
# это «unbound variable», и оболочка выходит ПОСРЕДИ цикла.
#
# Ровно этот дефект описан в шапке самого стража (строки 27-31): «Имена переменных
# перед кавычкой-ёлочкой обязаны быть в фигурных скобках». На строке 57 приём применён
# (`«${trimmed}»`), на строках 98 и 115 — нет. Правило записано и не соблюдено в своём
# же файле.
#
# Последствие ровно то, ради чего страж написан: нарушители ПОСЛЕ первого не проверяются
# вовсе, а в витрину генератор их всё равно увозит — то есть страж проверил не то,
# что уехало. Здесь `z-alsobroken.sh` несёт обрыв фразы без терминатора; генератор
# ставит его в таблицу, страж о нём не говорит ни слова.
#
# Достижимость: macOS, системный /bin/bash 3.2.57 — среда, названная в задаче как
# рабочая. Вход — хук, у которого строка 2 не даёт описания: ровно то, что страж
# обязан ловить (по его шапке таких было 3 из 75 на момент написания).
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_hook_header_contract.sh"
GEN="$REPO/scripts/regen-readme-skills.sh"
TMP="$(mktemp -d)"
FAKE="$TMP/repo"
mkdir -p "$FAKE/hooks/tests" "$FAKE/skills/dummy" "$FAKE/scripts"
ln -s "$GUARD" "$FAKE/hooks/tests/test_hook_header_contract.sh"

printf -- '---\nname: dummy\ndescription: заглушка для генератора\n---\n' \
    > "$FAKE/skills/dummy/SKILL.md"
printf '# fake\n<!-- SKILLS-TABLE:START -->\n<!-- SKILLS-TABLE:END -->\n<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n' \
    > "$FAKE/README.md"

# Нарушитель №1: строка 2 не комментарий — генератор её выбрасывает с WARN.
printf '#!/usr/bin/env bash\nexit 0\n# a-broken.sh — описание уехало на строку 3.\n' \
    > "$FAKE/hooks/a-broken.sh"
# Нарушитель №2, алфавитно ПОСЛЕ первого: фраза обрывается без терминатора.
printf '#!/usr/bin/env bash\n# z-alsobroken.sh — PreToolUse: инжектит сигнал в контекст и\n' \
    > "$FAKE/hooks/z-alsobroken.sh"

out="$(bash "$FAKE/hooks/tests/test_hook_header_contract.sh" 2>&1)"
rc=$?
bash "$GEN" "$FAKE" >/dev/null 2>&1
row="$(grep -F '`z-alsobroken`' "$FAKE/README.md" 2>/dev/null)"

crashed=no
case "$out" in *"unbound variable"*) crashed=yes ;; esac
mentions_z=no
case "$out" in *z-alsobroken*) mentions_z=yes ;; esac

if [ "$crashed" = no ] && [ "$mentions_z" = yes ]; then
    echo "PASS: страж выдал вердикт по обоим нарушителям (rc=$rc)"
    echo "adv4 guard crash verdict: 1/1 passed"
    exit 0
fi

echo "FAIL [test_hook_header_contract.sh:98]: вместо вердикта — ошибка интерпретатора."
echo "     Вывод стража: «$(printf '%s' "$out" | LC_ALL=C tr '\n' ' ')», rc=$rc"
echo "     Упал на \`«\$line2»\`: bash 3.2 читает \xc2 как часть имени переменной."  # mb-ok: строка демонстрирует дефект
echo "     Второй нарушитель упомянут стражем: $mentions_z"
echo "     При этом в витрину он уехал: ${row:-<строки нет>}"
echo "     Ожидалось: две строки FAIL и ненулевой код — падение интерпретатора"
echo "     неотличимо от «проверка сломана», а хуки после первого не проверены вовсе."
echo "adv4 guard crash verdict: 0/1 passed"
exit 1
