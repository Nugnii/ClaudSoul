#!/usr/bin/env bash
# test_adv_bump_counter_comment_resets.sh — АТАКА: счётчик не инкрементируется, а ОБНУЛЯЕТСЯ
# до единицы, если в строке есть что-нибудь кроме числа.
#
# Разбор значения (строки 252-255):
#
#     v = $0; sub("^" field ":[[:space:]]*", "", v)
#     if (v ~ /^-?[0-9]+$/) { printf "%s: %d\n", field, v + 1 } else { printf "%s: 1\n", field }
#
# Запасная ветка «не число → пиши 1» задумана для отсутствующего значения, но срабатывает
# на ЛЮБОМ отклонении: хвостовой комментарий YAML (`confirmed_count: 17  # за три месяца`),
# кавычки вокруг числа, символ возврата каретки от файла с CRLF. Семнадцать подтверждений
# превращаются в одно, и восстановить их неоткуда: prevenance_log хранит только те записи,
# которые скрипт добавлял сам.
#
# Мимо этого проходят все проверки: файл остаётся валидным YAML, поле на месте, тип целый.
# Расхождение видно только сравнением с прошлым значением, а прошлого значения никто не
# хранит. `reliability = confirmed_count - contradicted_count` и `priority` (knowledge/META.md)
# считаются от этого числа, то есть тихо обесценивают знание.
#
# Достижимость: НИЗКАЯ на сегодняшней базе — в ~/.claude/global-lessons 0 файлов со строкой
# счётчика, содержащей комментарий (проверено `grep -h '^\(confirmed\|contradicted\)_count:.*#'`).
# Хвостовой комментарий YAML законен, и knowledge/META.md показывает комментарии во
# frontmatter (строка 169), но именно на строках счётчиков их сейчас нет.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

cat > "$LESSONS_DIR/pattern-probe.md" <<'KN'
---
name: проба
confidence: 5
impact: 4
confirmed_count: 17  # накопилось за три месяца
contradicted_count: 0
provenance_log: []
---
тело
KN

bash "$SCRIPT" pattern-probe confirmed "восемнадцатое подтверждение" >/dev/null 2>&1
got=$(grep '^confirmed_count:' "$LESSONS_DIR/pattern-probe.md")
echo "было: 'confirmed_count: 17  # накопилось за три месяца'"
echo "стало: '$got'"

rc=0
case "$got" in
    "confirmed_count: 18"*) ;;
    *) echo "FAIL: 17 подтверждений заменены на '$got' — данные потеряны, а не увеличены"; rc=1 ;;
esac

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: счётчик становится 18 (комментарий может быть сохранён или отброшен)."
    echo "Факт:     значение сброшено запасной веткой «не число → 1»."
    echo "adv bump counter-comment-resets: КРАСНЫЙ"
else
    echo "adv bump counter-comment-resets: 1/1 passed"
fi
exit "$rc"
