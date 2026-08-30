#!/usr/bin/env bash
# changelog-reminder.sh — PreToolUse[Bash] на `git commit`: тихо напоминает добавить запись в CHANGELOG.md, если в staged diff есть изменения КОДА, а CHANGELOG.md в staged нет.
# en: PreToolUse[Bash] on `git commit`: quietly reminds to add a CHANGELOG entry when code changed.
#
# Механизирует текстовое правило «каждое изменение → CHANGELOG» (канон D5:
# always-fire правило — лучше хуком, чем текстом). Scoped против ложных
# срабатываний (урок R3 docs-family-check): только реальный код (hooks/*.sh,
# mcp-server/**/*.py, scripts/*), исключая tests/ и сам CHANGELOG; docs-only /
# SESSION-only / test-only коммиты не триггерят. Silent (additionalContext),
# не блокирует — агент решает.
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

# Команда сама заметает в индекс всё изменённое? Тогда правленый в дереве файл уйдёт
# в этот же коммит, и напоминать не о чем. Пробел после `add` обязателен: `git add -p`
# добавляет выборочно, `git commit -am` — да, `git commit --amend` — нет.
is_add_all() {
    local exec_part; exec_part=$(executable_part "${1:-}")
    grep -qE '(^|[[:space:]]|;|&|\||`)git[[:space:]]+add[[:space:]]+(-A|-all|--all|\.)([[:space:]]|$)' <<< "$exec_part" && return 0
    grep -qE '(^|[[:space:]]|;|&|\||`)git[[:space:]]+commit[[:space:]]+(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)' <<< "$exec_part"
}

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
is_git_commit "$COMMAND" || exit 0

# cwd из payload, не из окружения процесса — тот же баг чинился в
# claude-md-size-check (v1.12.4), сюда фикс не доходил до аудита 2026-08-08.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Конвенция opt-in: проект без CHANGELOG.md напоминаниями не пилится.
[ -f "$ROOT/CHANGELOG.md" ] || exit 0

# Staged-файлы (если не в git-репо или нет staged — выходим тихо).
STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$STAGED" ] && exit 0

# CHANGELOG учтён → ничего не нужно.
#
# Смотрим и в индекс, и в рабочее дерево. Хук стоит на PreToolUse и читает индекс ДО
# того, как отработает `git add` из той же составной команды: при `git add -A && git
# commit -m x` правленый, но ещё не добавленный CHANGELOG выглядел отсутствующим, хотя
# уходил в тот же коммит. Тот же дефект чинили в docs-family-check на v1.14.1.
#
# Рабочее дерево засчитывается ТОЛЬКО когда команда сама добавляет всё подряд
# (`git add -A`, `git add .`, `git commit -a`) — тогда правленый файл действительно
# уйдёт в этот коммит. Иначе грязный CHANGELOG глушил напоминание для коммита, в
# который он не попадает: `git commit -m fix hooks/demo.sh` с pathspec уносит один
# файл, а страж молчал, потому что CHANGELOG где-то правился. Проверено доведением
# до коммита — `git show --name-only HEAD` записи не содержал.
CHANGELOG_TOUCHED=$(printf '%s\n' "$STAGED" | grep -xE 'CHANGELOG\.md')
if [ -z "$CHANGELOG_TOUCHED" ] && \
   is_add_all "$COMMAND" && \
   grep -qxE 'CHANGELOG\.md' <<< "$(git -C "$CWD" diff --name-only 2>/dev/null)"; then
    CHANGELOG_TOUCHED="CHANGELOG.md"
fi
[ -n "$CHANGELOG_TOUCHED" ] && exit 0

# Есть ли реальный КОД? По расширению, не по дереву ClaudSoul (переносимость,
# аудит 2026-08-08); tests и документация не считаются.
CODE=$(printf '%s\n' "$STAGED" | grep -vE '(^|/)tests?/' \
    | grep -E '\.(sh|bash|py|js|jsx|ts|tsx|go|rs|rb|php|java|kt|kts|c|cc|cpp|h|hpp|swift|scala|sql|lua|vue|svelte)$' || true)
[ -z "$CODE" ] && exit 0

# Per-session throttle по набору staged-кода (тот же diff не напоминаем дважды).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
KEY=$(printf '%s' "$CODE" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/changelog-reminder-${SID}.txt"
if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi
printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null

MSG="📝 CHANGELOG: в staged есть изменения кода, но CHANGELOG.md не добавлен. Если это содержательное изменение — добавь запись в [Unreleased] (правило «каждое изменение → CHANGELOG»). Если это рефактор/чор без пользовательского эффекта — игнорируй."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
