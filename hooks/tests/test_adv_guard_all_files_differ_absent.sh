#!/usr/bin/env bash
# test_adv_guard_all_files_differ_absent.sh — пара, где РАЗОШЛИСЬ ВСЕ файлы, объявляется
# «установка не выполнялась» и даёт код 0.
#
# Вход: $REPO/templates/*.tmpl — три файла; $CLAUDE_HOME/templates/ — те же три имени, у
#   каждого другое содержимое (правка шаблонов в репозитории без повторного install.sh —
#   ровно то расхождение, ради которого пара 8 и заводилась).
# Ожидание: DRIFT по паре «шаблоны», код возврата 1.
# Факт: `_classify` (drift-check.sh:71-72) считает `_c_d` == `_c_n` при `_c_n > 1` признаком
#   отсутствия установки — а `_c_d` растёт и когда файла нет, и когда он ЕСТЬ, но другой.
#   Пара печатает ABSENT со «сравнено 0» и текстом «ни одного из 3 файлов в нём нет»,
#   который прямо противоречит диску: там все три. Код возврата 0.
#
# Достижимость: три и более файлов в паре — обычное дело (templates: 7 .tmpl, hooks: 83).
#   Достаточно одной правки, затрагивающей все файлы каталога (смена шапки, версии,
#   переименование маркера), — и вся пара уходит в молчание. Пары с одним файлом (n == 1)
#   защищены случайно: условие требует n > 1.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }

T="$(mktemp -d)"
P="$T/repo"; H="$T/home"
mkdir -p "$P/hooks/lib" "$P/skills/demo" "$P/templates" "$P/scripts" "$P/rules" "$P/lib" "$P/bin"
cp "$REPO/lib/claude-md-merge.sh" "$P/lib/claude-md-merge.sh" 2>/dev/null || { echo "SKIP: нет lib/claude-md-merge.sh"; exit 0; }
cp "$REPO/rules/CLAUDE.md" "$P/rules/CLAUDE.md"
printf '#!/usr/bin/env bash\ncp "$D/bin/resolve.sh" "$CLAUDE_HOME/bin/resolve.sh"\n' > "$P/install.sh"
printf 'echo resolve\n' > "$P/bin/resolve.sh"
printf 'print(0)\n' > "$P/scripts/regen-seed.py"
printf 'echo statusline\n' > "$P/scripts/statusline-claudsoul.sh"
printf 'echo hook\n' > "$P/hooks/a.sh"
printf 'echo lib\n'  > "$P/hooks/lib/b.sh"
printf '# demo\n'    > "$P/skills/demo/SKILL.md"

mkdir -p "$H/templates"
for t in CLAUDE SESSION knowledge; do
    printf 'шаблон %s — версия репозитория\n' "$t" > "$P/templates/$t.md.tmpl"
    printf 'шаблон %s — версия УСТАНОВЛЕННАЯ, другая\n' "$t" > "$H/templates/$t.md.tmpl"
done

out="$(CLAUDSOUL_REPO="$P" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1)"; rc=$?
line="$(printf '%s\n' "$out" | grep '|шаблоны|' || true)"
status="${line%%|*}"

echo "на диске в $H/templates: $(ls -1 "$H/templates" | tr '\n' ' ')"
echo "строка пары: $line"
echo "код возврата drift-check: $rc"

fail=0
if [ "$status" != "DRIFT" ]; then
    echo "ПРОВАЛ: все три файла пары различаются по содержимому, а статус «${status}», не DRIFT"
    fail=1
fi
if [ "$rc" -eq 0 ]; then
    echo "ПРОВАЛ: код возврата 0 — расхождение всей пары прочитано как «всё хорошо»"
    fail=1
fi
case "$line" in
    *"ни одного из"*)
        echo "ПРОВАЛ: подробности утверждают отсутствие файлов, которые лежат на диске"
        fail=1 ;;
esac
[ "$fail" -eq 0 ] && echo "OK: полное расхождение пары названо расхождением"
exit "$fail"
