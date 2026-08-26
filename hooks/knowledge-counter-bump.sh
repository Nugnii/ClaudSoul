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
#   confirmed   → confirmed_count++,   last_confirmed = сегодня, provenance_log += reinforced
#   contradicted → contradicted_count++, provenance_log += contradicted
#
# Почему provenance_log, а не modification_history (разнесено 2026-08-11). Раньше писали в
# историю модификаций — и она перестала означать то, что означает: 96 из 132 записей базы были
# подтверждениями, а не перекройками правила, из-за чего формула fragile (≥3 записей истории)
# по букве метила «хрупким» любое хорошо подтверждённое знание. Теперь два смысла в двух полях:
# modification_history — только narrowed/branched/deprecated/scope_widened/
# reinforced_after_challenge (её и считает fragile), provenance_log — «почему подтвердилось
# в этот раз». Миграция базы: scripts/split-provenance-log.py.
#
# Идемпотентности НЕТ намеренно: каждый вызов — отдельная встреча знания с решением.
# Дедуп «один раз за сессию» делает producer (knowledge-activator), а не этот скрипт.
#
# Exit: 0 — записано; 1 — знание не найдено / плохие аргументы.

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; fi

usage() {
    echo "usage: $(basename "$0") <knowledge> confirmed|contradicted|not_applicable|applicable_not_followed [reason] [trigger_case]" >&2
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

# Исходы без счётчика: знание всплыло не к месту (`not_applicable`, D60) либо
# знание ОТНОСИЛОСЬ к делу и НЕ БЫЛО применено (`applicable_not_followed`, D62).
# Счётчики не трогаются: ни «мимо», ни пропуск не подтверждают и не опровергают
# правило. Но запись обязана состояться, иначе ключ висит в pending и печатается
# каждой следующей сессией, превращая узкую очередь blocker-tier в фон — а
# единственная кнопка, гасившая алерт, писала confirmed, то есть механизм
# подталкивал завышать confirmed_count.
# Почему второй исход отдельным значением, а не «тоже мимо»: applicable_not_followed
# — единственная метрика разрыва «знание → действие», ради которой строится
# система. Слитый с not_applicable, он перестаёт быть наблюдаемым.
case "$ACTION" in not_applicable|applicable_not_followed)
    S="${CLAUDE_STATE_DIR:-$HOME/.claude/hooks/state}"
    TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    CONF=$(awk '/^confidence:/{print $2; exit}' "$FILE")
    KEY=$(basename "$FILE" .md)
    if [ "$ACTION" = "not_applicable" ]; then
        DEFAULT_REASON="знание не относилось к тому, что делали"
    else
        DEFAULT_REASON="знание относилось к делу и не было применено"
    fi
    REASON_CLEAN=$(printf '%s' "${REASON:-$DEFAULT_REASON}" | tr -d '"' | tr '\n' ' ')

    # Durable-журнал — источник для /knowledge-audit, переживает сессию.
    printf '{"date":"%s","session":"%s","knowledge":"%s.md","confidence":%s,"outcome":"%s","case":"%s"}\n' \
        "$TS" "${CLAUDE_CODE_SESSION_ID:-}" "$KEY" "${CONF:-0}" "$ACTION" "$REASON_CLEAN" \
        >> "$S/disagreement-outcomes.jsonl"

    # Гасим pending в ТОМ файле, где запись создана: алерт приходит на следующей
    # сессии, а запись лежит в файле предыдущей (тот же разрыв чинил v1.12.0).
    CLOSED=0
    for f in "$S"/disagreement-pending-*.jsonl; do
        [ -e "$f" ] || continue
        grep -q "\"key\":\"$KEY\"" "$f" 2>/dev/null || continue
        grep -q "\"key\":\"$KEY\".*\"outcome\":\"pending\"" "$f" 2>/dev/null || continue
        printf '{"date":"%s","key":"%s","outcome":"%s"}\n' "$TS" "$KEY" "$ACTION" >> "$f"
        CLOSED=$((CLOSED + 1))
    done

    echo "✅ $KEY: $ACTION записан (счётчики не тронуты, погашено записей: $CLOSED)"
    exit 0
    ;;
esac

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
# provenance_log. Поле провенанса существует в трёх состояниях — отсутствует,
# `[]`, блочный список; обрабатываем все три, иначе запись молча теряется.
# modification_history этот скрипт больше НЕ трогает — она только для перекроек правила.
awk -v field="$FIELD" -v kind="$KIND" -v today="$TODAY" -v reason="$REASON" \
    -v tcase="$TRIGGER_CASE" -v action="$ACTION" -v logfield="provenance_log" '
function hist_entry() {
    out = "  - date: " today "\n    kind: " kind "\n    reason: \"" reason "\""
    if (tcase != "") out = out "\n    trigger_case: " tcase
    return out
}
BEGIN { depth = 0; bumped = 0; hist_state = "absent"; in_hist = 0 }
/^---[[:space:]]*$/ {
    depth++
    if (depth == 2) {
        # Закрываем открытый блок провенанса, если он шёл последним полем.
        if (in_hist) { print hist_entry(); in_hist = 0 }
        if (hist_state == "absent") {
            print logfield ":"
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
    if ($0 ~ "^" logfield ":[[:space:]]*\\[\\][[:space:]]*$") {
        print logfield ":"; print hist_entry(); hist_state = "written"; next
    }
    if ($0 ~ "^" logfield ":[[:space:]]*$") {
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
