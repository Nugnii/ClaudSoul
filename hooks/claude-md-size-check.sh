#!/usr/bin/env bash
# claude-md-size-check.sh — PreToolUse[Bash] на `git commit`: тихо предупреждает, если CLAUDE.md проекта раздулся выше порога стоимости контекста.
# en: PreToolUse[Bash] on `git commit`: quietly warns when CLAUDE.md grows past the context-cost threshold.
# Механизирует канон D1 (короткий
# CLAUDE.md — иначе важные правила тонут) + D4 (подрезать регулярно): always-fire
# проверка лучше хуком, чем текстовым правилом (канон D5).
#
# Срабатывает раз в сессию и ТОЛЬКО при превышении порога (молчит, пока файл в
# норме). Предмет — CLAUDE.md корня git-репозитория текущего проекта, не глобальный
# ~/.claude/CLAUDE.md. Способ подрезки — вынести детализацию в .claude-docs/modules/.
#
# Input  (stdin): {tool_name, tool_input, session_id} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

# Детект коммита — по ИСПОЛНЯЕМОЙ части команды (single source — command-scope-lib.sh):
# `git commit` в кавычках или в теле heredoc — текст, а не команда.
SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    is_git_commit() { grep -qE 'git[[:space:]]+commit' <<< "${1:-}"; }
fi
command -v executable_commit_dir >/dev/null 2>&1 || executable_commit_dir() { return 2; }   # без разбора — папка сессии

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

THRESHOLD_BYTES=102400   # ~100 КБ

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
is_git_commit "$COMMAND" || exit 0

# CLAUDE.md в корне git-репо текущего проекта.
# `cwd` берём из payload, а не из окружения процесса (v1.12.4). Процесс хука не
# обязан стоять в каталоге сессии, и без `-C` страж смотрел в посторонний репозиторий:
# то есть проверял размер чужого CLAUDE.md и молчал про свой. Соседние стражи
# (docs-family-check, quality-gate-check) читают `.cwd` явно — этот отставал.
# Найдено первым же написанным для него тестом.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
# Каталог КОММИТА — у разбора команды (`cd` и `-C`), а не папка сессии (D1282, братья D1278). Разбор не ответил — папка сессии.
_CD=$(executable_commit_dir "$CWD" "$COMMAND") && CWD="$_CD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
CLAUDE="$ROOT/CLAUDE.md"
[ -f "$CLAUDE" ] || exit 0

SIZE=$(wc -c < "$CLAUDE" 2>/dev/null | tr -d ' ')
[ -z "$SIZE" ] && exit 0
[ "$SIZE" -le "$THRESHOLD_BYTES" ] && exit 0

# Throttle: раз в сессию на проект (пока файл над порогом — не спамим каждый коммит).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
RKEY=$(printf '%s' "$ROOT" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/claude-md-size-${SID}-${RKEY}.flag"
[ -f "$THROTTLE" ] && exit 0
: > "$THROTTLE" 2>/dev/null

KB=$((SIZE / 1024))

# Адрес правки, а не «файл велик»: самый жирный раздел `## ` — его и подрезают.
# Без адреса совет неисполним, и это измеримо: в ProjectA страж отработал 42 раза
# с 14 июня по 1 сентября 2026, файл за это время не подрезан ни разу и вырос
# с 100 до 114 КБ. Раздел там был один — §4 на 70% файла.
BIGGEST=$(awk '/^## /{if(s){printf "%d\t%s\n", b, s} s=$0; b=0} {b+=length($0)+1} END{if(s)printf "%d\t%s\n", b, s}' "$CLAUDE" 2>/dev/null | sort -rn | head -1)
BIG_B=$(printf '%s' "$BIGGEST" | cut -f1)
BIG_T=$(printf '%s' "$BIGGEST" | cut -f2 | sed 's/^## //')
BIG_PCT=0
[ -n "$BIG_B" ] && [ "$SIZE" -gt 0 ] && BIG_PCT=$((BIG_B * 100 / SIZE))

# Выноски, которые УЖЕ ссылаются на модуль, — это пересказ модуля, а не деталь без
# места. Требовать «вынеси в модуль» на них бессмысленно: вынесено, и агент читает
# требование как выполненное. Их чинит другое действие — сжатие до инварианта.
RETOLD=$(grep -c '^> \*\*.*\.claude-docs/modules/' "$CLAUDE" 2>/dev/null | tr -d ' ')
[ -z "$RETOLD" ] && RETOLD=0

MSG="📏 CLAUDE.md раздут (${KB} КБ > 100 КБ — канон D1/D4). Важные правила тонут в шуме."
[ "${BIG_PCT:-0}" -ge 30 ] && MSG="${MSG} Самый жирный раздел — «${BIG_T}» (${BIG_PCT}% файла), начинай с него."
if [ "${RETOLD:-0}" -ge 10 ]; then
    MSG="${MSG} Выносок, которые уже ссылаются на модуль и при этом его ПЕРЕСКАЗЫВАЮТ: ${RETOLD}. Их не надо «выносить в модуль» — модуль уже есть; сожми каждую до одного инварианта + ссылки, дописав в модуль то, чего там нет."
else
    MSG="${MSG} Подрежь: вынеси детализацию (пути файлов, имена функций, теги версий, механику UI) в .claude-docs/modules/, оставив в CLAUDE.md только связывающий инвариант + ссылку."
fi
MSG="${MSG} Самоочевидное (канон D3) удали."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
