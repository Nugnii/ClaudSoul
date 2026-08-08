#!/usr/bin/env bash
# ClaudSoul — регенерация авто-секций README.
# Секции:
#   1. <!-- SKILLS-TABLE:START --> ... <!-- SKILLS-TABLE:END -->
#      источник: skills/*/SKILL.md (frontmatter name + description | description_en)
#   2. <!-- HOOKS-TABLE:START --> ... <!-- HOOKS-TABLE:END -->
#      источник: hooks/*.sh (строка 2 после "— " | строка `# en:`); исключены *-lib.sh
#
# Запуск: bash scripts/regen-readme-skills.sh [путь_к_репо]
#   README_FILE — целевой файл (по умолчанию $REPO/README.md)
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
README="${README_FILE:-$REPO/README.md}"

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

    if ! grep -qF "$start" "$README"; then
        echo "WARN: marker '$start' not found in README.md — skipping $marker_base" >&2
        return 0
    fi
    if ! grep -qF "$end" "$README"; then
        echo "WARN: marker '$end' not found in README.md — skipping $marker_base" >&2
        return 0
    fi

    local tmp="${README}.tmp"
    awk -v start="$start" -v end="$end" -v section_file="$section_file" '
        BEGIN { in_section = 0 }
        index($0, start) {
            while ((getline line < section_file) > 0) print line
            close(section_file)
            in_section = 1
            next
        }
        index($0, end) {
            in_section = 0
            next
        }
        !in_section { print }
    ' "$README" > "$tmp"
    mv "$tmp" "$README"
}

# ---------- 1. SKILLS-TABLE ----------

SKILLS_ROWS=$(mktemp)
SKILLS_SECTION=$(mktemp)
trap 'rm -f "$SKILLS_ROWS" "$SKILLS_SECTION" "$HOOKS_ROWS" "$HOOKS_SECTION"' EXIT

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

replace_section "SKILLS-TABLE" "$SKILLS_SECTION"
SKILLS_COUNT=$(wc -l < "$SKILLS_ROWS" | tr -d ' ')

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
        desc_en=$(awk 'NR <= 8 && /^# en:[[:space:]]*/ { sub(/^# en:[[:space:]]*/, ""); print; exit }' "$hook_sh")
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

replace_section "HOOKS-TABLE" "$HOOKS_SECTION"
HOOKS_COUNT=$(wc -l < "$HOOKS_ROWS" | tr -d ' ')

# ---------- report ----------

echo "README regenerated: $SKILLS_COUNT skills, $HOOKS_COUNT hooks."
