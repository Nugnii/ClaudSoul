#!/usr/bin/env bash
# test_adv4_markerless_success.sh — генератор отчитывается о регенерации файла,
# которого не тронул.
#
# scripts/regen-readme-skills.sh:58-65 — если маркера в целевом файле нет, печатается
# WARN в stderr и `return 0`. Обе секции могут не примениться, а последняя строка (208)
# всё равно печатает «README regenerated: N skills, M hooks.» и скрипт выходит с 0.
# N и M — это число СОБРАННЫХ строк, а не число попавших в файл: они считаются по
# временным файлам ($SKILLS_ROWS / $HOOKS_ROWS), которые заполняются независимо от того,
# уехало ли что-нибудь в README.
#
# Единственный вызывающий гасит stdout: install.sh:181 —
#     if README_FILE="$CLAUDSOUL_DIR/README.ru.md" bash "$REGEN_SCRIPT" ... >/dev/null; then
# то есть решение об успехе шага установки принимается ПО КОДУ ВОЗВРАТА, а он нулевой.
#
# Достижимость проверена на живом репозитории, без подмен: в нём прямо сейчас лежат
# README.draft.md и README.ru.draft.md — оба без единого маркера (grep по
# 'TABLE:START' даёт ноль совпадений). Черновики — кандидаты на замену основных
# README (открытый пункт D78: «перенацелить install.sh:180 на справочники, иначе
# шаг установки станет тихим no-op»). В день, когда README_FILE укажет на файл без
# маркеров, установка отрапортует успех, а таблицы не появятся никогда.
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
# Целевой файл ровно той формы, что лежит в репозитории как README.draft.md: маркеров нет.
printf '# ClaudSoul\n\nЧерновик справочника без маркеров.\n' > "$FAKE/target.md"

before="$(cat "$FAKE/target.md")"
out="$(README_FILE="$FAKE/target.md" bash "$GEN" "$FAKE" 2>/dev/null)"
rc=$?
after="$(cat "$FAKE/target.md")"

claims_success=no
case "$out" in *"README regenerated"*) claims_success=yes ;; esac
changed=yes
[ "$before" = "$after" ] && changed=no

if [ "$rc" -ne 0 ] || [ "$claims_success" = no ]; then
    echo "PASS: отсутствие маркеров не выдано за успех (rc=$rc, отчёт: «${out}»)"
    echo "adv4 markerless success: 1/1 passed"
    exit 0
fi

echo "FAIL [regen-readme-skills.sh:58-65,208]: отчёт об успехе на нетронутом файле."
echo "     Отчёт: «${out}», код возврата $rc"
echo "     Файл изменился: $changed"
echo "     Ожидалось: ненулевой код либо отсутствие строки об успехе — числа в отчёте"
echo "     называют собранные строки, а не попавшие в файл, и вызывающий (install.sh:181)"
echo "     смотрит только на код возврата, а stdout гасит в /dev/null."
echo "adv4 markerless success: 0/1 passed"
exit 1
