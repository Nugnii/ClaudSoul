#!/usr/bin/env bash
# bulk-copy-guard.sh — PreToolUse: ask user before bulk copy/move/rsync operations.
# en: PreToolUse guard: asks the user before bulk copy/move/rsync operations.
#
# Purpose: close the failure mode observed in a document-handling session —
# bulk-copying from a directory whose name suggests homogeneous content
# (Statements/) while actual content is heterogeneous (unrelated receipts mixed in).
# `verify-before-acting` принцип уже есть, но silent injection не помогает.
# Этот хук блокирует на уровне harness: permissionDecision:"ask" requires the
# agent to enumerate files OR get explicit auth.
#
# Contract:
#   Input  (stdin): {session_id, transcript_path, tool_name, tool_input, cwd}
#   Output (stdout): permissionDecision:"ask" JSON or empty
#   Exit:  always 0
#
# Detection: command matches bulk-copy signature.
#   - cp / mv with glob (/* /. wildcard)
#   - cp -r / cp -R / mv with -r (directory recursion)
#   - rsync -a / rsync -r
#   - find ... -exec cp ...
#
# Auth scan: last N user text messages contain «копируй всё», «клонируй папку»,
# «возьми все файлы», «move all», etc. (полный словарь — AUTH_TOKENS ниже)
# + reference to source dir basename.
#
# Throttle: per (signature, source, dest) per session.

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


STATE_DIR="${STATE_DIR:-${BULK_COPY_STATE_DIR:-$HOME/.claude/hooks/state}}"
AUTH_SCAN_WINDOW="${BULK_COPY_AUTH_WINDOW:-4}"

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

# --- Detection ---

SIGNATURE=""
SOURCE=""
DEST=""

match_bulk_signature() {
    local cmd="$1"
    local norm
    norm=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')

    # cp with glob source: cp src/* dst   |   cp src/. dst
    if grep -qE '(^|[[:space:];&|])(cp|mv)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^[:space:]]+/(\*|\.)[[:space:]]' <<< "$norm"; then
        SIGNATURE="bulk copy with glob"
        SOURCE=$(echo "$norm" | sed -nE 's|.*(cp\|mv)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*([^[:space:]]+/)(\*\|\.).*|\3|p' | head -1)
        DEST=$(echo "$norm" | sed -nE 's|.*(cp\|mv)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^[:space:]]+/(\*\|\.)[[:space:]]+([^[:space:];&|]+).*|\4|p' | head -1)
        return 0
    fi

    # cp -r / cp -R / mv -r: recursive directory copy
    if grep -qE '(^|[[:space:];&|])(cp|mv)[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]' <<< "$norm"; then
        SIGNATURE="recursive directory copy"
        # Last 2 non-flag args are source + dest
        SOURCE=$(echo "$norm" | awk '{for(i=1;i<=NF;i++) if($i !~ /^-/ && $i !~ /^(cp|mv)$/) print $i}' | tail -2 | head -1)
        DEST=$(echo "$norm" | awk '{for(i=1;i<=NF;i++) if($i !~ /^-/ && $i !~ /^(cp|mv)$/) print $i}' | tail -1)
        return 0
    fi

    # rsync with -a or -r
    if grep -qE '(^|[[:space:];&|])rsync[[:space:]]+(-[a-zA-Z]*[arR][a-zA-Z]*[[:space:]]|--archive|--recursive)' <<< "$norm"; then
        SIGNATURE="rsync archive/recursive"
        SOURCE=$(echo "$norm" | awk '{for(i=1;i<=NF;i++) if($i !~ /^-/ && $i != "rsync") print $i}' | tail -2 | head -1)
        DEST=$(echo "$norm" | awk '{for(i=1;i<=NF;i++) if($i !~ /^-/ && $i != "rsync") print $i}' | tail -1)
        return 0
    fi

    # find ... -exec cp/mv ...
    if grep -qE '(^|[[:space:];&|])find[[:space:]]+.*-exec[[:space:]]+(cp|mv)[[:space:]]' <<< "$norm"; then
        SIGNATURE="find -exec bulk operation"
        SOURCE=$(echo "$norm" | sed -nE 's|.*find[[:space:]]+([^[:space:]]+).*|\1|p' | head -1)
        DEST="(определяется find)"
        return 0
    fi

    return 1
}

match_bulk_signature "$COMMAND" || exit 0

# --- Auth scan ---

has_auth=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_USER_TEXTS=$(jq -r '
        select(.type == "user")
        | .message.content // []
        | map(select(.type == "text") | .text)
        | .[]?
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -"$AUTH_SCAN_WINDOW")

    if [ -n "$LAST_USER_TEXTS" ]; then
        AUTH_TOKENS='копируй[[:space:]]+всё|скопируй[[:space:]]+всё|возьми[[:space:]]+все|перенеси[[:space:]]+всё|перемести[[:space:]]+всё|copy[[:space:]]+all|move[[:space:]]+all|rsync|клонируй[[:space:]]+папк|синхронизируй|вся[[:space:]]+папка|целиком|массово'
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

        source_base=$(basename "$SOURCE" 2>/dev/null || echo "$SOURCE")

        if grep -qE "($AUTH_TOKENS)" <<< "$USER_LOWER"; then
            if [ -n "$source_base" ] && grep -Fqi "$source_base" <<< "$USER_LOWER"; then
                has_auth=1
            elif grep -qE "(копируй[[:space:]]+всё|скопируй[[:space:]]+всё|copy[[:space:]]+all|move[[:space:]]+all|целиком|массово)" <<< "$USER_LOWER"; then
                has_auth=1
            fi
        fi
    fi
fi

[ "$has_auth" = "1" ] && exit 0

# --- Throttle per session ---

hash_value() {
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$1" | md5
    else
        printf '%s' "$1" | cksum | awk '{print $1}'
    fi
}

THROTTLE_KEY=$(hash_value "${SIGNATURE}|${SOURCE}|${DEST}")
THROTTLE_FILE="$STATE_DIR/bulk-copy-fired-${SESSION_ID}.jsonl"
if [ -f "$THROTTLE_FILE" ] && grep -Fq "\"hash\":\"$THROTTLE_KEY\"" "$THROTTLE_FILE" 2>/dev/null; then
    exit 0
fi
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"date":"%s","hash":"%s","signature":"%s","source":"%s","dest":"%s"}\n' \
    "$NOW" "$THROTTLE_KEY" "$SIGNATURE" "$SOURCE" "$DEST" >> "$THROTTLE_FILE"

# --- Emit permissionDecision:ask ---

SOURCE_DISPLAY="${SOURCE:-(не распознан)}"
DEST_DISPLAY="${DEST:-(не распознан)}"

REASON=$(printf '📦 Bulk-copy guard: %s (source: %s → dest: %s) без явного подтверждения.\nИмя папки не гарантирует однородность содержимого (прецедент: Statements/ содержала посторонние квитанции).\nПеред массовым копированием — ls source, классифицируй по типу, копируй явно перечисленные файлы.' \
    "$SIGNATURE" "$SOURCE_DISPLAY" "$DEST_DISPLAY")

jq -n --arg ctx "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $ctx
    }
}'

exit 0
