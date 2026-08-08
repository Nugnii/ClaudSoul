#!/usr/bin/env bash
# knowledge-counter-bump.sh — механический инкремент счётчиков знания.
# en: mechanical increment of a knowledge item's confirmed/contradicted counters.
#
# Зачем механизм, а не инструкция в скилле. `contradicted_count` равен нулю во всех
# 265 знаниях базы при 156 знаниях с подтверждениями. Причина не в том, что нечего
# опровергать: /learn текстом запрещал трогать знание при противоречии, а /retro
# писал соседнее поле, которое тоже осталось нулевым. Текстовое правило уже один раз
# не исполнилось — второй раз надеяться не на что (principle-knowledge-in-the-world:
# уровень 1 «правило в тексте» хрупок, уровень 3 «механизм» неотвратим).
#
# Usage:
#   knowledge-counter-bump.sh <knowledge> confirmed   [reason] [trigger_case]
#   knowledge-counter-bump.sh <knowledge> contradicted [reason] [trigger_case]
#   knowledge-counter-bump.sh <knowledge> --show
#
#   <knowledge> — имя файла с .md или без (pattern-foo | pattern-foo.md), либо путь.
#
# Что делает:
#   confirmed   → confirmed_count++,   last_confirmed = сегодня, modification_history += reinforced
#   contradicted → contradicted_count++, modification_history += contradicted
#
# Идемпотентности НЕТ намеренно: каждый вызов — отдельная встреча знания с решением.
# Дедуп «один раз за сессию» делает producer (knowledge-activator), а не этот скрипт.
#
# Exit: 0 — записано; 1 — знание не найдено / плохие аргументы.

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; fi

usage() {
    echo "usage: $(basename "$0") <knowledge> confirmed|contradicted [reason] [trigger_case]" >&2
    echo "       $(basename "$0") <knowledge> --show" >&2
    exit 1
}

[ $# -ge 2 ] || usage
KN="$1"; ACTION="$2"; REASON="${3:-}"; TRIGGER_CASE="${4:-}"

# --- Разрешение имени в путь ---
case "$KN" in
    */*) FILE="$KN" ;;
    *.md) FILE="$LESSONS_DIR/$KN" ;;
    *)   FILE="$LESSONS_DIR/$KN.md" ;;
esac
if [ ! -f "$FILE" ]; then
    echo "knowledge-counter-bump: не найдено знание '$KN' (искал $FILE)" >&2
    exit 1
fi

show_counters() {
    awk '
        /^---$/ { d++; if (d >= 2) exit; next }
        d == 1 && /^(confirmed_count|contradicted_count|last_confirmed|status):/ { print }
    ' "$FILE"
}

if [ "$ACTION" = "--show" ]; then show_counters; exit 0; fi

case "$ACTION" in
    confirmed)   FIELD="confirmed_count";   KIND="reinforced" ;;
    contradicted) FIELD="contradicted_count"; KIND="contradicted" ;;
    *) usage ;;
esac

TODAY=$(date '+%Y-%m-%d')
[ -n "$REASON" ] || REASON="outcome ${ACTION} через /learn"
# Кавычки в reason сломали бы YAML-строку — убираем на границе, как в других хуках.
REASON=$(printf '%s' "$REASON" | tr -d '"' | tr '\n' ' ')

TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' EXIT

# Одним проходом: инкремент счётчика, обновление last_confirmed, вставка записи в
# modification_history. Поле истории существует в трёх состояниях — отсутствует,
# `[]`, блочный список; обрабатываем все три, иначе запись молча теряется.
awk -v field="$FIELD" -v kind="$KIND" -v today="$TODAY" -v reason="$REASON" \
    -v tcase="$TRIGGER_CASE" -v action="$ACTION" '
function hist_entry() {
    out = "  - date: " today "\n    kind: " kind "\n    reason: \"" reason "\""
    if (tcase != "") out = out "\n    trigger_case: " tcase
    return out
}
BEGIN { depth = 0; bumped = 0; hist_state = "absent"; in_hist = 0 }
/^---[[:space:]]*$/ {
    depth++
    if (depth == 2) {
        # Закрываем открытый блок истории, если он шёл последним полем.
        if (in_hist) { print hist_entry(); in_hist = 0 }
        if (hist_state == "absent") {
            print "modification_history:"
            print hist_entry()
        }
        print; next
    }
    print; next
}
depth == 1 {
    # Выход из блока истории по следующему полю верхнего уровня.
    if (in_hist && /^[A-Za-z_][A-Za-z0-9_]*:/) { print hist_entry(); in_hist = 0 }

    if ($0 ~ "^" field ":") {
        v = $0; sub("^" field ":[[:space:]]*", "", v)
        if (v ~ /^-?[0-9]+$/) { printf "%s: %d\n", field, v + 1 } else { printf "%s: 1\n", field }
        bumped = 1; next
    }
    if (action == "confirmed" && /^last_confirmed:/) { print "last_confirmed: " today; next }
    if (/^modification_history:[[:space:]]*\[\][[:space:]]*$/) {
        print "modification_history:"; print hist_entry(); hist_state = "written"; next
    }
    if (/^modification_history:[[:space:]]*$/) {
        print; in_hist = 1; hist_state = "written"; next
    }
    print; next
}
{ print }
END {
    if (!bumped) {
        # Поля счётчика не было — сообщаем наружу, чтобы не молчать об этом.
        print "MISSING_FIELD" > "/dev/stderr"
    }
}
' "$FILE" > "$TMP_OUT" 2>"$TMP_OUT.err"

if [ ! -s "$TMP_OUT" ]; then
    echo "knowledge-counter-bump: пустой результат, файл не тронут" >&2
    exit 1
fi

if grep -q "MISSING_FIELD" "$TMP_OUT.err" 2>/dev/null; then
    # Поля не было — дописываем его в конец frontmatter, чтобы счёт начался.
    awk -v field="$FIELD" '
        /^---[[:space:]]*$/ { d++; if (d == 2) { print field ": 1" } }
        { print }
    ' "$TMP_OUT" > "$TMP_OUT.2" && mv "$TMP_OUT.2" "$TMP_OUT"
fi
rm -f "$TMP_OUT.err" 2>/dev/null || true

cat "$TMP_OUT" > "$FILE"
echo "✅ $(basename "$FILE"): ${FIELD}++ ($(show_counters | tr '\n' ' '))"
