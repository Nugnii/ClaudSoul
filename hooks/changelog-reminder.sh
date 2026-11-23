#!/usr/bin/env bash
# changelog-reminder.sh — PreToolUse[Bash] на `git commit`: тихо напоминает добавить запись в CHANGELOG.md, если в staged diff есть изменения КОДА, а CHANGELOG.md в staged нет.
# en: PreToolUse[Bash] on `git commit`: quietly reminds to add a CHANGELOG.md entry when the staged diff contains CODE changes AND CHANGELOG.md is not staged.
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
command -v executable_commit_dir >/dev/null 2>&1 || executable_commit_dir() { return 2; }   # без разбора — папка сессии

# Команда сама заметает в индекс всё изменённое? Тогда правленый в дереве файл уйдёт
# в этот же коммит, и напоминать не о чем. Ответ — у владельца разбора
# (`executable_commit_adds`, command-scope-lib.sh, D1087): `all` и `tracked` оба уносят
# отслеживаемый CHANGELOG.md. Прежде здесь стояло своё выражение, и на таблице эталона
# (`test_commit_adds_oracle.sh`) оно ошибалось в 21 форме из 47. Разбора нет — «не
# добавит»: лишнее напоминание дешевле пропущенного.
is_add_all() {
    command -v executable_commit_adds >/dev/null 2>&1 && [ -n "$(executable_commit_adds "${1:-}")" ]
}

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# ЛОВУШКА GIT (D1022): `--commit-msg <файл>` зовёт `commit-trap.sh` в корне рабочего дерева коммита с его индексом
# (GIT_INDEX_FILE): файлы коммита — индекс, «команда сама всё добавит» не бывает. Подсказка — в stderr. На PreToolUse
# страж молчит, если в репозитории папки сессии ловушка стоит.
TRAP=0
if [ "${1:-}" = "--commit-msg" ]; then
    TRAP=1; COMMAND=""; SID=""
    CWD=$(project_git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || exit 0   # git зовёт ловушку в корне дерева коммита
else
    INPUT=$(cat)
    [ -z "$INPUT" ] && exit 0
    TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
    [ "$TOOL_NAME" = "Bash" ] || exit 0
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    is_git_commit "$COMMAND" || exit 0
    # cwd из payload, не из окружения процесса — тот же баг чинился в
    # claude-md-size-check (v1.12.4), сюда фикс не доходил до аудита 2026-08-08.
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
    # Каталог КОММИТА — у разбора команды (`cd` и `-C`), а не папка сессии (D1279); не ответил — папка сессии.
    _CD=$(executable_commit_dir "$CWD" "$COMMAND") && CWD="$_CD"
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
fi
_say() {   # подсказка: additionalContext на PreToolUse, stderr в ловушке (агент видит его в выводе команды)
    if [ "$TRAP" -eq 1 ]; then printf '%s\n' "$1" >&2
    else jq -cn --arg m "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'; fi
}
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$TRAP" -eq 0 ] && command -v project_commit_trap >/dev/null 2>&1 && project_commit_trap "$ROOT" commit-msg "$COMMAND" && exit 0

# Конвенция opt-in: проект без CHANGELOG.md напоминаниями не пилится.
[ -f "$ROOT/CHANGELOG.md" ] || exit 0

# Staged-файлы (если не в git-репо или нет staged — выходим тихо).
STAGED=$(project_git -C "$CWD" diff --cached --name-only 2>/dev/null) || exit 0
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
   grep -qxE 'CHANGELOG\.md' <<< "$(project_git -C "$CWD" diff --name-only 2>/dev/null)"; then
    CHANGELOG_TOUCHED="CHANGELOG.md"
fi
[ -n "$CHANGELOG_TOUCHED" ] && exit 0

# Есть ли реальный КОД? По расширению, не по дереву ClaudSoul (переносимость,
# аудит 2026-08-08); tests и документация не считаются.
# ПЕРЕЧЕНЬ РАСШИРЕНИЙ — У ВЛАДЕЛЬЦА (25 сентября 2026, D480). Здесь стояла своя копия, и она
# разошлась с соседней молча: `prisma` в ней не было, а `root-cause-lib.sh` держал третью, из
# четырёх расширений. Владелец один — `token_code_ext_re` в `hooks/portable-lib.sh`; его
# отсутствие называется вслух, а не гасит напоминание молча (это был бы род B).
_CLR_PORTABLE="${_CLR_PORTABLE:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
[ -f "$_CLR_PORTABLE" ] || _CLR_PORTABLE="$HOME/.claude/hooks/portable-lib.sh"
# shellcheck source=/dev/null
[ -f "$_CLR_PORTABLE" ] && . "$_CLR_PORTABLE" 2>/dev/null
if ! command -v token_code_ext_re >/dev/null 2>&1; then
    _say "📝 CHANGELOG НЕ ПРОВЕРЕН: нет token_code_ext_re (искал ${_CLR_PORTABLE}) — перечень расширений кода спросить не у кого."
    exit 0
fi
CODE=$(printf '%s\n' "$STAGED" | grep -vE '(^|/)tests?/' \
    | grep -E '\.('"$(token_code_ext_re)"')$' || true)
[ -z "$CODE" ] && exit 0

# Per-session throttle по набору staged-кода (тот же diff не напоминаем дважды).
KEY=$(printf '%s' "$CODE" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/changelog-reminder-${SID}.txt"
if [ "$TRAP" -eq 0 ]; then
    if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi
    printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null
fi

MSG="📝 CHANGELOG: в staged есть изменения кода, но CHANGELOG.md не добавлен. Если это содержательное изменение — добавь запись в [Unreleased] (правило «каждое изменение → CHANGELOG»). Если это рефактор/чор без пользовательского эффекта — игнорируй."
_say "$MSG"
exit 0
