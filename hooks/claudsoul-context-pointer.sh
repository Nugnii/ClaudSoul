#!/usr/bin/env bash
# claudsoul-context-pointer.sh — UserPromptSubmit hook, инжектит project CLAUDE.md status section при упоминании ClaudSoul снаружи директории проекта.
# en: UserPromptSubmit: injects the project CLAUDE.md status section when ClaudSoul is mentioned from outside its directory.
#
# Когда собеседник упоминает имя проекта, а cwd за пределами project tree —
# project CLAUDE.md (актуальное состояние) не подгружается через стандартную
# иерархию Claude Code. Хук это закрывает: инжектит секцию "## 5. Текущий
# статус" из project CLAUDE.md в additionalContext, чтобы агент видел
# реальное состояние, а не упрощённую модель из global CLAUDE.md.
#
# Закрывает 19-е проявление pattern-inside-out-blindness
# (case-2026-05-05-claudsoul-blindness-from-home.md): cross-directory
# blindness. Уровень 3 embedded-ness (mechanical injection,
# не text rule).
#
# v1.6.8 (case-2026-05-05-deployed-artifact-action-blindness.md, 20-е
# проявление): расширение detection за пределы bare project name на
# ClaudSoul-уникальные **path/filename** patterns. Substring-match ловил
# только явное "ClaudSoul" в тексте — но user reference на компоненты по
# пути или имени файла (без слова "claudsoul") мимо. Path-based recall
# закрывает эту дыру.
#
# Triggers (substring match на lowercased .user_prompt):
#   1. Project name: claudsoul, claud soul, claud-soul, клод соул, клод-соул
#   2. Path-based (v1.6.8): "global-lessons" — ClaudSoul knowledge base
#   3. Filename-based (v1.6.8): principle-*.md, pattern-*.md, entity-*.md —
#      ClaudSoul knowledge format (uniquely named files)
#
# Skip if:
#   - cwd внутри project директории (project CLAUDE.md уже загружен)
#   - per-session dedup (уже инжектили в этой сессии)
#   - project CLAUDE.md не существует или не читается
#   - empty session_id или user_prompt
#
# State: $STATE_DIR/claudsoul-pointer-fired-${SESSION_ID}.flag
# Output: jq hookSpecificOutput с additionalContext.

set -eo pipefail

STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || true

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
USER_PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0
[ -z "$USER_PROMPT" ] && exit 0

# -----------------------------------------------------------------------
# Detection — substring match (case-insensitive via tr)
#   1. project name (substring)
#   2. path-based: global-lessons (ClaudSoul knowledge base)
#   3. filename-based: principle-*.md, pattern-*.md, entity-*.md
# -----------------------------------------------------------------------
# Приведение регистра — через общую библиотеку: GNU tr кириллицу не сворачивает ни в какой
# локали, поэтому на Linux шаблоны с русскими словами молча не совпадают.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
elif [ -f "$HOME/.claude/hooks/portable-lib.sh" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.claude/hooks/portable-lib.sh"
else
    to_lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }
fi

PROMPT_LOWER=$(to_lower "$USER_PROMPT")
case "$PROMPT_LOWER" in
    *claudsoul*|*"claud soul"*|*"claud-soul"*|*"клод соул"*|*"клод-соул"*) ;;
    *global-lessons*) ;;
    *principle-*.md*|*pattern-*.md*|*entity-*.md*) ;;
    *) exit 0 ;;
esac

# -----------------------------------------------------------------------
# Resolve project path. Override via CLAUDSOUL_PROJECT_PATH env (для тестов).
# -----------------------------------------------------------------------
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; fi
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
[ -f "$THROTTLE_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$THROTTLE_LIB"


PROJECT_PATH="${CLAUDSOUL_PROJECT_PATH:-$CLAUDSOUL_ROOT}"
PROJECT_CLAUDE_MD="$PROJECT_PATH/CLAUDE.md"

[ -f "$PROJECT_CLAUDE_MD" ] || exit 0
[ -r "$PROJECT_CLAUDE_MD" ] || exit 0

# -----------------------------------------------------------------------
# Skip if cwd within project tree (CLAUDE.md уже загружен Claude Code)
# -----------------------------------------------------------------------
CURRENT_PWD="${CLAUDSOUL_TEST_PWD:-$PWD}"
case "$CURRENT_PWD" in
    "$PROJECT_PATH"|"$PROJECT_PATH"/*) exit 0 ;;
esac

# -----------------------------------------------------------------------
# Per-session dedup
# -----------------------------------------------------------------------
THROTTLE_FILE=$(throttle_file "$STATE_DIR" claudsoul-pointer "$SESSION_ID")
throttle_seen "$THROTTLE_FILE" session && exit 0

# -----------------------------------------------------------------------
# Extract "## 5. Текущий статус" section. Take header + first 25 lines
# of the section to keep injection compact (status table растёт большой,
# полный inject забил бы контекст).
# -----------------------------------------------------------------------
STATUS_SECTION=$(awk '
    /^## 5\. Текущий статус/ { in_section = 1 }
    in_section && /^## [0-9]/ && !/^## 5\./ { exit }
    in_section { print; lines++ }
    in_section && lines >= 25 { exit }
' "$PROJECT_CLAUDE_MD")

[ -z "$STATUS_SECTION" ] && exit 0

# -----------------------------------------------------------------------
# Fire: write flag + emit hint
# -----------------------------------------------------------------------
throttle_mark "$THROTTLE_FILE" session

MESSAGE="📚 ClaudSoul project state pointer

Cwd находится вне директории проекта (\`$PROJECT_PATH\`), поэтому project CLAUDE.md не загружен Claude Code автоматически. Ниже — выдержка из секции «Текущий статус» (первые ~25 строк). Полный файл: \`$PROJECT_CLAUDE_MD\`.

$STATUS_SECTION

— Если нужны детали по конкретному компоненту — прочитай файл по абсолютному пути."

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: .
  }
}'
