#!/usr/bin/env bash
# claude-md-merge.sh — sourceable lib для marker-based merge ~/.claude/CLAUDE.md.
# Extracted from install.sh в v1.7.4 для тестируемости.
#
# Public function: sync_claude_md TARGET_FILE MASTER_FILE
#   - TARGET_FILE: путь к deployed файлу (создаётся если отсутствует)
#   - MASTER_FILE: путь к репозиторному master rules/CLAUDE.md
# Returns 0 на успех, ненулевой при отсутствии MASTER_FILE.
#
# 4 случая:
#   1. Маркеры присутствуют в TARGET — заменить только содержимое между ними.
#   2. Маркеров нет, TARGET содержит "Self-Learning" — legacy, переписать целиком с маркерами.
#   3. Маркеров нет, TARGET без признаков ClaudSoul — добавить блок в конец.
#   4. TARGET не существует — создать с маркерами.
#
# Каждое изменение оставляет бэкап TARGET.bak.YYYYMMDDHHMMSS (кроме случая 4).

CLAUDE_MD_MARKER_START="<!-- ClaudSoul: managed-start (install.sh синхронизирует область между маркерами; правки внутри будут перезаписаны при следующей установке) -->"
CLAUDE_MD_MARKER_END="<!-- ClaudSoul: managed-end -->"

# Замок на ЦЕЛИ (род H, D376). Слияние читает target через head/tail, пишет во временный и
# кладёт обратно — окно read→write. Своих писателей у ~/.claude/CLAUDE.md двое (install.sh и
# scripts/sync-drifted.sh зовут эту же функцию), и до 13 сентября 2026 их не сериализовало
# ничто. Замок — общий `hooks/state-lock-lib.sh` (mkdir <файл>.lock), а не своя реализация;
# единица блокировки — ФАЙЛ, поэтому ключ — путь цели. Библиотеки нет — слияние идёт без
# замка и ГОВОРИТ об этом в stderr: молчание тут читалось бы как «под замком».
_CM_LOCK_LIB="${STATE_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../hooks" 2>/dev/null && pwd)/state-lock-lib.sh}"
[ -f "$_CM_LOCK_LIB" ] || _CM_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
if [ -f "$_CM_LOCK_LIB" ]; then . "$_CM_LOCK_LIB"; fi

sync_claude_md() {
    if command -v with_lock >/dev/null 2>&1; then
        with_lock "$1" _cm_sync_unlocked "$@"
    else
        echo "sync_claude_md: state-lock-lib не найдена ($_CM_LOCK_LIB) — слияние идёт БЕЗ замка" >&2
        _cm_sync_unlocked "$@"
    fi
}

_cm_write_managed_block() {
    local master="$1"
    printf '%s\n' "$CLAUDE_MD_MARKER_START"
    cat "$master"
    printf '\n%s\n' "$CLAUDE_MD_MARKER_END"
}

_cm_sync_unlocked() {
    local target="$1"
    local master="$2"

    if [ ! -f "$master" ]; then
        echo "sync_claude_md: master file not found: $master" >&2
        return 1
    fi

    if [ -f "$target" ]; then
        if grep -qF "$CLAUDE_MD_MARKER_START" "$target" 2>/dev/null && \
           grep -qF "$CLAUDE_MD_MARKER_END" "$target" 2>/dev/null; then
            # Случай 1: маркеры есть → заменить между ними.
            cp "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
            local start_line end_line tmp
            start_line=$(grep -n -F "$CLAUDE_MD_MARKER_START" "$target" | head -1 | cut -d: -f1)
            end_line=$(grep -n -F "$CLAUDE_MD_MARKER_END" "$target" | head -1 | cut -d: -f1)
            tmp=$(mktemp)
            {
                if [ "$start_line" -gt 1 ]; then
                    head -n $((start_line - 1)) "$target"
                fi
                _cm_write_managed_block "$master"
                tail -n +"$((end_line + 1))" "$target"
            } > "$tmp"
            mv "$tmp" "$target"
            return 0
        fi

        cp "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
        if grep -q "Self-Learning" "$target" 2>/dev/null; then
            # Случай 2: legacy ClaudSoul install (без маркеров) → переписать с маркерами.
            _cm_write_managed_block "$master" > "$target"
            return 0
        fi

        # Случай 3: пользовательское содержимое → добавить блок в конец.
        {
            cat "$target"
            printf '\n'
            _cm_write_managed_block "$master"
        } > "${target}.tmp"
        mv "${target}.tmp" "$target"
        return 0
    fi

    # Случай 4: первая установка → master в маркерах.
    _cm_write_managed_block "$master" > "$target"
    return 0
}
