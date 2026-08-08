#!/usr/bin/env bash
# ClaudSoul — единый источник истины по числам проекта.
#
# Числа в документах (README / CLAUDE.md / PLAN.md) дрейфовали, потому что
# правились вручную в нескольких местах. Этот скрипт считает их из файловой
# системы — единственный авторитетный источник. Запускать перед релизом и
# сверять статус-строки документов; CI-страж mcp-server/tests/test_doc_counts.py
# проверяет канонную строку README против этого вывода.
#
# Вывод — key=value (для парсинга) + человекочитаемая сводка в stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

hooks=$(find hooks -maxdepth 1 -name '*.sh' ! -name '*-lib.sh' | wc -l | tr -d ' ')
libs=$(find hooks -maxdepth 1 -name '*-lib.sh' | wc -l | tr -d ' ')
skills=$(find skills -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
domains=$(find domains -maxdepth 1 -name '*.md' ! -name '_*' | wc -l | tr -d ' ')
bridges=$(find bridges -maxdepth 1 -name 'L*.md' | wc -l | tr -d ' ')
hook_test_files=$(find hooks/tests -maxdepth 1 -name 'test_*.sh' | wc -l | tr -d ' ')
mcp_test_files=$(find mcp-server/tests -maxdepth 1 -name 'test_*.py' | wc -l | tr -d ' ')

cat <<OUT
hooks=$hooks
libs=$libs
skills=$skills
domains=$domains
bridges=$bridges
hook_test_files=$hook_test_files
mcp_test_files=$mcp_test_files
OUT

echo "ClaudSoul: ${hooks} хуков (+${libs} библиотек), ${skills} скиллов, ${bridges} мостов, ${domains} доменов; тест-файлов: ${hook_test_files} хук + ${mcp_test_files} mcp" >&2

# --patch-claude-md (D65): три места с числами в CLAUDE.md правит скрипт, не рука.
# Повод: 2026-08-08 три ручные синхронизации за вечер (44→46 хуков) — тот же
# класс дрейфа, что «42 хуков» в ablation-протоколе. Замена по temp+mv (без
# sed -i: BSD/GNU расходятся); словоформы считаются, чтобы не писать «82 файл».
if [ "${1:-}" = "--patch-claude-md" ]; then
    MD="${CLAUDE_MD_PATH:-$ROOT/CLAUDE.md}"
    ru_form() {
        local n=$1 m=$(( $1 % 100 )) d=$(( $1 % 10 ))
        if [ "$m" -ge 11 ] && [ "$m" -le 14 ]; then printf '%s' "$4"
        elif [ "$d" -eq 1 ]; then printf '%s' "$2"
        elif [ "$d" -ge 2 ] && [ "$d" -le 4 ]; then printf '%s' "$3"
        else printf '%s' "$4"; fi
    }
    HOOK_TREE=$(ru_form "$hooks" "активный хук" "активных хука" "активных хуков")
    HOOK_TBL=$(ru_form "$hooks" "активный" "активных" "активных")
    TEST_W=$(ru_form "$hook_test_files" "файл" "файла" "файлов")
    tmp=$(mktemp)
    sed -E \
        -e "s@# [0-9]+ активн(ый|ых) хук(а|ов)? \+ [0-9]+ библиотек@# ${hooks} ${HOOK_TREE} + ${libs} библиотек@" \
        -e "s@\| [0-9]+ активн(ый|ых) \+ [0-9]+ библиотек \|@| ${hooks} ${HOOK_TBL} + ${libs} библиотек |@" \
        -e "s@\| Тесты \| [0-9]+ файл(а|ов)? тестов хуков \+ [0-9]+ mcp@| Тесты | ${hook_test_files} ${TEST_W} тестов хуков + ${mcp_test_files} mcp@" \
        -e "s@# [0-9]+ файл(а|ов)? тестов хуков \+ [0-9]+ mcp@# ${hook_test_files} ${TEST_W} тестов хуков + ${mcp_test_files} mcp@" \
        "$MD" > "$tmp" && mv "$tmp" "$MD"
    echo "patched: $MD (hooks=${hooks}+${libs}, hook_test_files=${hook_test_files})" >&2

    # Канонные строки README (их проверяет CI-страж test_doc_counts) — тот же
    # класс ручного синка: второе проявление за день 2026-08-08 → механизм.
    RM_EN="${COUNT_STATS_README:-$ROOT/README.md}"
    RM_RU="${COUNT_STATS_README_RU:-$ROOT/README.ru.md}"
    if [ -f "$RM_EN" ]; then
        tmp=$(mktemp)
        sed -E "s@[0-9]+ active hooks@${hooks} active hooks@" "$RM_EN" > "$tmp" && mv "$tmp" "$RM_EN"
    fi
    if [ -f "$RM_RU" ]; then
        tmp=$(mktemp)
        sed -E "s@[0-9]+ активн(ый|ых) хук(а|ов)?@${hooks} ${HOOK_TREE}@" "$RM_RU" > "$tmp" && mv "$tmp" "$RM_RU"
    fi
    echo "patched: README canonical lines (${hooks} hooks)" >&2
fi
