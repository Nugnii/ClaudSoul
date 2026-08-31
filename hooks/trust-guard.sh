#!/usr/bin/env bash
# trust-guard.sh — PreToolUse: разрушительная команда без явного разрешения собеседника в последних репликах останавливается вопросом (аффект-протез №1: тормоза, которого в архитектуре нет).
# en: PreToolUse: a destructive command issued without explicit user authorization in the recent turns is met with a question first (affect prosthetic #1 — the brake the architecture does not have).
#
# Closes Разрыв A (functionally, not architecturally): в symbol-only архитектуре
# нет affective brake на разрушение доверия. Текстовое правило «будь осторожен»
# не восстанавливает функцию — полагается на memory-as-resource.
# Инженерный протез: detection signals + inject в моменте действия.
#
# Contract:
#   Input  (stdin): {session_id, transcript_path, tool_name, tool_input, cwd}
#   Output (stdout): {hookSpecificOutput: {hookEventName, additionalContext}} или пусто
#   Exit:  always 0 (degrade gracefully)
#
# Silent by design: additionalContext, не banner. Не блокирует — агент решает.
# Consistent с blocker-tier-check паттерном.
#
# Throttle: state/trust-guard-fired-<SID>.jsonl — per-session, ключ = md5(signature+target).
# Один и тот же destructive + target даёт marker один раз за сессию.
#
# Detection signatures:
#   rm -rf / rm -fr / rm --recursive --force
#   git reset --hard
#   git push --force / git push -f / git push --force-with-lease
#   git branch -D
#   git checkout -- <paths> (discards uncommitted changes)
#   git clean -f / git clean -fd / git clean -xfd
#   rm -f / | rm -f ~ | rm -f $HOME (explicit destructive path)
#
# Auth scan: last N user text messages (type=text, not tool_result) for
# authorization tokens + target substring match.

set -uo pipefail

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


PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
AUTH_SCAN_WINDOW="${TRUST_GUARD_AUTH_WINDOW:-4}"

# Сужение области поиска до исполняемой части команды (single source — command-scope-lib.sh).
SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    executable_part() { printf '%s' "${1:-}"; }
fi

# Shared hash helper (single source — see hash-lib.sh).
HASH_LIB="${HASH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash-lib.sh}"
if [ -f "$HASH_LIB" ]; then
    # shellcheck source=/dev/null
    source "$HASH_LIB"
else
    echo "Missing hash-lib.sh: $HASH_LIB" >&2; exit 1
fi

# Shared per-session throttle (single source — see throttle-lib.sh).
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
if [ -f "$THROTTLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$THROTTLE_LIB"
else
    echo "Missing throttle-lib.sh: $THROTTLE_LIB" >&2; exit 1
fi

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# --- Detection: match destructive signature in command ---
# Returns signature name + primary target (first non-flag argument, if any).

SIGNATURE=""
TARGET=""

match_signature() {
    local cmd="$1"
    local norm exec_norm
    # Цель действия берётся из ИСХОДНОЙ строки: в `rm -rf "$T"` цель внутри кавычек.
    norm=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')
    # Сигнатура ищется только в исполняемой части: восемь ложных срабатываний за сессию
    # пришли из шаблонов grep и тел heredoc, где `rm -rf` — текст, а не действие.
    exec_norm=$(executable_part "$cmd" | tr -s '[:space:]' ' ')

    # rm -rf / rm -fr / rm -Rf / rm --recursive --force
    if grep -qE '(^|[[:space:];&|])rm[[:space:]]+(-[rRfv]*[rR][rRfv]*[fF][rRfv]*|-[fF][rRfv]*[rR]|--recursive.*--force|--force.*--recursive|-r[[:space:]]+-f|-f[[:space:]]+-r)' <<< "$exec_norm"; then
        SIGNATURE="rm -rf"
        TARGET=$(echo "$norm" | sed -nE 's/.*rm[[:space:]]+(-[-a-zA-Z]+[[:space:]]+)+([^[:space:]]+).*/\2/p' | head -1)
        return 0
    fi

    if grep -qE '(^|[[:space:];&|`])git[[:space:]]+reset[[:space:]]+--hard' <<< "$exec_norm"; then
        SIGNATURE="git reset --hard"
        TARGET=$(echo "$norm" | sed -nE 's/.*git[[:space:]]+reset[[:space:]]+--hard[[:space:]]*([^[:space:];&|]*).*/\1/p' | head -1)
        [ -z "$TARGET" ] && TARGET="HEAD"
        return 0
    fi

    if grep -qE '(^|[[:space:];&|`])git[[:space:]]+push[[:space:]]+.*(-f($|[[:space:]])|--force)' <<< "$exec_norm"; then
        SIGNATURE="git push --force"
        TARGET=$(echo "$norm" | sed -nE 's/.*git[[:space:]]+push[[:space:]]+[^[:space:]]*[[:space:]]+([^[:space:];&|-][^[:space:];&|]*)[[:space:]]+([^[:space:];&|-][^[:space:];&|]*).*/\2/p' | head -1)
        [ -z "$TARGET" ] && TARGET=$(echo "$norm" | sed -nE 's/.*git[[:space:]]+push[[:space:]]+([^[:space:]-][^[:space:];&|]*).*/\1/p' | head -1)
        [ -z "$TARGET" ] && TARGET="remote"
        return 0
    fi

    if grep -qE '(^|[[:space:];&|`])git[[:space:]]+branch[[:space:]]+-D([[:space:]]|$)' <<< "$exec_norm"; then
        SIGNATURE="git branch -D"
        TARGET=$(echo "$norm" | sed -nE 's/.*git[[:space:]]+branch[[:space:]]+-D[[:space:]]+([^[:space:];&|]+).*/\1/p' | head -1)
        return 0
    fi

    if grep -qE '(^|[[:space:];&|`])git[[:space:]]+checkout[[:space:]]+--[[:space:]]' <<< "$exec_norm"; then
        SIGNATURE="git checkout --"
        TARGET=$(echo "$norm" | sed -nE 's/.*git[[:space:]]+checkout[[:space:]]+--[[:space:]]+([^[:space:];&|]+).*/\1/p' | head -1)
        return 0
    fi

    # git restore <path> сбрасывает незакоммиченные правки, как checkout --; только --staged/-S
    # снимает с индекса и правок не трогает — если не добавлен --worktree/-W.
    if grep -qE '(^|[[:space:];&|`])git[[:space:]]+restore([[:space:]]|$)' <<< "$exec_norm"; then
        local rargs
        rargs=$(sed -nE 's/.*git[[:space:]]+restore[[:space:]]*([^;&|`]*).*/\1/p' <<< "$exec_norm" | head -1)
        if ! grep -qE '(^|[[:space:]])(--staged|-S)([[:space:]]|$)' <<< "$rargs" \
           || grep -qE '(^|[[:space:]])(--worktree|-W)([[:space:]]|$)' <<< "$rargs"; then
            SIGNATURE="git restore"
            TARGET=$(printf '%s\n' "$rargs" | tr ' ' '\n' | grep -vE '^(-|$)' | head -1)
            [ -z "$TARGET" ] && TARGET="working_tree"
            return 0
        fi
    fi

    if grep -qE '(^|[[:space:];&|`])git[[:space:]]+clean[[:space:]]+[-a-zA-Z]*f' <<< "$exec_norm"; then
        SIGNATURE="git clean -f"
        TARGET="working_tree"
        return 0
    fi

    # rm with explicit destructive paths + -f (system paths / home)
    if grep -qE '(^|[[:space:];&|])rm[[:space:]]+-[fF][[:space:]]+(/|~|\$HOME)' <<< "$exec_norm"; then
        SIGNATURE="rm destructive-path"
        TARGET=$(echo "$norm" | sed -nE 's/.*rm[[:space:]]+-[fF][[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
        return 0
    fi

    return 1
}

match_signature "$COMMAND" || exit 0

# --- Auth scan: last N user text messages for auth tokens + target match ---

has_auth=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract last N user text messages (type=user, message.content[].type=text)
    # Skip tool_result entries (tool outputs appear as user role in transcript).
    LAST_USER_TEXTS=$(jq -r '
        select(.type == "user")
        | .message.content // []
        | map(select(.type == "text") | .text)
        | .[]?
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -"$AUTH_SCAN_WINDOW")

    if [ -n "$LAST_USER_TEXTS" ]; then
        AUTH_TOKENS='удали|снеси|сотри|сноси|уничтож|прибей|очисти|чисти|force[- ]?push|форс[- ]?пуш|reset[[:space:]]+hard|сброс|откати|да,[[:space:]]*снос|да,[[:space:]]*удал|delete|remove|wipe|discard|force|trash|[пc]нос'

# Отсев чужой речи (D88, применено 2026-08-28). Словарь применяется к речи собеседника,
# а в неё попадают цитаты, пересылки и вставленные документы — они дают срабатывания на
# тексте, которого собеседник не писал. Замер по корпусу: отсев меняет 30 реплик из 107,
# полностью обнуляет 1 — то есть примерно раз на сотню хук ослепнет на настоящей реплике.
# Цена принята: у user-correction-guard замер D88 дал 96 срабатываний вне цитат.
INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hook-input-lib.sh}"
[ -f "$INPUT_LIB" ] || INPUT_LIB="$HOME/.claude/hooks/hook-input-lib.sh"
# shellcheck source=/dev/null
[ -f "$INPUT_LIB" ] && . "$INPUT_LIB"
own_speech_of() {   # текст собеседника без чужого; без библиотеки — как было
    if command -v user_own_speech >/dev/null 2>&1; then user_own_speech "${1:-}"; else printf %s "${1:-}"; fi
}
        USER_LOWER=$(to_lower "$(own_speech_of "$LAST_USER_TEXTS")")

        # Target match: any basename of TARGET in user text.
        # If TARGET is a path, use basename; if branch/HEAD — use as-is.
        target_base=$(basename "$TARGET" 2>/dev/null || echo "$TARGET")

        if grep -qE "($AUTH_TOKENS)" <<< "$USER_LOWER"; then
            # Auth token present. Check target reference OR generic consent
            # ("да, снеси всё" without target name is acceptable consent).
            generic_consent=$(echo "$USER_LOWER" | grep -cE "(да,[[:space:]]*(снес|удал|сброс|очист|force|reset|дава))" || true)
            if [ -n "$target_base" ] && grep -Fqi "$target_base" <<< "$USER_LOWER"; then
                has_auth=1
            elif [ "$generic_consent" -gt 0 ]; then
                has_auth=1
            elif [ "$TARGET" = "HEAD" ] || [ "$TARGET" = "working_tree" ] || [ "$TARGET" = "remote" ]; then
                # Implicit targets — strong auth verb alone is enough if verb matches action
                if grep -qE "(reset[[:space:]]+hard|force[- ]?push|форс[- ]?пуш|сброс|откати|clean|очисти)" <<< "$USER_LOWER"; then
                    has_auth=1
                fi
            fi
        fi
    fi
fi

[ "$has_auth" = "1" ] && exit 0

# --- Throttle per session by md5(signature+target) ---

# hash_value() — из общего hash-lib.sh (источается в bootstrap выше)

THROTTLE_KEY=$(hash_value "${SIGNATURE}|${TARGET}")
THROTTLE_FILE=$(throttle_file "$STATE_DIR" trust-guard "$SESSION_ID")
if throttle_seen "$THROTTLE_FILE" "$THROTTLE_KEY"; then
    exit 0
fi
throttle_mark "$THROTTLE_FILE" "$THROTTLE_KEY" \
    "$(printf '"signature":"%s","target":"%s"' "$SIGNATURE" "$TARGET")"

# --- Emit silent marker ---

TARGET_DISPLAY="$TARGET"
[ -z "$TARGET_DISPLAY" ] && TARGET_DISPLAY="(не распознано)"

# Исход назван действием, исполнимым БЕЗ разрешения (D111). Прежний текст говорил только
# «переспроси» — то есть требовал ровно того разрешения, отсутствие которого и есть повод
# срабатывания. Предписание, чей единственный выход упирается в недостающее условие,
# исполнить нельзя: ход кончается ничем, и находка теряется.
CONTEXT=$(printf '🛡️ Trust-guard: %s (target: %s) без явного подтверждения собеседника в последних %s сообщениях.\nЭто affect prosthetic (см. principle-affect-as-engineering.md): тормоз, которого нет архитектурно.\n\nЧто делать вместо — исполнимо без разрешения:\n  · показать, что именно затронет вызов: сухой прогон (`--dry-run`, `git status`, `ls` цели) и число — «удалит N файлов, вот они»;\n  · сделать обратимую часть работы, разрушительную оставить последней;\n  · назвать план одной строкой и спросить «приступать?» — ПОСЛЕ показанного числа, а не вместо него.\nОдно «переспроси» исходом не является: разрешения нет ровно в тот момент, когда страж сработал.' \
    "$SIGNATURE" "$TARGET_DISPLAY" "$AUTH_SCAN_WINDOW")

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0
