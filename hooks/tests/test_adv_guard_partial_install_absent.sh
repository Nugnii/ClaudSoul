#!/usr/bin/env bash
# test_adv_guard_partial_install_absent.sh — на установленной машине пропавший приёмник
# объявляется «не установлено» и даёт код 0.
#
# Вход: $CLAUDE_HOME, где хуки и библиотеки установлены и побайтово совпадают, а двух новых
#   приёмников нет: файла statusline-claudsoul.sh (пара 9) и каталога templates/ (пара 8).
#   Так выглядит машина, на которой install.sh отработал ДО появления этих приёмников,
#   либо с которой файл удалили.
# Ожидание: DRIFT — репозиторий несёт файл, установленное его не несёт. Код возврата 1.
# Факт: обе пары печатают ABSENT со «сравнено 0» и текстом «не установлено», код 0.
#   Статус ABSENT определён в шапке drift-check.sh как «установленной стороны нет вовсе
#   (машина без install.sh) — вопрос не стоит». Здесь машина установлена: соседние пары
#   сравнили файлы в том же прогоне. Вердикт стоит на посылке, опровергаемой соседней
#   строкой того же вывода.
# Отличить одно от другого есть чем: сумма сравнений по всем парам. drift-check её считает
#   (_checked_total, строки 48 и 55) и не использует ни разу; run_all.sh считает её заново
#   (CHECKED_FILES) — и печатает «N пар совпадают, сверено M файлов», потому что M > 0.
#
# Достижимость: пары 8 и 9 добавлены только что, а установки на машинах — прежние.
#   Ровно тот случай, для которого пара и заводилась: показывается не то состояние, в
#   котором система на самом деле.
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
printf 'шаблон\n'    > "$P/templates/CLAUDE.md.tmpl"

# установленная сторона: хуки есть и совпадают; шаблонов и статусной строки нет
mkdir -p "$H/hooks/lib" "$H/commands/demo" "$H/bin"
cp "$P/hooks/a.sh" "$H/hooks/a.sh"
cp "$P/hooks/lib/b.sh" "$H/hooks/lib/b.sh"
cp "$P/skills/demo/SKILL.md" "$H/commands/demo/SKILL.md"
cp "$P/bin/resolve.sh" "$H/bin/resolve.sh"

out="$(CLAUDSOUL_REPO="$P" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
compared_total="$(printf '%s\n' "$out" | awk -F'|' '{s += $3} END {print s + 0}')"
echo "сверено файлов всего по прогону: $compared_total (значит машина установлена)"
echo "код возврата drift-check: $rc"

fail=0
for lbl in "статусная строка" "шаблоны"; do
    line="$(printf '%s\n' "$out" | grep "|$lbl|" || true)"
    status="${line%%|*}"
    if [ "$status" = "ABSENT" ]; then
        echo "ПРОВАЛ: пара «${lbl}» — ABSENT «не установлено» на машине, где сверено $compared_total файлов"
        fail=1
    fi
done
if [ "$rc" -eq 0 ]; then
    echo "ПРОВАЛ: код возврата 0 — отсутствующие приёмники прочитаны как «всё хорошо»"
    fail=1
fi
[ "$fail" -eq 0 ] && echo "OK: пропавший приёмник на установленной машине назван расхождением"
exit "$fail"
