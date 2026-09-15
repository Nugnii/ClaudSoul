#!/usr/bin/env bash
# test_adv5_empty_table_wipe.sh — на одном и том же входе страж ОТКАЗЫВАЕТ, а генератор
# стирает таблицу и отчитывается об успехе.
#
# Вход: каталог hooks/, где после отсева `*-lib.sh` не остаётся ни одного хука.
#   страж    (test_hook_header_contract.sh:122-126) → «ОТКАЗ», exit 2.
#            Обоснование в его шапке: «Ноль проверенных файлов — ОТКАЗ, а не успех…
#            "нарушений нет" становится дословно неотличимо от "файлов не нашлось"».
#   генератор (scripts/regen-readme-skills.sh) → собирает ПУСТОЙ HOOKS_ROWS, кладёт в
#            README секцию из одной шапки таблицы, затирая все прежние строки,
#            печатает «README regenerated: N skills, 0 hooks (2/2 секций)» и выходит с 0.
#
# Генератор проверяет «ни одной ЗАМЕНЫ — отказ» (строки 227-230, поставлено после
# прошлого раунда), но не проверяет «ни одной СТРОКИ — отказ». Замена состоялась, значит
# по его мерке всё хорошо; то, что заменять было нечем, мерка не видит. Тот же принцип,
# что у стража, применён к половине предмета.
#
# Достижимость проверена: генератор берёт корень из `$1`, затем `CLAUDSOUL_REPO`, затем
# каталога скрипта (строка 24). Любой из трёх, указывающий на неполное дерево (частичный
# клон, каталог установки, оборванная выгрузка), даёт ровно этот вход. Проверок «это
# действительно ClaudSoul» нет ни одной — есть только `[ -d "$HOOKS_DIR" ]`.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_hook_header_contract.sh"
GEN="$REPO/scripts/regen-readme-skills.sh"
rc_test=0

T="$(mktemp -d)"
mkdir -p "$T/hooks" "$T/skills/dummy"
printf -- '---\nname: dummy\ndescription: заглушка для генератора.\n---\n' > "$T/skills/dummy/SKILL.md"
printf '#!/bin/bash\n# helper-lib.sh — библиотека, в витрину не идёт.\n' > "$T/hooks/helper-lib.sh"

cat > "$T/README.ru.md" <<'MDEOF'
# Справочник

<!-- HOOKS-TABLE:START -->

| Хук | Когда срабатывает и что делает |
|-----|-------------------------------|
| `error-tracker` | PreToolUse: считает провалы подряд и просит остановиться. |
| `session-collector` | Stop: напоминает про SESSION.md и незакрытые записи. |

<!-- HOOKS-TABLE:END -->
<!-- SKILLS-TABLE:START -->
<!-- SKILLS-TABLE:END -->
MDEOF

before=$(grep -c '^| `' "$T/README.ru.md")
echo "в витрине до запуска: $before строк хуков"

# --- 1. Страж на этом входе отказывает — это эталон поведения ---
guard_out="$(HOOKS_DIR="$T/hooks" bash "$GUARD" 2>&1)"; guard_rc=$?
echo "страж: rc=$guard_rc — $(printf '%s' "$guard_out" | tr '\n' ' ' | sed 's/  */ /g')"
if [ "$guard_rc" -eq 0 ]; then
    echo "SKIP: страж перестал отказывать на пустой выборке — эталон сравнения исчез"
    exit 0
fi

# --- 2. Генератор обязан вести себя так же: не отчитываться об успехе ---
gen_out="$(README_FILE="$T/README.ru.md" bash "$GEN" "$T" 2>&1)"; gen_rc=$?
after=$(grep -c '^| `error-tracker`\|^| `session-collector`' "$T/README.ru.md" || true)
echo "генератор: rc=$gen_rc — $gen_out"
echo "в витрине после запуска: $after прежних строк хуков осталось"

if [ "$gen_rc" -eq 0 ] && [ "$after" -eq 0 ]; then
    echo "FAIL [A6]: генератор стёр $before строк витрины и вышел с кодом 0."
    echo "  на этом же входе страж отвечает ОТКАЗ (rc=$guard_rc)."
    echo "  README после:"
    sed -n '/HOOKS-TABLE:START/,/HOOKS-TABLE:END/p' "$T/README.ru.md" | sed 's|^|    |'
    rc_test=1
elif [ "$after" -eq 0 ]; then
    echo "FAIL [A6]: строки витрины стёрты (генератор хотя бы отдал rc=$gen_rc)"
    rc_test=1
else
    echo "PASS [A6]: витрина не потеряла строк"
fi

echo ""
if [ "$rc_test" -ne 0 ]; then
    echo "adv5 empty-table-wipe: КРАСНЫЙ — «ноль — не успех» применено к заменам,"
    echo "  но не к строкам; страж и генератор дают противоположный вердикт на одном входе."
fi
exit "$rc_test"
