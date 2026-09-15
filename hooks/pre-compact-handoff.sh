#!/usr/bin/env bash
# pre-compact-handoff.sh — PreCompact: сохранить нить работы перед сжатием контекста.
# en: PreCompact: preserves the thread of work before context compaction.
#
# Purpose:
#   Компактация (авто при заполнении окна ИЛИ ручная /compact) заменяет историю
#   на summary — детали теряются. SessionStart на компакт НЕ срабатывает (сессия
#   та же), поэтому авто-инжект "LAST SESSION CONTEXT" не повторяется. Этот хук:
#     1. снимает снапшот SESSION.md проекта в $STATE_DIR/handoff-snapshots/ (артефакт
#        переживает сжатие гарантированно), хранит последние 20;
#     2. возвращает additionalContext — напоминание после сжатия перечитать
#        SESSION.md (актуальное состояние + next steps), а не доверять только summary.
#
#   Качественный бриф пишет АГЕНТ (скилл /передача или /save) — shell-хук модель
#   думать не заставит; его роль — гарантировать сохранность и напомнить.
#
# Input:  JSON на stdin (session_id, trigger=manual|auto, cwd).
# Output: JSON hookSpecificOutput с additionalContext (best-effort) — НИКОГДА не
#         блокирует компактацию. Silent-degrade при отсутствии jq/SESSION.md.

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# Корень проекта: paths-lib, иначе walk-up до SESSION.md / CLAUDE.md / .git.
ROOT="$CWD"
if command -v find_project_root >/dev/null 2>&1; then
    ROOT=$(find_project_root "$CWD" 2>/dev/null || echo "$CWD")
else
    d="$CWD"
    while [ "$d" != "/" ]; do
        if [ -f "$d/SESSION.md" ] || [ -f "$d/CLAUDE.md" ] || [ -d "$d/.git" ]; then ROOT="$d"; break; fi
        d=$(dirname "$d")
    done
fi

SESSION_FILE="$ROOT/SESSION.md"
[ -f "$SESSION_FILE" ] || exit 0

# Снапшот в ГЛОБАЛЬНЫЙ эфемерный каталог (не в git проекта).
SNAP_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}/handoff-snapshots"
PROJ=$(basename "$ROOT" 2>/dev/null | tr ' /' '__' || echo "proj")
TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "snapshot")
SNAP="$SNAP_DIR/${PROJ}-precompact-$TS.md"
mkdir -p "$SNAP_DIR" 2>/dev/null || true
cp "$SESSION_FILE" "$SNAP" 2>/dev/null || true
# Автоочистка: оставить последние 20 снапшотов этого проекта.
ls -t "$SNAP_DIR/${PROJ}-precompact-"*.md 2>/dev/null | tail -n +21 | while read -r old; do rm -f "$old" 2>/dev/null || true; done

MSG="Контекст сжимается (PreCompact, trigger=${TRIGGER}). Нить работы зафиксирована в ${SESSION_FILE} (снапшот: ${SNAP}). После сжатия ПРОЧИТАЙ SESSION.md — актуальное состояние и next steps — прежде чем продолжать; не полагайся только на summary компактации."

# additionalContext — best-effort; если поле не поддерживается, безвредно игнорируется.
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreCompact",additionalContext:$m}}' 2>/dev/null || true
exit 0
