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
    SKILL_W=$(ru_form "$skills" "скилл" "скилла" "скиллов")
    tmp=$(mktemp)
    sed -E \
        -e "s@# [0-9]+ активн(ый|ых) хук(а|ов)? \+ [0-9]+ библиотек@# ${hooks} ${HOOK_TREE} + ${libs} библиотек@" \
        -e "s@\| [0-9]+ активн(ый|ых) \+ [0-9]+ библиотек \|@| ${hooks} ${HOOK_TBL} + ${libs} библиотек |@" \
        -e "s@\| Тесты \| [0-9]+ файл(а|ов)? тестов хуков \+ [0-9]+ mcp@| Тесты | ${hook_test_files} ${TEST_W} тестов хуков + ${mcp_test_files} mcp@" \
        -e "s@# [0-9]+ файл(а|ов)? тестов хуков \+ [0-9]+ mcp@# ${hook_test_files} ${TEST_W} тестов хуков + ${mcp_test_files} mcp@" \
        -e "s@# [0-9]+ скилл(а|ов)?: @# ${skills} ${SKILL_W}: @" \
        -e "s@\| Скиллы \| [0-9]+: @| Скиллы | ${skills}: @" \
        "$MD" > "$tmp" && mv "$tmp" "$MD"
    echo "patched: $MD (hooks=${hooks}+${libs}, hook_test_files=${hook_test_files}, skills=${skills})" >&2

    # Канонные строки README (их проверяет CI-страж test_doc_counts) — тот же
    # класс ручного синка: второе проявление за день 2026-08-08 → механизм.
    #
    # Строка статистики отделена от строки версии (2026-08-21). Раньше версия и
    # производные числа жили в одной строке `**Current version:** v1.27.0 — 49 active
    # hooks`, и работа этого генератора выглядела для docs-family-check как бамп версии:
    # страж требовал обновить пять документов под релиз, которого не было. Носитель
    # двух независимых фактов путает любого, кто на него смотрит; разделение убирает
    # причину, а не очередное её следствие.
    #
    # Строка не патчится регекспами, а СОБИРАЕТСЯ целиком. Прежний вариант привязывался
    # к соседнему слову — `s@(активных хуков, )[0-9]+ скилл@` — и молча переставал
    # работать, когда склонение менялось: на 51 хуке форма стала «активный хук», и число
    # скиллов в русском README не обновлялось вовсе. Дефект дремал, потому что страж
    # ловит расхождение чисел, а расхождения не было, пока скиллов не прибавилось.
    # У собранной строки словоформ в условии нет — есть только в результате.
    RM_EN="${COUNT_STATS_README:-$ROOT/README.md}"
    RM_RU="${COUNT_STATS_README_RU:-$ROOT/README.ru.md}"
    STATS_EN="**At a glance:** ${hooks} active hooks, ${skills} skills, ${bridges} inter-layer bridges, ${domains} domain nodes — tests green."
    BRIDGE_W=$(ru_form "$bridges" "межслойный мост" "межслойных моста" "межслойных мостов")
    DOMAIN_W=$(ru_form "$domains" "домен" "домена" "доменов")
    STATS_RU="**Коротко о системе:** ${hooks} ${HOOK_TREE}, ${skills} ${SKILL_W}, ${bridges} ${BRIDGE_W}, ${domains} ${DOMAIN_W} — тесты зелёные."
    # Наличие якоря проверяет тот же awk, что и патчит, буквальным index() — без regex.
    # Первая версия спрашивала `grep -q "^**At a glance:**"`, и это молча не работало:
    # на машине стоит ugrep, для которого `^**` — синтаксическая ошибка, а не литерал.
    # Два инструмента с разным пониманием одной строки — лишняя пара, где им расходиться
    # (pattern-shell-portability). Один инструмент, одно понимание, счётчик замен вместо
    # отдельной проверки.
    patch_stats_line() {   # patch_stats_line <файл> <префикс-якорь> <новая строка>
        [ -f "$1" ] || return 0
        tmp=$(mktemp)
        _hits=$(awk -v anchor="$2" -v line="$3" '
            index($0, anchor) == 1 { print line; n++; next }
            { print }
            END { print n + 0 > "/dev/stderr" }
        ' "$1" 2>"$tmp.n" > "$tmp")
        _n=$(cat "$tmp.n" 2>/dev/null); rm -f "$tmp.n"
        case "${_n:-0}" in ''|*[!0-9]*) _n=0 ;; esac
        if [ "$_n" -eq 0 ]; then
            rm -f "$tmp"
            echo "count-stats: в $1 нет строки статистики (якорь «$2») — не тронут" >&2
            return 0
        fi
        mv "$tmp" "$1"
    }
    patch_stats_line "$RM_EN" "**At a glance:**"       "$STATS_EN"
    patch_stats_line "$RM_RU" "**Коротко о системе:**" "$STATS_RU"
    echo "patched: README canonical lines (${hooks} hooks, ${skills} skills)" >&2
fi
