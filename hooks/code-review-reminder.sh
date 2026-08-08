#!/usr/bin/env bash
# code-review-reminder.sh — PreToolUse[Bash] на `git commit`: тихо напоминает
# en: PreToolUse[Bash] on `git commit`: quietly reminds to review the diff before committing.
# прогнать /code-review (адверсариальный ревью дифа), если в staged крупный
# КОДОВЫЙ дифф. Механизирует канон A6 (ревью дифа свежим контекстом перед
# «готово») — always-fire правило лучше хуком, чем текстом (канон D5).
#
# Порог «крупный»: > LINES изменённых строк ИЛИ > FILES кодовых файлов в
# web/lib | web/app | web/components (*.ts/*.tsx). Scoped против ложных
# срабатываний: docs-only / tests-only / мелкие правки не триггерят.
# Throttle per-session per-diff-hash (тот же дифф не напоминаем дважды) — не
# детектит факт запуска /code-review (маркера нет), но не спамит. Silent.
#
# Input  (stdin): {tool_name, tool_input, session_id} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

LINES_THRESHOLD=80
FILES_THRESHOLD=4

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+commit' || exit 0

# numstat по staged кодовым файлам.
#
# Два дефекта, найденных первым же написанным для этого хука тестом (v1.12.4):
#
# 1. `cwd` не читался из payload. Процесс хука не обязан стоять в каталоге сессии,
#    и без `-C` страж смотрел diff постороннего репозитория.
# 2. Фильтр был `web/(lib|app|components)/*.ts(x)` — раскладка того проекта, откуда
#    хук импортировали в v1.11.0. В репозитории из bash, python и markdown он не мог
#    сработать НИКОГДА: молчал не потому что диффы мелкие, а потому что не понимал
#    ни одного здешнего файла. Молчание было структурно независимо от предмета проверки.
#
# Теперь набор расширений общий и переопределяется через `CODE_REVIEW_EXT`.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
NUMSTAT=$(git -C "$CWD" diff --cached --numstat 2>/dev/null) || exit 0
[ -z "$NUMSTAT" ] && exit 0
CODE_EXT="${CODE_REVIEW_EXT:-ts|tsx|js|jsx|mjs|cjs|py|sh|bash|go|rs|rb|java|kt|php|c|cc|cpp|h|hpp|sql}"
CODE=$(printf '%s\n' "$NUMSTAT" | grep -E "	.*\.($CODE_EXT)$" || true)
[ -z "$CODE" ] && exit 0

FILE_COUNT=$(printf '%s\n' "$CODE" | grep -c . )
LINE_COUNT=$(printf '%s\n' "$CODE" | awk '{a+=$1; d+=$2} END{print a+d+0}')

# Крупный дифф?
if [ "$LINE_COUNT" -le "$LINES_THRESHOLD" ] && [ "$FILE_COUNT" -le "$FILES_THRESHOLD" ]; then
  exit 0
fi

# Throttle per-session per-diff-hash.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
KEY=$(printf '%s' "$CODE" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/code-review-reminder-${SID}.txt"
if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi
printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null

MSG="🔍 Крупный кодовый дифф (${LINE_COUNT} строк / ${FILE_COUNT} файлов). Перед коммитом, если ещё не делал — прогони ревью адверсариально: инварианты, границы, обработка ошибок. Если ревью уже был или правка тривиальна — игнорируй."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
