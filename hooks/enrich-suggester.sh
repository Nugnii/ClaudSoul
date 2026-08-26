#!/usr/bin/env bash
# enrich-suggester.sh — UserPromptSubmit hint при наличии recently-modified sparse entity.
# en: UserPromptSubmit: hint when a recently-modified entity is sparse (fewer than 3 attributes).
#
# v1.5.7 — второй C-класс tier 2 скилл (/enrich) из docs/skill-triggers-audit.md.
# Закрывает knowledge-action gap: `/enrich` manual-first. После `/ingest`
# на sparse entity (0-2 attributes) агент должен помнить вызвать `/enrich` —
# хрупкий memory-as-resource. Хук механически scan'ит недавно изменённые
# entity-*.md с `attributes:` count < ENRICH_SPARSE_THRESHOLD и инжектит hint.
#
# Contract:
#   Input  (stdin): {session_id, cwd, prompt, ...} (UserPromptSubmit JSON)
#   Output (stdout): {hookSpecificOutput: {hookEventName, additionalContext}} или пусто
#   Exit:  always 0 (degrade gracefully)
#
# Silent by design (feedback_silent_correct_decisions.md): additionalContext, не banner.
#
# Throttle: state/enrich-suggester-fired-<SID>.jsonl — per-session, ключ = md5(sparse-set).
# Тот же набор sparse entity не fired дважды; новый или изменённый — новый fire.

set -uo pipefail

STATE_DIR="${STATE_DIR:-${ENRICH_SUGGESTER_STATE_DIR:-$HOME/.claude/hooks/state}}"

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; fi

# Shared per-session throttle (single source — see throttle-lib.sh).
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
if [ -f "$THROTTLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$THROTTLE_LIB"
else
    echo "Missing throttle-lib.sh: $THROTTLE_LIB" >&2; exit 1
fi

# Shared hash helper (single source — see hash-lib.sh).
HASH_LIB="${HASH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash-lib.sh}"
if [ -f "$HASH_LIB" ]; then
    # shellcheck source=/dev/null
    source "$HASH_LIB"
else
    echo "Missing hash-lib.sh: $HASH_LIB" >&2; exit 1
fi

# Shared BSD/GNU разводка (single source — see portable-lib.sh): здесь нужен file_mtime.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
else
    echo "Missing portable-lib.sh: $PORTABLE_LIB" >&2; exit 1
fi
GLOBAL_LESSONS="${GLOBAL_LESSONS:-$LESSONS_DIR}"
ENRICH_SPARSE_THRESHOLD="${ENRICH_SPARSE_THRESHOLD:-3}"
ENRICH_WINDOW_MINUTES="${ENRICH_WINDOW_MINUTES:-30}"

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

# Skip if user already mentioned /enrich in prompt
case "$PROMPT" in
    */enrich*|*обогати*|*enrich*) exit 0 ;;
esac

[ -d "$GLOBAL_LESSONS" ] || exit 0

# Count attributes in entity file by parsing YAML frontmatter.
# Handles:
#   attributes: {}            → 0
#   attributes:               → count indented child keys
#     key1: ...
#     key2: ...
#   next_top_level_key:       → stop counting
count_attrs() {
    local file="$1"
    awk '
        BEGIN { in_fm=0; fm_seen=0; in_attrs=0; count=0 }
        /^---[[:space:]]*$/ {
            if (fm_seen==0) { in_fm=1; fm_seen=1; next }
            else if (in_fm) { in_fm=0; exit }
        }
        in_fm && /^attributes:[[:space:]]*\{[[:space:]]*\}[[:space:]]*$/ { count=0; exit }
        in_fm && /^attributes:[[:space:]]*$/ { in_attrs=1; next }
        in_attrs && /^[a-zA-Z_]/ { in_attrs=0 }
        in_attrs && /^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_-]*:/ { count++ }
        END { print count+0 }
    ' "$file"
}

# entity_name from file: strip "entity-" prefix and ".md" suffix.
entity_slug() {
    local base="$1"
    base="${base#entity-}"
    base="${base%.md}"
    printf '%s' "$base"
}

# file_mtime() — из общего portable-lib.sh (источается в bootstrap выше).
# Здесь была своя копия с той же разводкой BSD/GNU: две копии условия расходятся при
# первой же правке, поэтому — единый источник, как с hash_value.

NOW_EPOCH=$(date +%s)
WINDOW_SECS=$((ENRICH_WINDOW_MINUTES * 60))
CUTOFF=$((NOW_EPOCH - WINDOW_SECS))

SPARSE=""
append_sparse() {
    local item="$1"
    if [ -z "$SPARSE" ]; then SPARSE="$item"
    else SPARSE="$SPARSE"$'\n'"$item"; fi
}

shopt -s nullglob
for path in "$GLOBAL_LESSONS"/entity-*.md; do
    mtime=$(file_mtime "$path")
    [ "$mtime" -ge "$CUTOFF" ] || continue
    base=$(basename "$path")
    attrs=$(count_attrs "$path")
    [ "$attrs" -lt "$ENRICH_SPARSE_THRESHOLD" ] || continue
    slug=$(entity_slug "$base")
    append_sparse "${slug}|${attrs}"
done
shopt -u nullglob

[ -z "$SPARSE" ] && exit 0

# Per-session throttle by hash of sparse-set.
# hash_value() — из общего hash-lib.sh (источается в bootstrap выше)

SPARSE_HASH=$(hash_value "$SPARSE")
THROTTLE_FILE=$(throttle_file "$STATE_DIR" enrich-suggester "$SESSION_ID")
if throttle_seen "$THROTTLE_FILE" "$SPARSE_HASH"; then
    exit 0
fi
throttle_mark "$THROTTLE_FILE" "$SPARSE_HASH"

ITEMS=$(printf '%s\n' "$SPARSE" | awk -F '|' 'NF==2 {printf "  • %s (%s attr)\n", $1, $2}')

CONTEXT=$(printf '📎 Sparse entity: недавно изменённые entity с < %s атрибутами:\n%s\nПравило: `/enrich` (C-класс tier 2) после `/ingest` — sparse entity = 0-2 атрибута требует обогащения источниками.\nЕсли entity только что создана из одного источника — это ожидаемо; если уже несколько раз mentioned — стоит добавить facts/attributes через `/enrich`.' \
    "$ENRICH_SPARSE_THRESHOLD" "$ITEMS")

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'

exit 0
