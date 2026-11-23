#!/usr/bin/env bash
# lib-prefix-guard.sh — PreToolUse[Write|Edit|MultiEdit]: новая функция библиотеки носит имя из ОБЪЯВЛЕННОГО пространства имён, а не выведенное из ряда соседних.
# en: PreToolUse on library writes — a new function must carry one of the prefixes declared in the file header.
#
# Результат: в `hooks/*-lib.sh` не появляется функция с префиксом, которого нет в строке
#            `# ПРЕФИКСЫ:` этой библиотеки
# Проверка результата: bash hooks/tests/test_lib_prefix_guard.sh даёт 0
#
# Повод — слово владельца 11 сентября 2026: «должен быть какой-то механизм по неймингу
# функций при создании новой». Сказано после того, как я выдумал `rc_trace_counts`,
# выведя имя из соседних `rc_trace` и `rc_trace_text`. Тот же класс стоил проекту D318:
# `_cm_merge_into` достроено по образцу `_cm_write_managed_block`, а библиотека, где
# функция зовётся `sync_claude_md`, прочитана не была.
#
# ПОЧЕМУ СПЕРВА ОБЪЯВЛЕНИЕ, А НЕ СРАЗУ СТРАЖ. Замер 11 сентября 2026: правила именования
# не было ни в одном документе, в библиотеках 45 разных префиксов, и лишь 10 из 21
# библиотеки с 3+ функциями держали 80%+ имён под одним. Признак «префикс совпадает с
# самым частым в файле» дал бы 11 ложных из 21. Потому порядок обратный: сперва
# ОБЪЯВЛЕНИЕ (`# ПРЕФИКСЫ:` в шапке, собрано ИЗ ФАКТА), затем сверка объявленного с
# написанным — то же устройство, что у карты корней (`ROOTS.md` + `scripts/root-map.py`).
#
# ЧТО ПОД ПРАВИЛО НЕ ПОДПАДАЕТ и почему:
#   · имя с ведущим `_` — внутреннее, у него своя жизнь и своё пространство;
#   · файл без строки `# ПРЕФИКСЫ:` — объявления нет, сверять не с чем: страж молчит,
#     а доля библиотек с объявлением считается замером (сейчас 29 из 29);
#   · не-библиотеки (`hooks/*.sh` без `-lib`) — у них пространство имён не объявляется.
#
# Уровень — ПОДСКАЗКА, не отказ. Точность признака на живых правках не измерена: отказ
# уровня 4 заводится только с измеренной точностью на признаке с одним последствием
# (`case-2026-08-28-enforcement-is-a-property-of-consequence`). Положительный контроль
# при заведении: страж прогнан по всем 29 библиотекам дерева и промолчал на каждой.
#
# Input  (stdin): {tool_name, tool_input:{file_path, content|new_string}}
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} либо пусто
# Exit:  always 0.

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
case "$FILE" in *-lib.sh) ;; *) exit 0 ;; esac

# Что записывается: у Write это content, у Edit — новая половина, у MultiEdit — все новые куски
BODY=$(printf '%s' "$INPUT" | jq -r '
    (.tool_input.content // "")
    + "\n" + (.tool_input.new_string // "")
    + "\n" + ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
' 2>/dev/null)
# Непустоту проверяем grep, а не `${BODY//…/}`: глобальная замена по строке в 100 КБ
# (root-cause-lib.sh) в bash 3.2 квадратична — страж висел 30 с и был убит по времени.
grep -q '[^[:space:]]' <<< "$BODY" || exit 0

# Объявление берётся у ФАЙЛА на диске, а при его отсутствии — из записываемого текста:
# новый файл несёт объявление в себе, иначе сверять не с чем.
DECL=""
[ -f "$FILE" ] && DECL=$(grep -m1 '^# ПРЕФИКСЫ:' "$FILE" 2>/dev/null)
[ -n "$DECL" ] || DECL=$(printf '%s' "$BODY" | grep -m1 '^# ПРЕФИКСЫ:' 2>/dev/null)
[ -n "$DECL" ] || exit 0
PREFIXES=${DECL#\# ПРЕФИКСЫ:}

BAD=""
while IFS= read -r _fn; do
    [ -n "$_fn" ] || continue
    case "$_fn" in _*) continue ;; esac        # внутреннее имя
    _ok=0
    for _p in $PREFIXES; do
        case "$_fn" in "$_p"*) _ok=1; break ;; esac
    done
    [ "$_ok" -eq 1 ] || BAD="$BAD $_fn"
done <<FNS
$(printf '%s' "$BODY" | grep -oE '^[a-z_][a-z0-9_]*\(\)' | sed 's/()//')
FNS

[ -n "$(printf '%s' "$BAD" | tr -d '[:space:]')" ] || exit 0

jq -Rn --arg bad "$BAD" --arg pref "$PREFIXES" --arg f "${FILE##*/}" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:
    ("🔤 Имя вне объявленного пространства имён " + $f + ":" + $bad +
     ". Объявлено: " + $pref +
     ". Имя, выведенное из ряда соседних, — выдумка: возьми префикс из строки «# ПРЕФИКСЫ:» этой библиотеки либо объяви новый там же, с доводом.")}}' 2>/dev/null
exit 0
