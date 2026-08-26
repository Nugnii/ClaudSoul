#!/usr/bin/env bash
# rework-detector.sh — PostToolUse: третий заход на тот же файл при зелёных прогонах.
# en: PostToolUse: third rework cycle on the same file while every run looks green.
#
# Слепое пятно, которое он закрывает. Все существующие детекторы повторения реагируют
# на ОШИБКИ: `error-tracker` считает подряд идущие провалы Bash и на втором просит
# остановиться. Повторение с ЗЕЛЁНЫМ результатом не видит никто.
#
# Живой случай (v1.12.4). Один тест переписывался трижды: чистое дерево → staged пусто,
# стражи не запускались; воспроизведение последнего коммита → покрытие случайное;
# и только «всё дерево в индекс» дало настоящий прогон. Каждая из трёх итераций
# завершалась «0 провалов», то есть выглядела успехом. Ни один счётчик их не связал,
# и разбор причины («5 почему») не запускался — запускать его было нечему.
#
# Собеседник назвал это точно: три раза сделано одно и то же, потому что не был
# применён приём, который агент знает и раньше применял. Знание без момента
# срабатывания не работает — уровень 1 embedded-ness.
#
# Сигнатура переработки: правка файла → прогон → правка ТОГО ЖЕ файла → прогон →
# правка. Просто три правки подряд не считаются: это нормальное дописывание.
# Между правками обязан быть прогон — значит, результат проверяли и он не устроил.
#
# Contract:
#   Input  (stdin): PostToolUse JSON {session_id, tool_name, tool_input}
#   Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
#   Exit:  always 0
#
# Порог: REWORK_THRESHOLD (по умолчанию 3) — на третьей правке в цепочке.
# Throttle: один раз на файл за сессию, иначе алерт станет фоном.

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

THRESHOLD="${REWORK_THRESHOLD:-3}"

mkdir -p "$STATE_DIR" 2>/dev/null
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
LOG="$STATE_DIR/rework-${SID}.jsonl"

case "$TOOL" in
    Bash)
        # Прогон. Отмечаем только если в сессии уже была хоть одна правка —
        # до первой правки цепочки не существует, и файл не создаём.
        [ -f "$LOG" ] || exit 0
        printf '{"kind":"run"}\n' >> "$LOG" 2>/dev/null || true
        exit 0
        ;;
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -n "$FILE" ] || exit 0

# Калибровка D18 (2026-08-08, выборка 40 срабатываний): 10 пришлись на
# файлы-хроники (CHANGELOG x4, BACKLOG x3, SESSION x2, архив) — там повторные
# правки норма жанра (append-лог), ни одно срабатывание не было переработкой.
# Хроники исключены до записи в цепочку; маска переопределяется env.
#
# Разметка выборки D23 (2026-08-11, 36 срабатываний после калибровки): хроник ноль —
# исключение работает, — но два срабатывания пришлись на CLAUDE.md и одно на META.md.
# Это документы СОСТОЯНИЯ: они переписываются по ходу сессии столько раз, сколько
# уточняется картина, и повторная правка в них — тот же жанр, что append в хронике.
REWORK_EXCLUDE_RE="${REWORK_EXCLUDE_RE:-(CHANGELOG|SESSION|BACKLOG[^/]*|CLAUDE|META)\.md$}"
# Ответ берётся у grep, а не у трубы: под `set -o pipefail` producer, убитый SIGPIPE,
# отдаёт 141, и исключение молча перестаёт исключать (D50; доказано замером в D59).
grep -qE "$REWORK_EXCLUDE_RE" <<< "$FILE" && exit 0

printf '{"kind":"edit","path":"%s"}\n' "$FILE" >> "$LOG" 2>/dev/null || true

# Считаем правки этого файла, между которыми был прогон.
# Цепочка: edit(F) ... run ... edit(F) ... run ... edit(F) → CYCLES=3.
CYCLES=$(awk -v f="$FILE" '
    /"kind":"run"/ { ran = 1; next }
    /"kind":"edit"/ {
        # путь текущей строки
        if (split($0, a, "\"path\":\"") < 2) next
        split(a[2], b, "\"")
        if (b[1] != f) next
        if (first == 0) { first = 1; n = 1; ran = 0; next }
        if (ran == 1) { n++; ran = 0 }
    }
    END { print n + 0 }
' "$LOG" 2>/dev/null || echo 0)
CYCLES=${CYCLES:-0}

[ "$CYCLES" -ge "$THRESHOLD" ] 2>/dev/null || exit 0

# Throttle: один раз на файл за сессию.
FIRED="$STATE_DIR/rework-fired-${SID}.jsonl"
if [ -f "$FIRED" ] && grep -Fq "\"path\":\"$FILE\"" "$FIRED" 2>/dev/null; then
    exit 0
fi
printf '{"path":"%s","cycles":%s}\n' "$FILE" "$CYCLES" >> "$FIRED" 2>/dev/null || true

BASE=$(basename "$FILE")
CTX=$(printf '🔁 Переработка: %s правится %s-й раз, и между правками были прогоны — значит результат каждый раз проверяли и он не устраивал.\n\nВсе прогоны при этом могли быть зелёными: детектор ошибок такое не видит, он считает провалы.\n\nОстановись до следующей правки и назови причину, а не симптом:\n  1. Почему пришлось править снова?\n  2. Почему предыдущая правка не сработала?\n  3. Почему это не было видно сразу?\n  4. Почему проверка не поймала?\n  5. Что в процессе позволяет этому повторяться?\n\nЕсли причина найдена — чини её, а не текущий симптом. Если правка действительно четвёртая по делу (разные задачи в одном файле) — игнорируй.' \
    "$BASE" "$CYCLES")

jq -n --arg ctx "$CTX" '{
    hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $ctx
    }
}'
exit 0
