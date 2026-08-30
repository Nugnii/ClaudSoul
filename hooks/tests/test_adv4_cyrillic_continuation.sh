#!/usr/bin/env bash
# test_adv4_cyrillic_continuation.sh — признак «описание продолжено следующей строкой»
# слеп к русскому продолжению: класс [a-z] содержит только ASCII.
#
# Страж, строки 74-76:
#     case "$next" in
#         "# "[a-z]*|"# —"*|"# –"*|"# -"*) is_cont=yes ;;
#     esac
# `[a-z]` — диапазон ASCII. Строчная кириллическая буква под него не подходит НИ в
# UTF-8-локали, ни под LC_ALL=C (проверено на /bin/bash 3.2.57):
#     case "# гасит" in "# "[a-z]*) ;; esac   → не совпадает
# Значит, признак продолжения ловит только английские переносы и переносы, начатые
# с тире. Корпус хуков написан ПО-РУССКИ: типичный перенос длинной шапки начинается
# со строчной русской буквы («и держит…», «а также…», «который…»).
#
# Условие срабатывания то же, что у test_adv3_wrapped_terminator: перенос по ширине
# встал на терминатор — точку, скобку или ёлочку. Тогда строка 2 признаётся законченной
# фразой, продолжение со строки 3 не опознано, страж ЗЕЛЁНЫЙ, а генератор увозит
# в витрину половину предложения с обратным смыслом.
#
# Это дословно тот дефект, ради которого страж написан (его шапка, повод D73: «11 из 75
# обрывали фразу»). Те 11 были пойманы вручную; из них видимы стражу только английские.
#
# Достижимость: 96 хуков, описания русские, строка 2 у многих под 150 символов —
# перенос неизбежен. На сегодняшнем корпусе признак не срабатывает потому, что все
# переносы уже вычищены руками, а не потому, что страж их видит: проверено обходом
# hooks/*.sh — ни одной строки 3, начинающейся со строчной кириллицы, сейчас нет.
# Первый же новый перенос по-русски пройдёт молча.
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

HEAD="Stop: гасит проактивные предложения (по одному сигналу на сессию)"
TAIL="и снимает запрет только при следующем старте."
{
    printf '#!/usr/bin/env bash\n'
    printf '# rus-wrap.sh — %s\n' "$HEAD"
    printf '# %s\n' "$TAIL"
} > "$FAKE/hooks/rus-wrap.sh"

out="$(bash "$FAKE/hooks/tests/test_hook_header_contract.sh" 2>&1)"
guard_rc=$?
bash "$GEN" "$FAKE" >/dev/null 2>&1
row="$(grep -F '`rus-wrap`' "$FAKE/README.md" 2>/dev/null)"

if [ "$guard_rc" -ne 0 ]; then
    echo "PASS: русский перенос пойман (rc=$guard_rc): $(printf '%s' "$out" | LC_ALL=C tr '\n' ' ')"
    echo "adv4 cyrillic continuation: 1/1 passed"
    exit 0
fi

echo "FAIL [test_hook_header_contract.sh:74-76]: продолжение по-русски не опознано."
echo "     Страж: «$(printf '%s' "$out" | LC_ALL=C tr '\n' ' ')», rc=$guard_rc"
echo "     Строка 3 хука: «# ${TAIL}» — начинается со строчной «и», под [a-z] не подходит."
echo "     В витрину уехало: ${row:-<строки нет>}"
echo "     Потеряно: ${TAIL}"
echo "     Ожидалось: ненулевой код — это ровно тот обрыв фразы, ради которого"
echo "     страж написан, только на языке, на котором написан корпус."
echo "adv4 cyrillic continuation: 0/1 passed"
exit 1
