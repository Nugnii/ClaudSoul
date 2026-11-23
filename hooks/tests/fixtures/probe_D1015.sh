#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# probe_D1015.sh — вид «только оболочка» не теряет местный вызов (D1015).
#
# Коды: 0 — во всех десяти командах местный вызов `timeout <число>` виден в цепочке владельца
#       `ds_unquoted_command "$(ds_shell_only …)"`; 1 — хоть в одной вид его потерял (дефект D1015:
#       ложное начало heredoc съедает хвост, кавычки парятся без состояния); 2 — библиотеки нет.
# Случаи взяты у финального скептика D1012 (20 октября 2026): прежний сырой шаблон стража каждый
# из них отбивал, вид — молча пропускал.
# Названный предел: судится одна сторона — местное не теряется. Что закавыченное и тело heredoc
# снимаются, держат ноги свидетелей детекции. Условие снятия: вторая сторона войдёт сюда, когда
# у вида появится разбор, на котором её можно судить без подгонки под эти десять строк.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || exit 2
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 2
command -v ds_shell_only >/dev/null 2>&1 && command -v ds_unquoted_command >/dev/null 2>&1 || exit 2

t=timeout   # имя собрано из переменной: команда, судимая стражем отсутствующего инструмента, — данные пробы
cases=(
    "$(printf "grep -n '<<EOF' f.sh\n%s 5 true" "$t")"
    "$(printf 'git commit -m "doc: the <<EOF form"\n%s 5 true' "$t")"
    "$(printf 'read a <<< hello\n%s 5 true' "$t")"
    "$(printf 'echo $((x<<y))\n%s 5 true' "$t")"
    "$(printf "echo \"it's\"; %s 5 true; echo 'done'" "$t")"
    "$(printf "# don't forget\n%s 5 true\necho 'ok'" "$t")"
    "$(printf 'echo "a \\" b"; %s 5 true; echo "c"' "$t")"
    "$(printf 'echo \\"; %s 5 true; echo "x"' "$t")"
    "$(printf 'cat <<-EOF\n\tbody\n\tEOF\n%s 5 true' "$t")"
    "$(printf 'cat <<END-X\nbody\nEND-X\n%s 5 true' "$t")"
)
lost=0
for c in "${cases[@]}"; do
    v=$(ds_unquoted_command "$(ds_shell_only "$c")")
    if ! grep -qE "(^|[;|&(]|&&|\|\|)[[:space:]]*$t[[:space:]]+[0-9]" <<< "$v"; then
        lost=$((lost + 1))
        echo "вид потерял местный вызов: $(printf '%s' "$c" | tr '\n' '|' | cut -c1-80)"
    fi
done
[ "$lost" -eq 0 ]
