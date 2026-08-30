#!/usr/bin/env bash
# internal-doc-leak-guard.sh — PreToolUse: prevent writing internally-marked content to externally-shared paths (lawyer / counsel / advisor folders).
#
# Failure mode from a document-handling session: переведённый текст содержал inline
# notes «Для адвоката:», бюджеты и TODO; был перемещён в папку получателя целиком.
# Receiver получил черновые заметки и budget brief, не согласованные для передачи.
#
# Detection rules (AND): destination path matches external-share pattern
#                       + content contains internal-only marker
#
# External-share patterns (case-insensitive, configurable):
#   lawyer | adwokat | counsel | radca | attorney | Lawyer_Track | Korespondencja
#
# Internal-only markers (case-insensitive):
#   «Для адвоката:», «Для клиента:», «Для меня:» (annotation patterns)
#   TODO, FIXME, XXX, HACK (developer-style draft markers)
#   draft, черновик, internal only, не отправлять
#   D&O (доменный маркер — собеседник сказал «никто не просит», но
#        переживает в шаблонах)
#
# Matcher: Edit | Write (file content available in tool_input).
# For Bash cp/mv into external-share folders — separate signal (no content access
# from input alone, would need to read source file). Skipped first iteration.
#
# Throttle: per (destination + first-matched-marker) per session.
# Auth scan: «отправь как есть», «пусть с заметками», «согласовано целиком».

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


STATE_DIR="${STATE_DIR:-${INTERNAL_DOC_STATE_DIR:-$HOME/.claude/hooks/state}}"
AUTH_SCAN_WINDOW="${INTERNAL_DOC_AUTH_WINDOW:-4}"

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# --- Detect external-share destination ---
# Настраиваемо (обещание шапки, исполнено по аудиту 2026-08-08): словарь
# адресатов — через INTERNAL_DOC_LEAK_REGEX; default — словарь владельца.
# КОНТРПРИМЕР: внешний адресат, названный иначе — «нотариус», «бухгалтер», имя фирмы без
# слова-роли, латиницей с опечаткой — не опознаётся. Признак ловит РОЛЬ по словарю, а не
# внешность адресата как таковую; полного словаря ролей не существует, и перечень
# дополняется встреченными случаями.
EXTERNAL_REGEX="${INTERNAL_DOC_LEAK_REGEX:-([Ll]awyer|[Aa]dwokat|[Cc]ounsel|[Rr]adca|[Aa]ttorney|Lawyer_Track|Korespondencja|advisor|Адвокат|Юрист)}"
grep -qE "$EXTERNAL_REGEX" <<< "$FILE_PATH" || exit 0

# --- Extract content to scan ---
# Edit: new_string is the new content; Write: content is the full file.
CONTENT=""
if [ "$TOOL_NAME" = "Edit" ]; then
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
else
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null)
fi
[ -z "$CONTENT" ] && exit 0

# --- Match internal markers ---
MATCHED_MARKER=""

check_marker() {
    local needle="$1"
    if grep -Fqi -- "$needle" <<< "$CONTENT"; then
        MATCHED_MARKER="$needle"
        return 0
    fi
    return 1
}

check_marker "Для адвоката:" \
    || check_marker "Для клиента:" \
    || check_marker "Для меня:" \
    || check_marker "Для адвокатa:" \
    || check_marker "TODO:" \
    || check_marker "FIXME" \
    || check_marker "XXX:" \
    || check_marker "HACK:" \
    || check_marker "draft" \
    || check_marker "черновик" \
    || check_marker "не отправлять" \
    || check_marker "internal only" \
    || check_marker "D&O" \
    || exit 0

# --- Auth scan: user explicitly says «отправь как есть», «целиком», etc. ---
has_auth=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_USER_TEXTS=$(jq -r '
        select(.type == "user")
        | .message.content // []
        | map(select(.type == "text") | .text)
        | .[]?
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -"$AUTH_SCAN_WINDOW")

    if [ -n "$LAST_USER_TEXTS" ]; then
        AUTH_TOKENS='отправ[ьи][[:space:]]+как[[:space:]]+есть|с[[:space:]]+заметками|с[[:space:]]+черновиком|целиком|согласовано|send[[:space:]]+as[[:space:]]+is|approved[[:space:]]+with[[:space:]]+notes'
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
        if grep -qE "($AUTH_TOKENS)" <<< "$USER_LOWER"; then
            has_auth=1
        fi
    fi
fi

[ "$has_auth" = "1" ] && exit 0

# --- Throttle ---
hash_value() {
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$1" | md5
    else
        printf '%s' "$1" | cksum | awk '{print $1}'
    fi
}

THROTTLE_KEY=$(hash_value "${FILE_PATH}|${MATCHED_MARKER}")
THROTTLE_FILE="$STATE_DIR/internal-doc-leak-fired-${SESSION_ID}.jsonl"
if [ -f "$THROTTLE_FILE" ] && grep -Fq "\"hash\":\"$THROTTLE_KEY\"" "$THROTTLE_FILE" 2>/dev/null; then
    exit 0
fi
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"date":"%s","hash":"%s","path":"%s","marker":"%s"}\n' \
    "$NOW" "$THROTTLE_KEY" "$FILE_PATH" "$MATCHED_MARKER" >> "$THROTTLE_FILE"

# --- Emit permissionDecision:ask ---
REASON=$(printf '📤 Internal-doc leak guard: запись в external-share путь (%s) с маркером внутренней заметки «%s».\nПрецедент: документ с inline-комментариями «Для адвоката:» и budget brief был передан получателю целиком.\nПеред передачей — удали internal markers, либо явно подтверди «отправь как есть».' \
    "$FILE_PATH" "$MATCHED_MARKER")

jq -n --arg ctx "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $ctx
    }
}'

exit 0
