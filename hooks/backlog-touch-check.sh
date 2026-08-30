#!/usr/bin/env bash
# backlog-touch-check.sh — PreToolUse[Edit|Write|MultiEdit]: правишь файл, который назван в открытом пункте долга.
# en: PreToolUse on file edits — the file is named in an open backlog item.
#
# Результат: правка файла, названного в открытом пункте долга, не проходит незамеченной:
#            либо пункт берётся в работу и метится, либо правка признана другой работой
# Проверка результата: bash hooks/tests/test_backlog_touch_check.sh даёт 0
#
# Повод — требование владельца 29 августа 2026, дословно: «при починке чего-то должна
# проходить сверка с бэклогом не была ли там эта проблема и не решили ли мы её».
#
# Зачем механизм, а не память. Долг ведётся, чтобы проблема не потерялась, — но читают его
# в начале работы, а чинят через час-два, и к моменту правки пункт уже вне внимания. Так
# получается третий исход, которого не должно быть: проблема числится открытой, а починка
# идёт как «новая задача» — и закрытие не отмечается, потому что никто не вспомнил, что
# закрывать. Обратный случай так же плох: чинится то, что уже закрыто и лежит в архиве.
#
# ДВА БЭКЛОГА, а не один. Долг самого ClaudSoul виден из любого проекта (абсолютный путь
# через paths-lib), локальный долг проекта — по cwd из payload. Тот же двойной контур, что
# у session-collector: cwd-only глушит кросс-проектный долг, absolute-only — локальный.
#
# ПОЧЕМУ ИНЖЕКТ, А НЕ ОТКАЗ. У совпадения ДВА последствия, а не одно: правка может быть
# починкой этого пункта, а может быть работой рядом с ним. Правило отказа (ADR-011)
# требует признака с ОДНИМ последствием и замеренной точностью; здесь ни того, ни другого,
# и слепой отказ дал бы ложные блоки на соседней работе — прецедент измерен: 40 отказов,
# из них 32 ложных (case-2026-08-28-enforcement-is-a-property-of-consequence).
#
# КОНТРПРИМЕР: файл, чьё имя случайно встретилось в тексте пункта («правь не CLAUDE.md, а
# rules/CLAUDE.md»), даст ложное совпадение — признак смотрит на текст пункта, а не на
# список файлов, который пункт затрагивает. Цена ложного — одна строка контекста.
# НАЗВАННЫЙ ПРЕДЕЛ: сверка идёт по ОТНОСИТЕЛЬНОМУ пути и по имени файла, то есть пункт,
# описывающий проблему без единого пути (например «числа в доках расходятся»), не совпадёт
# ни с одной правкой.
# Условие снятия: предел держится, пока пункт долга называет места прозой. Появится у
# пункта машинное поле с адресами (см. контракт пункта в BACKLOG.md) — сверка пойдёт по
# нему, и угадывание по тексту станет не нужно.
#
# Input  (stdin): {session_id, tool_name, tool_input:{file_path}, cwd} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} либо пусто
# Exit:  always 0 (degrade gracefully).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -n "$FILE" ] || exit 0

BASE=$(basename "$FILE")
# Хроники и черновики отбрасываются: повторная правка там норма жанра, и упоминание их
# имён в пунктах долга сплошное (та же калибровка, что у rework-detector, D18/D23).
case "$BASE" in
    CHANGELOG.md|SESSION.md|BACKLOG.md|BACKLOG-archive.md|CLAUDE.md|META.md) exit 0 ;;
esac
case "$FILE" in */tmp/*|*scratchpad*|*/_drafts/*|*/.claude-docs/sessions/*) exit 0 ;; esac

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"

BL_LIB="${BL_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/backlog-lib.sh}"
[ -f "$BL_LIB" ] || BL_LIB="$HOME/.claude/hooks/backlog-lib.sh"
# Опознание пункта — только из общей библиотеки. Своя копия признака здесь уже отказывала
# у трёх стражей: 28 августа 2026 сменилась вёрстка, и они сутки видели ноль пунктов.
# shellcheck source=/dev/null
{ [ -f "$BL_LIB" ] && . "$BL_LIB"; } || exit 0
command -v backlog_item_re >/dev/null 2>&1 || exit 0

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)

# Носители долга: локальный (проект сессии) и абсолютный (ClaudSoul). Держатся ДВУМЯ
# переменными, а не списком через пробел: путь проекта сам содержит пробел
# («~/My Project/ClaudSoul»), и неквотированное расширение списка рвёт его на два
# несуществующих пути — страж молчит на живом дереве, оставаясь зелёным в тестах, где
# `mktemp` даёт пути без пробелов. Поймано прогоном на самом репозитории.
BL_LOCAL=""
if [ -n "$CWD" ] && command -v find_project_root >/dev/null 2>&1; then
    _root=$(find_project_root "$CWD")
    [ -n "$_root" ] && [ -f "$_root/BACKLOG.md" ] && BL_LOCAL="$_root/BACKLOG.md"
fi
BL_CS="${CLAUDSOUL_ROOT:-$HOME/My Project/ClaudSoul}/BACKLOG.md"
[ -f "$BL_CS" ] || BL_CS=""
[ -n "$BL_CS" ] && [ "$BL_CS" = "$BL_LOCAL" ] && BL_CS=""
[ -n "$BL_LOCAL" ] || [ -n "$BL_CS" ] || exit 0

# Блок пункта — от его заголовка до следующего заголовка. Совпадение ищется в ТЕЛЕ
# открытого пункта (☐ ◐): у закрытых своя судьба — они уезжают в архив.
OPEN_RE=$(backlog_item_re "${BACKLOG_OPEN_MARKS:-☐◐}")
HITS=""
for _bl in "$BL_LOCAL" "$BL_CS"; do
    [ -n "$_bl" ] && [ -f "$_bl" ] || continue
    _hit=$(awk -v item_re="$OPEN_RE" -v base="$BASE" '
        $0 ~ item_re { inside = 1; head = $0; found = 0; next }
        /^(- |#{2,6} )/ { inside = 0 }
        inside && index($0, base) > 0 && !found {
            found = 1
            if (match(head, /D[0-9]+/)) id = substr(head, RSTART, RLENGTH); else id = "?"
            # Короткая суть пункта: заголовок без разметки и метки. Метки убираются
            # ЛИТЕРАЛАМИ, а не классом символов: mawk (он и стоит в чистом Linux-образе)
            # не знает многобайтовых, и класс вида [метки] режется по БАЙТАМ — строка
            # ломается посреди символа (pattern-shell-portability, confirmed 31).
            t = head
            gsub(/^[-#[:space:]]+/, "", t); gsub(/[*]/, "", t)
            gsub(/☐/, "", t); gsub(/◐/, "", t); gsub(/☑/, "", t); gsub(/⊘/, "", t)
            sub(/^[[:space:]]*D[0-9]+[[:space:]]*/, "", t)   # номер печатается отдельно
            sub(/^[[:space:]]+/, "", t)
            if (length(t) > 70) t = substr(t, 1, 70) "…"
            print id "\t" t
        }
    ' "$_bl" 2>/dev/null | head -3)
    [ -n "$_hit" ] && HITS="${HITS}${_hit}
"
done
[ -n "${HITS//[[:space:]]/}" ] || exit 0

# Троттл: одно напоминание на пару (файл, пункт) за сессию, иначе станет фоном на правке
# одного и того же файла.
mkdir -p "$STATE" 2>/dev/null
FIRED="$STATE/backlog-touch-fired-${SID}.jsonl"
NEW=""
while IFS= read -r _line; do
    [ -n "${_line//[[:space:]]/}" ] || continue
    _id=${_line%%$'\t'*}
    _key="${_id}|${FILE}"
    grep -qxF "$_key" "$FIRED" 2>/dev/null && continue
    printf '%s\n' "$_key" >> "$FIRED" 2>/dev/null
    NEW="${NEW}  · ${_id}: ${_line#*$'\t'}
"
done <<< "$HITS"
[ -n "${NEW//[[:space:]]/}" ] || exit 0

MSG="📋 Правишь ${BASE}, а он назван в ОТКРЫТОМ пункте долга:
${NEW}
Реши до правки, иначе исход потеряется:
  · это та проблема → возьми пункт в работу (◐), назови измеримый результат и команду проверки; починил — переведи в ☑ с показанием, и пункт уедет в архив;
  · это другая работа → не расширяй задачу: находка по ходу заводится отдельным пунктом;
  · пункт уже решён, а метка осталась → закрой его с показанием, а не чини заново."

jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}' 2>/dev/null || true
exit 0
