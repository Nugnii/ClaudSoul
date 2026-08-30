#!/usr/bin/env bash
# ClaudSoul — регенерация авто-секций справочников.
# Результат: авто-таблицы справочников (docs/reference.md, docs/reference.ru.md) совпадают с деревом
# Проверка результата: t=$(mktemp -d); cp docs/reference.md "$t/"; README_FILE="$t/reference.md" bash scripts/regen-readme-skills.sh >/dev/null && cmp -s docs/reference.md "$t/reference.md" даёт 0 (так же для docs/reference.ru.md; тот же приём — регенерация в копию и cmp — стоит в hooks/docs-family-check.sh, check_generated_tables, на коммите)
#
# Секции — маркеры живут в docs/reference.md и docs/reference.ru.md; в README их нет
# (витрины вынесены в справочники, когда оба README перевалили порог обрезания страницы):
#   1. <!-- SKILLS-TABLE:START --> ... <!-- SKILLS-TABLE:END -->
#      источник: skills/*/SKILL.md (frontmatter name + description | description_en)
#   2. <!-- HOOKS-TABLE:START --> ... <!-- HOOKS-TABLE:END -->
#      источник: hooks/*.sh (строка 2 после "— " | строка `# en:`); исключены *-lib.sh
#
# Запуск: README_FILE=<справочник> bash scripts/regen-readme-skills.sh [путь_к_репо]
#   README_FILE — целевой файл; умолчание в коде — $REPO/README.md, где маркеров нет,
#                 поэтому вызов без README_FILE кончается «marker not found» и кодом 1
#   README_LANG — ru | en (по умолчанию выводится из имени файла: *.ru.md → ru, иначе en)
#
# Два языка, v1.12.2. До этого генератор знал один набор описаний и один набор
# заголовков колонок — по-русски. Английский README из-за этого вообще не имел
# маркеров: подставлять в него русские строки было нельзя, а другого источника не
# существовало. Итог: таблица хуков там писалась руками, отстала до 14 записей из 37
# и не обновлялась ни разу. Английское описание теперь живёт РЯДОМ с артефактом
# (`# en:` в шапке хука, `description_en:` во frontmatter скилла), а не в отдельном
# словаре — иначе получилось бы два источника правды на одну сущность.
# Нет английского варианта — берётся русский, чтобы строка не пропала молча.

set -euo pipefail

REPO="${1:-${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/.." && pwd)}}"
SKILLS_DIR="$REPO/skills"
HOOKS_DIR="$REPO/hooks"
# Умолчание — docs/reference.md, где живут маркеры (в README их нет, и вызов без README_FILE
# всегда падал); без справочника — README.md, как в фикстурах тестов.
if [ -n "${README_FILE:-}" ]; then README="$README_FILE"
elif [ -f "$REPO/docs/reference.md" ]; then README="$REPO/docs/reference.md"
else README="$REPO/README.md"; fi

case "${README_LANG:-}" in
    ru|en) LANG_CODE="$README_LANG" ;;
    *) case "$README" in *.ru.md) LANG_CODE=ru ;; *) LANG_CODE=en ;; esac ;;
esac

if [ "$LANG_CODE" = "en" ]; then
    SKILLS_H1="Command"; SKILLS_H2="What it does"
    HOOKS_H1="Hook";     HOOKS_H2="When it fires and what it does"
    NO_DESC="(no description in SKILL.md)"
else
    SKILLS_H1="Команда"; SKILLS_H2="Что делает"
    HOOKS_H1="Хук";      HOOKS_H2="Когда срабатывает и что делает"
    NO_DESC="(нет описания в SKILL.md)"
fi

[ -d "$SKILLS_DIR" ] || { echo "ERROR: skills/ not found at $SKILLS_DIR" >&2; exit 1; }
[ -d "$HOOKS_DIR" ]  || { echo "ERROR: hooks/ not found at $HOOKS_DIR" >&2; exit 1; }
[ -f "$README" ]     || { echo "ERROR: README.md not found at $README" >&2; exit 1; }

# ---------- helpers ----------

# Replace section between START/END markers in README with a file's contents.
# Args: marker_base (e.g. SKILLS-TABLE), section_file
replace_section() {
    local marker_base="$1"
    local section_file="$2"
    local start="<!-- ${marker_base}:START -->"
    local end="<!-- ${marker_base}:END -->"

    # Маркером считается строка, РАВНАЯ маркеру, а не содержащая его. Поиск подстрокой
    # принимал за маркер любое упоминание в прозе («таблица собирается между <!-- X:START -->
    # и парным END»), после чего печать выключалась до конца файла: гибли все секции ниже
    # и весь хвост документа — без предупреждения и с кодом 0. Первый же справочник,
    # описывающий собственную разметку, потерял бы половину себя.
    local n_start n_end
    n_start=$(grep -cxF "$start" "$README")
    n_end=$(grep -cxF "$end" "$README")
    if [ "$n_start" -eq 0 ] || [ "$n_end" -eq 0 ]; then
        echo "WARN: marker '$marker_base' not found in $README — skipping" >&2
        return 1
    fi
    if [ "$n_start" -gt 1 ] || [ "$n_end" -gt 1 ]; then
        echo "ERROR: marker '$marker_base' встречается $n_start/$n_end раз в $README —" >&2
        echo "       пара должна быть ровно одна, иначе замена срежет текст между парами." >&2
        return 1
    fi

    local tmp="${README}.tmp"
    awk -v start="$start" -v end="$end" -v section_file="$section_file" '
        BEGIN { in_section = 0 }
        $0 == start {
            while ((getline line < section_file) > 0) print line
            close(section_file)
            in_section = 1
            next
        }
        $0 == end {
            in_section = 0
            next
        }
        !in_section { print }
    ' "$README" > "$tmp"
    mv "$tmp" "$README"
}

# ---------- 1. SKILLS-TABLE ----------

# Все четыре имени объявляются ДО trap: под `set -u` ловушка, ссылающаяся на ещё не
# созданные HOOKS_ROWS/HOOKS_SECTION, отвергается при разборе целиком — не удаляется
# ни один временный файл, а последней строкой stderr печатается «unbound variable»
# ПОСЛЕ настоящей причины отказа и читается как причина.
SKILLS_ROWS=""; SKILLS_SECTION=""; HOOKS_ROWS=""; HOOKS_SECTION=""
trap 'rm -f "$SKILLS_ROWS" "$SKILLS_SECTION" "$HOOKS_ROWS" "$HOOKS_SECTION" 2>/dev/null' EXIT
SKILLS_ROWS=$(mktemp)
SKILLS_SECTION=$(mktemp)

for skill_dir in "$SKILLS_DIR"/*/; do
    skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || continue

    fields=$(awk '
        /^---$/ { delim++; if (delim > 1) exit; next }
        delim == 1 && /^name:/ {
            sub(/^name:[[:space:]]*/, "")
            gsub(/^["\x27]/, ""); gsub(/["\x27]$/, "")
            n = $0
        }
        delim == 1 && /^description:/ {
            sub(/^description:[[:space:]]*/, "")
            gsub(/^["\x27]/, ""); gsub(/["\x27]$/, "")
            d = $0
        }
        delim == 1 && /^description_en:/ {
            sub(/^description_en:[[:space:]]*/, "")
            gsub(/^["\x27]/, ""); gsub(/["\x27]$/, "")
            e = $0
        }
        END { print n "\t" d "\t" e }
    ' "$skill_md")

    name=$(printf '%s' "$fields" | cut -f1)
    desc=$(printf '%s' "$fields" | cut -f2)
    desc_en=$(printf '%s' "$fields" | cut -f3)
    [ -z "$name" ] && continue
    # Английская колонка берёт description_en, но падает обратно на русский:
    # пропущенная строка хуже строки не на том языке — её не видно.
    [ "$LANG_CODE" = "en" ] && [ -n "$desc_en" ] && desc="$desc_en"
    [ -z "$desc" ] && desc="$NO_DESC"
    desc=${desc//|/\\|}

    printf '| `/%s` | %s |\n' "$name" "$desc" >> "$SKILLS_ROWS"
done

sort "$SKILLS_ROWS" -o "$SKILLS_ROWS"

{
    echo "<!-- SKILLS-TABLE:START -->"
    echo ""
    printf '| %s | %s |\n' "$SKILLS_H1" "$SKILLS_H2"
    echo "|---------|-----------|"
    cat "$SKILLS_ROWS"
    echo ""
    echo "<!-- SKILLS-TABLE:END -->"
} > "$SKILLS_SECTION"

REPLACED=0
SKILLS_COUNT=$(wc -l < "$SKILLS_ROWS" | tr -d ' ')
# Пустая таблица проверяется ДО замены, а не после: replace_section уже переписал бы файл,
# и ненулевой код возврата достался бы читателю вместе со стёртой витриной. Отказ, который
# наступает после разрушения, — это не отказ, а сообщение о нём.
if [ "$SKILLS_COUNT" -eq 0 ]; then
    echo "ERROR: собрано 0 строк скиллов из $SKILLS_DIR — замена стёрла бы витрину." >&2
    exit 1
fi
replace_section "SKILLS-TABLE" "$SKILLS_SECTION" && REPLACED=$((REPLACED + 1))

# ---------- 2. HOOKS-TABLE ----------

HOOKS_ROWS=$(mktemp)
HOOKS_SECTION=$(mktemp)

for hook_sh in "$HOOKS_DIR"/*.sh; do
    [ -f "$hook_sh" ] || continue
    base=$(basename "$hook_sh")

    # Skip libraries
    case "$base" in
        *-lib.sh) continue ;;
    esac

    # Extract line 2 after "— " separator
    # Line 2 format: # <name>.sh — <event>: <description>
    line2=$(awk 'NR == 2 { print }' "$hook_sh")

    # Must start with "# "
    case "$line2" in
        "# "*) ;;
        *) echo "WARN: $base: line 2 is not a comment, skipping" >&2; continue ;;
    esac

    # Extract everything after the first em-dash
    desc=$(printf '%s' "$line2" | sed -E 's/^# [^—]+—[[:space:]]*//')
    if [ -z "$desc" ] || [ "$desc" = "$line2" ]; then
        echo "WARN: $base: no '— ' separator on line 2, skipping" >&2
        continue
    fi

    # Английская строка, если есть: `# en: ...` в первых строках шапки.
    if [ "$LANG_CODE" = "en" ]; then
        # Окно — весь ведущий блок комментариев, а не первые восемь строк. Восьмёрка была
        # произвольной: `# en:` на девятой строке генератор не видел и МОЛЧА подставлял в
        # английскую таблицу русскую строку — фоллбек, задуманный для «английского нет
        # вовсе», срабатывал на «английский есть, но я до него не дочитал».
        # Ту же границу сторожит hooks/tests/test_hook_header_contract.sh: два места
        # обязаны смотреть на одно окно, иначе страж сторожит своё представление.
        desc_en=$(awk '/^#!/ { next } !/^#/ { exit } /^# en:[[:space:]]*/ { sub(/^# en:[[:space:]]*/, ""); print; exit }' "$hook_sh")
        [ -n "$desc_en" ] && desc="$desc_en"
    fi

    desc=${desc//|/\\|}
    name="${base%.sh}"
    printf '| `%s` | %s |\n' "$name" "$desc" >> "$HOOKS_ROWS"
done

sort "$HOOKS_ROWS" -o "$HOOKS_ROWS"

{
    echo "<!-- HOOKS-TABLE:START -->"
    echo ""
    printf '| %s | %s |\n' "$HOOKS_H1" "$HOOKS_H2"
    echo "|-----|-------------------------------|"
    cat "$HOOKS_ROWS"
    echo ""
    echo "<!-- HOOKS-TABLE:END -->"
} > "$HOOKS_SECTION"

HOOKS_COUNT=$(wc -l < "$HOOKS_ROWS" | tr -d ' ')
if [ "$HOOKS_COUNT" -eq 0 ]; then
    echo "ERROR: собрано 0 строк хуков из $HOOKS_DIR — замена стёрла бы витрину." >&2
    exit 1
fi
replace_section "HOOKS-TABLE" "$HOOKS_SECTION" && REPLACED=$((REPLACED + 1))

# ---------- report ----------

# Ни одной замены — отказ, а не успех. Числа ниже считаются по временным файлам строк,
# а не по попавшему в целевой файл, поэтому без этой проверки скрипт бодро отчитывался
# «README regenerated: 23 skills, 52 hooks» о файле, которого не тронул, и возвращал 0.
# install.sh гасит stdout и судит ровно по коду возврата — то есть верил отчёту.
# Три отдельных условия отказа. Каждое закрывает свой способ отчитаться об успехе,
# ничего не сделав, — а install.sh глушит stdout и судит ровно по коду возврата.
FATAL=""
# 1. Ни одной замены: маркеров нет вовсе.
[ "$REPLACED" -eq 0 ] && FATAL="в $README не заменено ни одной секции — маркеров нет либо пара неверна"
# 2. Половина секций: файл получил одну таблицу из двух, вторая осталась прежней.
#    Прежний порог стоял на нуле, и «1/2» уезжало как успех вместе с устаревшей таблицей.
[ -z "$FATAL" ] && [ "$REPLACED" -lt 2 ] && FATAL="в $README заменена $REPLACED секция из 2 — вторая осталась прежней"
# Пустые таблицы отсеяны выше, ДО замены: страж шапок на том же входе отвечает ОТКАЗом,
# и два инструмента на одном дереве обязаны давать один вердикт, иначе один из них врёт.
if [ -n "$FATAL" ]; then
    echo "ERROR: $FATAL." >&2
    exit 1
fi
echo "README regenerated: $SKILLS_COUNT skills, $HOOKS_COUNT hooks ($REPLACED/2 секций)."
