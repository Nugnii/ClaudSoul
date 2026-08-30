#!/usr/bin/env bash
# test_adv3_guard_vs_generator.sh — страж одобряет строку 2, которую генератор выбрасывает.
#
# Страж (test_hook_header_contract.sh:62-65) принимает строку 2 по образцу "# "*"—"*,
# где `*` перед тире может быть ПУСТЫМ. Генератор (scripts/regen-readme-skills.sh)
# режет `sed -E 's/^# [^—]+—[[:space:]]*//'`, где `[^—]+` требует хотя бы один символ.
# Строка «# — описание» проходит стража и выпадает у генератора: он печатает
# WARN в stderr, пропускает хук и выходит с кодом 0 — хука в витрине просто нет.
#
# Предмет стража назван в его собственной шапке: «Отсюда предмет проверки — ИСТОЧНИК,
# а не вывод генератора». Значит, годной считается та строка 2, которую генератор
# действительно берёт; здесь эти два множества расходятся.
#
# Достижимость: шапка без имени файла перед тире. Стиль ни одним стражем не закреплён,
# а обрыв молчаливый — хук пропадает из README, ошибки нет ни у стража, ни у генератора.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_hook_header_contract.sh"
GEN="$REPO/scripts/regen-readme-skills.sh"
TMP="$(mktemp -d)"
FAKE="$TMP/repo"
mkdir -p "$FAKE/hooks/tests" "$FAKE/skills"
ln -s "$GUARD" "$FAKE/hooks/tests/test_hook_header_contract.sh"

DESC="PreToolUse: делает что-то полезное и понятное."
printf '#!/usr/bin/env bash\n# — %s\n' "$DESC" > "$FAKE/hooks/dashfirst.sh"
printf '# fake\n<!-- SKILLS-TABLE:START -->\n<!-- SKILLS-TABLE:END -->\n<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n' > "$FAKE/README.md"

bash "$FAKE/hooks/tests/test_hook_header_contract.sh" >"$TMP/guard.out" 2>&1
guard_rc=$?
bash "$GEN" "$FAKE" >"$TMP/gen.out" 2>&1
row=$(grep -F '`dashfirst`' "$FAKE/README.md" || true)

if [ "$guard_rc" -ne 0 ] || [ -n "$row" ]; then
    echo "PASS: страж и генератор сошлись (guard_rc=$guard_rc, row=«${row}»)"
    echo "adv3 guard vs generator: 1/1 passed"
    exit 0
fi

echo "FAIL [test_hook_header_contract.sh:62-65]: строка 2 «# — ${DESC}» признана годной"
echo "     (guard rc=$guard_rc, вывод: «$(tr -d '\n' < "$TMP/guard.out")»),"
echo "     а генератор её выбросил: «$(grep -F WARN "$TMP/gen.out" | tr -d '\n')»."
echo "     Строки хука в README нет вовсе. Ожидалось: страж краснеет на том же входе."
echo "adv3 guard vs generator: 0/1 passed"
exit 1
