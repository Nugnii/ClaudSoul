#!/usr/bin/env bash
# test_digest_self_dates_flow_form.sh — колонка «сессий» не зависит от формы записи списка.
#
# Результат: `_self_dates` из `hooks/knowledge-audit-digest.sh` даёт одно число для
#            блочной и поточной записи одного и того же `source_cases`
# Проверка результата: bash hooks/tests/test_digest_self_dates_flow_form.sh даёт 0
#
# Повод (D315). Брат корня, найденный шагом «вбок» при разборе отката D12: на строке
# `^source_cases:` awk делал `next`, поэтому СОДЕРЖИМОЕ этой строки не сканировалось
# никогда. В блочной форме там пусто и это верно; в поточной там лежит весь список.
# Замер 5 сентября 2026 по рабочей базе: поточных родителей 9, у 8 из 9 функция давала 0
# против 1-6 реальных дат. Колонка «сессий» — прокси устойчивости знания, и ноль в ней
# читается как «не подтверждалось ни разу».
#
# Функция берётся ИЗ САМОГО ХУКА, а не переписывается здесь: копия проверяла бы копию.
#
# КОНТРПРИМЕРЫ, оба проверяются ниже:
#   · блочная форма считается как прежде — правка не меняет то, что работало;
#   · дата в СОСЕДНЕМ поле за source_cases не засчитывается (границы поля соблюдены).
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/knowledge-audit-digest.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

# настоящий код функции, а не её пересказ
eval "$(sed -n '/^_self_dates() {/,/^}/p' "$HOOK")" || { echo "FAIL: не удалось извлечь _self_dates"; exit 1; }
declare -f _self_dates >/dev/null || { echo "FAIL: _self_dates не определилась"; exit 1; }

PASS=0; FAIL=0
assert_eq() {  # <получено> <ожидание> <метка>
    if [ "$1" = "$2" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: ожидалось '$2', получено '$1'"; fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- T1: блочная форма — как было ---
printf -- '---\nname: p\nsource_cases:\n  - case-2026-08-01-a.md\n  - case-2026-08-02-b.md\nstatus: active\n---\nтело\n' > "$TMP/block.md"
assert_eq "$(_self_dates "$TMP/block.md")" "2" "T1: блочная форма — две даты"

# --- T2: ГЛАВНАЯ НОГА. Поточная форма того же списка даёт то же число ---
printf -- '---\nname: p\nsource_cases: [case-2026-08-01-a.md, case-2026-08-02-b.md]\nstatus: active\n---\nтело\n' > "$TMP/flow.md"
assert_eq "$(_self_dates "$TMP/flow.md")" "2" "T2: поточная форма — те же две даты"

# --- T3: одна дата дважды считается один раз (форма не влияет на дедуп) ---
printf -- '---\nname: p\nsource_cases: [case-2026-08-01-a.md, case-2026-08-01-b.md]\nstatus: active\n---\nтело\n' > "$TMP/dup.md"
assert_eq "$(_self_dates "$TMP/dup.md")" "1" "T3: одна дата на два кейса — единица"

# --- T4: КОНТРПРИМЕР — дата соседнего поля не засчитывается ---
printf -- '---\nname: p\nsource_cases:\nlast_confirmed: 2026-09-05\nstatus: active\n---\nтело\n' > "$TMP/nb.md"
assert_eq "$(_self_dates "$TMP/nb.md")" "0" "T4: дата соседнего поля за источник не считается"

# --- T5: КОНТРПРИМЕР — тело знания за frontmatter не сканируется ---
printf -- '---\nname: p\nsource_cases: [case-2026-08-01-a.md]\nstatus: active\n---\nупоминание case-2026-01-01-z.md в прозе\n' > "$TMP/body.md"
assert_eq "$(_self_dates "$TMP/body.md")" "1" "T5: проза за frontmatter не считается"

echo "digest self_dates flow form: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
