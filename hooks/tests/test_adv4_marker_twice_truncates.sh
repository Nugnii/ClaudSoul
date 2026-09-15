#!/usr/bin/env bash
# test_adv4_marker_twice_truncates.sh — упоминание маркера второй раз срезает весь
# хвост целевого файла, а генератор отчитывается об успехе.
#
# scripts/regen-readme-skills.sh:70-80, awk внутри replace_section:
#     index($0, start) { ...печатает секцию...; in_section = 1; next }
#     index($0, end)   { in_section = 0; next }
#     !in_section      { print }
# Два дефекта складываются:
#   1. `index()` ищет ПОДСТРОКУ. Строка прозы, в которой маркер лишь упомянут
#      («вставьте <!-- HOOKS-TABLE:START --> и END»), считается маркером.
#   2. Состояние переключается без счётчика: после второго START ставится
#      in_section = 1, второго END в файле нет, и ВСЁ ОСТАЛЬНОЕ ДО КОНЦА ФАЙЛА
#      просто не печатается. Результат `mv` в README — молча урезанный документ.
# Ни строчки предупреждения; отчёт (208) — «README regenerated: N skills, M hooks.»,
# код возврата 0. Обратимость только через git.
#
# Проверено в этом тесте: гибнут и раздел прозы после второго упоминания, и целая
# секция SKILLS-TABLE, подставленная тем же прогоном пятью строками выше.
#
# Достижимость: любой README/справочник, который ОБЪЯСНЯЕТ собственную разметку —
# «таблица генерируется между маркерами <!-- HOOKS-TABLE:START --> и …». В текущем
# README.md и README.ru.md таких упоминаний нет (по два вхождения каждого маркера,
# все — сами маркеры), но целевой файл задаётся переменной README_FILE и меняется:
# сейчас в репозитории лежат README.draft.md и README.ru.draft.md, а пункт D78
# предполагает перенацеливание install.sh на них. Достижимость: не подтверждена на
# сегодняшнем содержимом, гарантирована для первого файла, который опишет свою разметку.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$REPO/scripts/regen-readme-skills.sh"
TMP="$(mktemp -d)"
FAKE="$TMP/repo"
mkdir -p "$FAKE/hooks" "$FAKE/skills/dummy"

printf -- '---\nname: dummy\ndescription: заглушка для генератора\n---\n' \
    > "$FAKE/skills/dummy/SKILL.md"
printf '#!/usr/bin/env bash\n# h1.sh — PreToolUse: делает нечто полезное всегда.\n' \
    > "$FAKE/hooks/h1.sh"

{
    printf '# ClaudSoul\n\n'
    printf '<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n\n'
    printf '## Как обновлять справочник\n\n'
    printf 'Таблица собирается между <!-- HOOKS-TABLE:START --> и парным END.\n\n'
    printf '## Установка\n\n'
    printf 'МАЯК-РАЗДЕЛ: этот текст обязан пережить регенерацию.\n\n'
    printf '<!-- SKILLS-TABLE:START -->\n<!-- SKILLS-TABLE:END -->\n\n'
    printf 'МАЯК-ХВОСТ: последняя строка документа.\n'
} > "$FAKE/README.md"

lines_before="$(wc -l < "$FAKE/README.md" | tr -d ' ')"
out="$(bash "$GEN" "$FAKE" 2>/dev/null)"
rc=$?
lines_after="$(wc -l < "$FAKE/README.md" | tr -d ' ')"

kept_section=no; grep -q 'МАЯК-РАЗДЕЛ' "$FAKE/README.md" && kept_section=yes
kept_tail=no;    grep -q 'МАЯК-ХВОСТ'   "$FAKE/README.md" && kept_tail=yes
kept_skills=no;  grep -q 'SKILLS-TABLE:START' "$FAKE/README.md" && kept_skills=yes

if [ "$kept_section" = yes ] && [ "$kept_tail" = yes ] && [ "$kept_skills" = yes ]; then
    echo "PASS: содержимое файла пережило регенерацию (строк $lines_before → $lines_after)"
    echo "adv4 marker twice truncates: 1/1 passed"
    exit 0
fi

echo "FAIL [regen-readme-skills.sh:68-82]: файл урезан, отчёт — об успехе."
echo "     Строк было $lines_before, стало $lines_after; код возврата $rc; отчёт: «${out}»"
echo "     Пережил раздел после второго упоминания маркера: $kept_section"
echo "     Пережил хвост документа: $kept_tail"
echo "     Пережила секция SKILLS-TABLE (подставлена этим же прогоном): $kept_skills"
echo "     Причина: index() ловит маркер как подстроку в прозе, а состояние секции"
echo "     не считает пары — после второго START печать выключается до конца файла."
echo "adv4 marker twice truncates: 0/1 passed"
exit 1
