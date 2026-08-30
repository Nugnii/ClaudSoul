#!/usr/bin/env bash
# module-doc-check.sh — PreToolUse[Bash] на `git commit`: новый модуль в staged без модульного дока — тихое напоминание завести .claude-docs/modules/<имя>.md.
# en: PreToolUse[Bash] on `git commit`: a NEW module staged without its module doc — quiet reminder.
#
# Механизирует правило «новый модуль → документация модуля» (Documentation rules;
# правило существовало текстом и не исполнилось ни разу: к 2026-08-07 в проекте
# был 41 хук и ноль модульных доков — конвенция заведена этим же днём по поправке
# собеседника). Сигнал выражен правилом о САМОМ ФАЙЛЕ, а не о его месте: НОВЫЙ
# (статус A) исходник проекта, не тест, не библиотека, не шаблон, не конфиг публикации
# (scripts/publish/) — это модуль;
# правки существующих не триггерят.
# Silent (additionalContext), не блокирует — агент решает.
#
# Input  (stdin): {tool_name, tool_input, session_id} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{...}} или пусто
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

# cwd из payload (баг «git diff из окружения процесса», аудит 2026-08-08);
# конвенция opt-in: без .claude-docs/modules/ в репозитории хук не действует.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$ROOT/.claude-docs/modules" ] || exit 0

# Новые (A) файлы-модули в staged. Модуль задан ПРАВИЛОМ о самом файле, не местом:
# исходник (sh/py) минус тесты, библиотеки, шаблоны и конфиг публикации. До 28 августа
# 2026 здесь стоял перечень мест (`^hooks/[^/]+\.sh$`) — маска, снятая с тогдашнего
# состава дерева, когда все механизмы жили в одной папке. Как только механизмы завелись
# в `scripts/`, страж замолчал на целом классе, и молчание читалось как «всё описано».
# Другой проект задаёт свои формы через MODULE_DOC_PATTERN / MODULE_DOC_EXCLUDE.
# КОНТРПРИМЕР: механизм, который не является файлом .sh/.py — скилл (`SKILL.md`),
# конфигурация поведения (`scripts/ablation/core/settings.json`), узел домена — не
# сработает, и это известно: их носители другие. Не сработает и переименование
# существующего файла в новый механизм: у него статус R, а не A.
MODULE_DOC_PATTERN="${MODULE_DOC_PATTERN:-\.(sh|py)$}"
MODULE_DOC_EXCLUDE="${MODULE_DOC_EXCLUDE:-(^|/)tests?/|-lib\.sh$|^templates/|^scripts/publish/}"
NEW_MODULES=$(git -C "$CWD" diff --cached --name-status 2>/dev/null \
    | awk -v pat="$MODULE_DOC_PATTERN" -v exc="$MODULE_DOC_EXCLUDE" \
        '$1 == "A" && $2 ~ pat && $2 !~ exc { print $2 }') || exit 0
[ -z "$NEW_MODULES" ] && exit 0

# Модульные доки в том же staged → напоминать не о чем.
grep -q '^\.claude-docs/modules/' <<< "$(git -C "$CWD" diff --cached --name-only 2>/dev/null)" && exit 0

# Per-session throttle по набору новых модулей.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
KEY=$(printf '%s' "$NEW_MODULES" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/module-doc-check-${SID}.txt"
if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi
printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null

LIST=$(printf '%s' "$NEW_MODULES" | awk 'BEGIN{ORS=""} NR>1{printf ", "} {printf "%s", $0}')
MSG="📦 Модульный док: в staged новые модули (${LIST}), а .claude-docs/modules/ не тронут. Правило «новый модуль → его док в том же коммите»: назначение, файлы, зависимости, правила. Если файл — не модуль (вспомогательный скрипт одного механизма, док уже покрывает) — игнорируй."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
