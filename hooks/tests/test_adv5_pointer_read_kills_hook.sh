#!/usr/bin/env bash
# test_adv5_pointer_read_kills_hook.sh — нечитаемый файл-указатель убивает любой хук
# под `set -e` при ИСТОЧЕНИИ библиотеки, без единого слова.
#
# hooks/paths-lib.sh:47-49:
#     elif [ -f "$HOME/.claude/claudsoul-repo" ]; then
#         _cs_pointer=$(cat "$HOME/.claude/claudsoul-repo" 2>/dev/null)
# `-f` проверяет существование, но не читаемость. Если файл существует и не читается,
# `cat` возвращает 1, статус присваивания равен статусу подстановки, и под `set -e`
# оболочка выходит НА ЭТОЙ СТРОКЕ. Диагностики нет: stderr `cat` заглушён `2>/dev/null`,
# а `set -e` молчит по устройству. Хук не доходит до своего первого действия и выглядит
# для вызывающего как хук, которому нечего сказать.
#
# Шапка библиотеки заявляет обратное (строки 14-16): «Контракт: используем `:=`, поэтому
# уже заданное окружение не перезаписывается — lib лишь подставляет дефолт, когда
# переменная пуста. Источать можно многократно (идемпотентно)». Резолв дефолта не имеет
# права быть отказом: любой сбой чтения обязан сводиться к откату на следующий кандидат,
# ради чего цепочка кандидатов и построена.
#
# Область поражения — 18 хуков, объявляющих `set -e*` и источающих paths-lib, среди них
# knowledge-activator.sh, metrics-collector.sh, session-collector.sh, session-start.sh,
# intrusiveness-tracker.sh, output-language-check.sh, pre-compact-handoff.sh.
# Проверено на /bin/bash 3.2.57: `set -eo pipefail` и `set -euo pipefail` → rc=1 и пустой
# вывод; `set -uo pipefail` (без -e) → откат на дефолт отрабатывает как задумано.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/paths-lib.sh"
rc_test=0

T="$(mktemp -d)"
mkdir -p "$T/.claude" "$T/My Project/ClaudSoul" "$T/other-checkout"
printf '%s\n' "$T/other-checkout" > "$T/.claude/claudsoul-repo"
chmod 000 "$T/.claude/claudsoul-repo"

if [ -r "$T/.claude/claudsoul-repo" ]; then
    echo "SKIP: файл всё равно читается (запуск от root?) — предпосылка не воспроизведена"
    exit 0
fi
echo "предпосылка: указатель существует, но не читается ($(ls -l "$T/.claude/claudsoul-repo" | awk '{print $1}'))"

probe() {   # $1 — набор флагов
    HOME="$T" /bin/bash -c "$1"'
. "'"$LIB"'"
printf "REACHED root=%s" "$CLAUDSOUL_ROOT"' 2>&1
}

for flags in "set -eo pipefail" "set -uo pipefail"; do
    out="$(probe "$flags")"; rc=$?
    printf '  %-18s rc=%s out=[%s]\n' "$flags" "$rc" "$out"
    case "$flags" in
        "set -eo pipefail")
            if [ "$rc" -ne 0 ]; then
                echo "FAIL [A8]: под «${flags}» источение библиотеки убило оболочку (rc=$rc),"
                echo "  вывод пуст — ни отката на дефолт, ни жалобы."
                rc_test=1
            else
                echo "PASS [A8]: библиотека откатилась на следующий кандидат"
            fi ;;
    esac
done

echo ""
if [ "$rc_test" -ne 0 ]; then
    echo 'adv5 pointer-read-kills-hook: КРАСНЫЙ — существование проверяет -f,'
    echo '  а читает cat; несовпадение двух проверок превращает откат в тихий выход.'
fi
exit "$rc_test"
