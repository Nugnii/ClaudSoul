#!/usr/bin/env bash
# test_adv3_wrapped_terminator.sh — обрыв по ширине проходит, если попал на терминатор.
#
# Единственный признак законченности у стража — последний символ из набора
# «. ! ? ) »» (test_hook_header_contract.sh:42). Перенос по ширине встаёт где угодно,
# в том числе сразу после закрывающей ёлочки или скобки. Тогда придаточное без
# главного признаётся законченной фразой, а продолжение со строки 3 теряется молча —
# дословно тот дефект, ради которого страж и написан (см. его шапку, повод D73).
#
# Достижимость: обычный перенос длинной шапки. В корпусе 96 хуков описания уже
# содержат ёлочки и скобки; строка 2 у многих идёт под 150 символов.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_hook_header_contract.sh"
GEN="$REPO/scripts/regen-readme-skills.sh"
TMP="$(mktemp -d)"
FAKE="$TMP/repo"
mkdir -p "$FAKE/hooks/tests" "$FAKE/skills"
ln -s "$GUARD" "$FAKE/hooks/tests/test_hook_header_contract.sh"

HEAD="Stop: если в последнем ответе собеседника есть слово «стоп»"
TAIL="— гасит проактивные предложения до конца сессии."
{
    printf '#!/usr/bin/env bash\n'
    printf '# wrapped.sh — %s\n' "$HEAD"
    printf '# %s\n' "$TAIL"
} > "$FAKE/hooks/wrapped.sh"
printf '# fake\n<!-- SKILLS-TABLE:START -->\n<!-- SKILLS-TABLE:END -->\n<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n' > "$FAKE/README.md"

bash "$FAKE/hooks/tests/test_hook_header_contract.sh" >"$TMP/guard.out" 2>&1
guard_rc=$?
bash "$GEN" "$FAKE" >/dev/null 2>&1
row=$(grep -F '`wrapped`' "$FAKE/README.md" || true)

if [ "$guard_rc" -ne 0 ]; then
    echo "PASS: обрыв на терминаторе пойман (rc=$guard_rc)"
    echo "adv3 wrapped terminator: 1/1 passed"
    exit 0
fi

echo "FAIL [test_hook_header_contract.sh:41-47]: описание оборвано переносом, но признано годным."
echo "     Страж: «$(tr -d '\n' < "$TMP/guard.out")», rc=$guard_rc."
echo "     В витрину уехало: ${row}"
echo "     Потеряно продолжение со строки 3: ${TAIL}"
echo "adv3 wrapped terminator: 0/1 passed"
exit 1
