#!/usr/bin/env bash
# rules-write-bypass.sh — PreToolUse[Bash]: запись в установленные правила только через библиотеку (D101).
# en: PreToolUse[Bash] — the installed rules file may only be written through the merge library.
#
# Результат: маркеры управляемого блока в ~/.claude/CLAUDE.md не теряются — пара «правила»
#            в drift-check никогда не бывает BROKEN.
# Проверка результата: bash hooks/tests/drift-check.sh | grep -q '^OK|правила'
#
# Повод. 28 августа 2026 пара «правила» была BROKEN: в установленном файле не оказалось
# маркеров, и сравнивать стало нечем. Шесть пар из семи сверялись, седьмая — нет, то есть
# мастер-копия могла уехать от установленной сколь угодно далеко, и ни один прогон бы об
# этом не сказал. Дрейф означает «сравнили и разошлось»; здесь было «не сравнивали вовсе».
#
# Почему именно эта пара беззащитна. У остальных шести установка — побайтовая копия, и любой
# обход ловится сравнением. Здесь установка ПРЕОБРАЗУЕТ содержимое (оборачивает в маркеры),
# поэтому обход даёт не расхождение, а невозможность сравнить.
#
# Почему страж стал возможен только сейчас. Пункт D101 отверг его возражением «правка идёт
# инструментом Edit, а хук PreToolUse[Bash] её не видит». Замер 28 августа по пяти сессиям:
# касаний ~/.claude/CLAUDE.md через Bash — 23, через Edit/Write — 0. Возражение снято
# данными, а не мнением.
#
# КОНТРПРИМЕР: правка установленных правил ИЗ ДРУГОГО ПРОЦЕССА — редактором, файловым
# менеджером, чужим скриптом — сюда не попадает: хук видит только вызовы Bash этой сессии.
# Для такого случая остаётся drift-check, который скажет постфактум.
#
# Input  (stdin): {tool_name, tool_input, ...}
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny", ...}} либо пусто
# Exit:  always 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Законный путь — через библиотеку слияния либо через установщик. Проверяется ПЕРВЫМ:
# если он в команде есть, дальше не смотрим.
case "$CMD" in
    *sync_claude_md*|*claude-md-merge*|*install.sh*) exit 0 ;;
esac

# Цель — установленные ГЛОБАЛЬНЫЕ правила, не проектный CLAUDE.md.
case "$CMD" in
    *'.claude/CLAUDE.md'*) ;;
    *) exit 0 ;;
esac

# Запись, а не чтение. Правило, а не перечень символов: перенаправление В ФАЙЛ либо
# команда, кладущая файл на место. Слияния потоков (2>&1) записью не считаются.
BARE=$(printf '%s' "$CMD" | awk '{
    s = $0
    gsub(/\047[^\047]*\047/, " ", s)
    gsub(/"[^"]*"/, " ", s)
    gsub(/[0-9]?>>?[[:space:]]*\/dev\/null/, " ", s)
    gsub(/[0-9]?>&[0-9]/, " ", s)
    gsub(/&>>?/, " ", s)
    print s
}')
IS_WRITE=0
grep -qE '>>?[[:space:]]*[^&[:space:]]' <<< "$BARE" && IS_WRITE=1
grep -qE '(^|[|;&[:space:]])(cp|mv|tee|install)[[:space:]]' <<< "$BARE" && IS_WRITE=1
grep -qE 'sed[[:space:]]+-i' <<< "$BARE" && IS_WRITE=1
[ "$IS_WRITE" -eq 1 ] || exit 0

MSG="⛔ ОТКАЗ (вызов не выполнен). Запись в установленные правила мимо библиотеки слияния.

Прямая запись в ~/.claude/CLAUDE.md стирает маркеры управляемого блока. Без них drift-check
по паре «правила» печатает BROKEN — «не с чем сравнить», — и мастер-копия может уехать от
установленной сколь угодно далеко молча. Так уже было 28 августа 2026.

Правильный путь один и он короткий:

    . lib/claude-md-merge.sh && sync_claude_md \"\$HOME/.claude/CLAUDE.md\" rules/CLAUDE.md

Библиотека сама делает бэкап и сохраняет маркеры. Чтение файла не блокируется."

jq -cn --arg m "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$m}}' 2>/dev/null || true
exit 0
