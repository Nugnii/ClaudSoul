#!/usr/bin/env bash
# test_adv4_trap_unbound_leak.sh — уборщик по EXIT сам падает под set -u и не убирает
# ничего, подменяя настоящую причину отказа своей.
#
# scripts/regen-readme-skills.sh:89 ставит ловушку:
#     trap 'rm -f "$SKILLS_ROWS" "$SKILLS_SECTION" "$HOOKS_ROWS" "$HOOKS_SECTION"' EXIT
# HOOKS_ROWS и HOOKS_SECTION создаются только на строках 145-146. Скрипт работает под
# `set -euo pipefail` (22). Любой выход между 89 и 145 запускает ловушку, в которой
# два имени ещё не определены; bash отвергает ВСЮ команду при разборе, поэтому
# `rm -f` не выполняется НИ ДЛЯ ОДНОГО файла — утекают оба уже созданных временных.
#
# Второй эффект: последней строкой на stderr оказывается «HOOKS_ROWS: unbound variable»,
# то есть сообщение о поломке уборщика печатается ПОСЛЕ настоящей причины и читается
# как причина. Диагноз уезжает в инструмент вместо предмета.
#
# Спусковой крючок здесь — каталог целевого файла без права записи: replace_section
# (строка 81) не может создать «${README}.tmp», set -e выходит, до строки 145 дело
# не доходит. Та же ветка срабатывает на любом отказе первой половины скрипта:
# нечитаемый SKILL.md (строка 113 — awk отдаёт ненулевой код), переполненный диск,
# только-читаемая выкладка.
#
# Достижимость: генератор зовётся из install.sh:181 на каталоге, который выбирает
# устанавливающий, и вручную с произвольным README_FILE. Правами на каталог управляет
# не скрипт. Утечка молчаливая: временные файлы копятся в TMPDIR.
#
# Утечка считается через подставленный в PATH `mktemp`, который пишет журнал выданных
# путей: BSD-шный mktemp на macOS переменную TMPDIR без шаблона игнорирует, поэтому
# счёт «по каталогу» здесь ничего не доказал бы. Подмена только в PATH теста, продукт
# не тронут. Ничего не удаляется: временное уберёт система.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$REPO/scripts/regen-readme-skills.sh"
TMP="$(mktemp -d)"
FAKE="$TMP/repo"
mkdir -p "$FAKE/hooks" "$FAKE/skills/dummy" "$FAKE/readonly" "$TMP/tmpdir" "$TMP/bin"

# Учётчик временных файлов: тот же mktemp, но кладёт в свой каталог и ведёт журнал.
cat > "$TMP/bin/mktemp" <<'SHIM'
#!/bin/sh
if [ "$#" -eq 0 ]; then
    p=$(/usr/bin/mktemp "$MKTEMP_LOG_DIR/tmp.XXXXXXXX")
else
    p=$(/usr/bin/mktemp "$@")
fi
printf '%s\n' "$p" >> "$MKTEMP_LOG_DIR/.journal"
printf '%s\n' "$p"
SHIM
chmod +x "$TMP/bin/mktemp"

printf -- '---\nname: dummy\ndescription: заглушка для генератора\n---\n' \
    > "$FAKE/skills/dummy/SKILL.md"
printf '#!/usr/bin/env bash\n# h1.sh — PreToolUse: делает нечто полезное всегда.\n' \
    > "$FAKE/hooks/h1.sh"
printf '<!-- SKILLS-TABLE:START -->\n<!-- SKILLS-TABLE:END -->\n<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n' \
    > "$FAKE/readonly/README.md"
chmod 555 "$FAKE/readonly"

err="$(PATH="$TMP/bin:$PATH" MKTEMP_LOG_DIR="$TMP/tmpdir" \
        README_FILE="$FAKE/readonly/README.md" \
        bash "$GEN" "$FAKE" 2>&1 >/dev/null)"
rc=$?
chmod 755 "$FAKE/readonly"

handed_out=0; leaked=0
while IFS= read -r f; do
    handed_out=$((handed_out + 1))
    [ -e "$f" ] && leaked=$((leaked + 1))
done < "$TMP/tmpdir/.journal"
trap_broke=no
case "$err" in *"HOOKS_ROWS: unbound variable"*) trap_broke=yes ;; esac

if [ "$trap_broke" = no ] && [ "$leaked" -eq 0 ]; then
    echo "PASS: уборщик отработал, временных не осталось (rc=$rc)"
    echo "adv4 trap unbound leak: 1/1 passed"
    exit 0
fi

echo "FAIL [regen-readme-skills.sh:89]: ловушка EXIT ссылается на ещё не заданные имена."
echo "     stderr: «$(printf '%s' "$err" | LC_ALL=C tr '\n' '|')»"
echo "     Код возврата: $rc"
echo "     Ловушка упала на unbound variable: $trap_broke"
echo "     Временных выдано $handed_out, осталось на диске $leaked (ожидалось 0)"
echo "     Ожидалось: уборщик снимает свои файлы, а последним сообщением остаётся"
echo "     настоящая причина отказа, а не поломка уборщика."
echo "adv4 trap unbound leak: 0/1 passed"
exit 1
