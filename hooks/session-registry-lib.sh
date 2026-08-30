#!/usr/bin/env bash
# session-registry-lib.sh — Session Registry library for ClaudSoul
# Provides functions for managing session lifecycle across Claude Code sessions.
#
# Usage: source this file from other hooks:
#   source "$HOME/.claude/hooks/session-registry-lib.sh"
#
# Functions:
#   sr_register_session     — create active session record (call at session start)
#   sr_update_knowledge     — add knowledge delta to active session
#   sr_update_commits       — add commit info to active session
#   sr_add_note             — append a free-text note to active session
#   sr_finalize_session     — move active session to registry (call at session end)
#   sr_cleanup_stale        — remove orphaned active files (dead PID, ancestor PID, UUID older than 24h)
#   sr_get_startup_context  — build startup message from registry data
#   sr_detect_parallel      — check for other active sessions
#   sr_detect_interrupted   — find stale active sessions (likely interrupted)

# Разбор меток времени — из общего portable-lib.sh: ключ `date -j` есть только у BSD date
# (macOS), на Linux парсинг обязан идти через `date -d`.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
else
    # Библиотека не задеплоена рядом. `exit` здесь убил бы вызывающий хук (файл источается),
    # поэтому отдаём ноль — то же значение, что раньше давала ветка `|| echo 0`.
    iso_epoch() { echo 0; }
fi

# Directories
SR_SESSIONS_DIR="$HOME/.claude/sessions"
SR_ACTIVE_DIR="$SR_SESSIONS_DIR/active"
SR_REGISTRY="$SR_SESSIONS_DIR/registry.jsonl"
SR_LAST_SESSION="$SR_SESSIONS_DIR/last-session.json"

# Current session ID
# Priority: caller-provided SR_OVERRIDE_SESSION_ID (parsed from hook stdin payload)
#           > CLAUDE_CODE_SESSION_ID env > PPID fallback.
# Hooks should parse `.session_id` from their stdin JSON and export
# SR_OVERRIDE_SESSION_ID before sourcing this lib for stable identification.
SR_SESSION_ID="${SR_OVERRIDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-$PPID}}"

# Ensure directories exist
mkdir -p "$SR_ACTIVE_DIR"

# --- Helper: JSON escaping ---

_sr_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# --- Helper: detect project from CWD ---

_sr_detect_project() {
    local dir="${PWD}"
    # Walk up to find .git or CLAUDE.md
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

_sr_project_name() {
    basename "$(_sr_detect_project)"
}

# --- Register session ---

sr_register_session() {
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    # Don't re-register
    if [ -f "$active_file" ]; then
        return 0
    fi

    local project_path
    project_path="$(_sr_detect_project)"
    local project_name
    project_name="$(basename "$project_path")"
    local started_at
    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    cat > "$active_file" <<ENDJSON
{
  "session_id": "$SR_SESSION_ID",
  "project": "$(_sr_json_escape "$project_path")",
  "project_name": "$(_sr_json_escape "$project_name")",
  "started_at": "$started_at",
  "knowledge_delta": {
    "created": [],
    "updated": [],
    "confirmed": [],
    "contradicted": []
  },
  "commits": [],
  "files_changed": 0,
  "notes": []
}
ENDJSON
}

# --- Update knowledge delta ---
# Usage: sr_update_knowledge "created" "case-new-finding.md"
#    or: sr_update_knowledge "updated" "pattern-some.md"

sr_update_knowledge() {
    local action="$1"  # created | updated | confirmed | contradicted
    local filename="$2"
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    [ -f "$active_file" ] || return 0

    if command -v jq &>/dev/null; then
        local tmp="${active_file}.tmp"
        jq --arg action "$action" --arg file "$filename" \
            '.knowledge_delta[$action] += [$file] | .knowledge_delta[$action] |= unique' \
            "$active_file" > "$tmp" && mv "$tmp" "$active_file"
    fi
}

# --- Update commits ---
# Usage: sr_update_commits "abc1234"

sr_update_commits() {
    local commit_hash="$1"
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    [ -f "$active_file" ] || return 0

    if command -v jq &>/dev/null; then
        local tmp="${active_file}.tmp"
        jq --arg hash "$commit_hash" \
            '.commits += [$hash] | .commits |= unique' \
            "$active_file" > "$tmp" && mv "$tmp" "$active_file"
    fi
}

# --- Add note to session ---
# Usage: sr_add_note "Fixed grep set -e issue"

sr_add_note() {
    local note="$1"
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    [ -f "$active_file" ] || return 0

    if command -v jq &>/dev/null; then
        local tmp="${active_file}.tmp"
        jq --arg note "$note" \
            '.notes += [$note]' \
            "$active_file" > "$tmp" && mv "$tmp" "$active_file"
    fi
}

# --- Finalize session ---
# Moves active session to registry.jsonl + updates last-session.json
# Args: $1 = summary (optional, from session-collector)

sr_finalize_session() {
    local summary="${1:-}"
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    [ -f "$active_file" ] || return 0

    if ! command -v jq &>/dev/null; then
        # Without jq, just clean up
        rm -f "$active_file"
        return 0
    fi

    local ended_at
    ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local started_at
    started_at="$(jq -r '.started_at' "$active_file")"

    # Calculate duration in minutes
    local start_epoch end_epoch duration_min
    start_epoch=$(iso_epoch "$started_at")
    end_epoch=$(date +%s)
    duration_min=$(( (end_epoch - start_epoch) / 60 ))

    # Count files changed (git diff if in a repo)
    local files_changed=0
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        files_changed=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d ' ') || files_changed=0
    fi

    # Build finalized record
    local finalized
    finalized=$(jq \
        --arg ended "$ended_at" \
        --arg summary "$(_sr_json_escape "$summary")" \
        --argjson duration "$duration_min" \
        --argjson files "$files_changed" \
        '. + {
            ended_at: $ended,
            duration_min: $duration,
            status: "completed",
            summary: $summary,
            files_changed: $files
        }' "$active_file")

    # Append to registry (one JSON per line)
    echo "$finalized" | jq -c '.' >> "$SR_REGISTRY"

    # Update last-session.json (pretty-printed for easy reading)
    echo "$finalized" | jq '.' > "$SR_LAST_SESSION"

    # Remove active session
    rm -f "$active_file"
}

# --- Helper: collect current process ancestry ---
# Walks up the process tree from $$ to init, returns space-separated PIDs.
# Used by cleanup to detect pre-fix PID-based registrations of the *current*
# Claude session (when SR_SESSION_ID is now UUID-based but a stale PID file
# from the same process tree is still on disk).

_sr_process_ancestors() {
    local pid=$$
    local out=""
    local guard=0
    while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
        out="$out $pid"
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        guard=$((guard + 1))
        [ "$guard" -gt 20 ] && break
    done
    echo "$out"
}

# --- Cleanup stale active sessions ---
# Removes active session files that no longer represent a live distinct session:
#   - PID-based file whose PID is dead → orphan, remove
#   - PID-based file whose PID is in current process tree → pre-fix duplicate of
#     current UUID session, remove
#   - UUID-based file older than 24h → assume orphan, remove
# Current SR_SESSION_ID is always preserved.

sr_cleanup_stale() {
    local sid
    local files=()
    # Перечисление через `find`, а не через шаблон оболочки. Было `compgen -G` — встроенная
    # команда bash, в zsh её нет: условие проваливалось, массив оставался пустым, цикл не
    # выполнялся, и функция возвращала «параллельных сессий нет» вместо семи. Тихий
    # ложноотрицательный. Замена на голый шаблон не годится тоже: в zsh несовпавший шаблон
    # по умолчанию не остаётся литералом, а обрывает выполнение с «no matches found».
    # `find` ведёт себя одинаково в обеих оболочках и на пустом каталоге просто молчит.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] && files+=("$_srf")
    done <<EOF
$(find "$SR_ACTIVE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF

    local ancestors=" $(_sr_process_ancestors) "

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        sid="$(basename "$f" .json)"
        [ "$sid" = "$SR_SESSION_ID" ] && continue

        case "$sid" in
            ''|*[!0-9]*)
                # Non-numeric (UUID or test stub) — TTL 24h
                if [ -n "$(find "$f" -mmin +1440 2>/dev/null)" ]; then
                    rm -f "$f"
                fi
                ;;
            *)
                # Numeric = PID. Two reasons to remove:
                # 1. PID is dead → orphan from a crashed session
                # 2. PID is in current process tree → duplicate of current session
                #    (pre-fix registration that used $PPID before UUID stdin override)
                if ! ps -p "$sid" >/dev/null 2>&1; then
                    rm -f "$f"
                elif [[ "$ancestors" == *" $sid "* ]]; then
                    rm -f "$f"
                fi
                ;;
        esac
    done
}

# --- Detect parallel sessions ---
# Returns JSON array of currently-live active sessions (excluding current).
# Runs cleanup first so dead PID-based files don't leak into the count.

sr_detect_parallel() {
    local sid entry
    sr_cleanup_stale

    local result="[]"

    local files=()
    # Перечисление через `find`, а не через шаблон оболочки. Было `compgen -G` — встроенная
    # команда bash, в zsh её нет: условие проваливалось, массив оставался пустым, цикл не
    # выполнялся, и функция возвращала «параллельных сессий нет» вместо семи. Тихий
    # ложноотрицательный. Замена на голый шаблон не годится тоже: в zsh несовпавший шаблон
    # по умолчанию не остаётся литералом, а обрывает выполнение с «no matches found».
    # `find` ведёт себя одинаково в обеих оболочках и на пустом каталоге просто молчит.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] && files+=("$_srf")
    done <<EOF
$(find "$SR_ACTIVE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        sid="$(basename "$f" .json)"
        [ "$sid" = "$SR_SESSION_ID" ] && continue

        if command -v jq &>/dev/null; then
            entry=$(jq -c '{session_id, project_name, started_at}' "$f" 2>/dev/null) || continue
            result=$(echo "$result" | jq --argjson e "$entry" '. += [$e]')
        fi
    done

    echo "$result"
}

# --- Detect interrupted sessions ---
# Active sessions older than threshold (default 6 hours) are likely interrupted
# Returns JSON array

sr_detect_interrupted() {
    local sid started_at start_epoch age entry
    sr_cleanup_stale

    local threshold_hours="${1:-6}"
    local threshold_sec=$((threshold_hours * 3600))
    local now
    now=$(date +%s)
    local result="[]"

    # Handle no-match case (bash nullglob or explicit check)
    local files=()
    # Перечисление через `find`, а не через шаблон оболочки. Было `compgen -G` — встроенная
    # команда bash, в zsh её нет: условие проваливалось, массив оставался пустым, цикл не
    # выполнялся, и функция возвращала «параллельных сессий нет» вместо семи. Тихий
    # ложноотрицательный. Замена на голый шаблон не годится тоже: в zsh несовпавший шаблон
    # по умолчанию не остаётся литералом, а обрывает выполнение с «no matches found».
    # `find` ведёт себя одинаково в обеих оболочках и на пустом каталоге просто молчит.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] && files+=("$_srf")
    done <<EOF
$(find "$SR_ACTIVE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        sid="$(basename "$f" .json)"
        [ "$sid" = "$SR_SESSION_ID" ] && continue

        # After cleanup, surviving PID-based ids are alive — they're parallel, not interrupted.
        case "$sid" in
            ''|*[!0-9]*) ;;  # UUID — keep checking (no liveness signal)
            *)
                if ps -p "$sid" >/dev/null 2>&1; then
                    continue
                fi
                ;;
        esac

        if command -v jq &>/dev/null; then
            started_at=$(jq -r '.started_at' "$f" 2>/dev/null) || continue

            start_epoch=$(iso_epoch "$started_at")

            age=$((now - start_epoch))
            if [ "$age" -gt "$threshold_sec" ]; then
                entry=$(jq -c --argjson age_h "$((age / 3600))" \
                    '{session_id, project_name, started_at, notes, age_hours: $age_h}' "$f" 2>/dev/null) || continue
                result=$(echo "$result" | jq --argjson e "$entry" '. += [$e]')
            fi
        fi
    done

    echo "$result"
}

# --- Get startup context ---
# Builds a human-readable startup message for injection
# Returns empty string if no useful context

sr_get_startup_context() {
    local msg=""

    # 1. Last completed session
    if [ -f "$SR_LAST_SESSION" ] && command -v jq &>/dev/null; then
        local last_project last_summary last_ended last_duration
        last_project=$(jq -r '.project_name // "unknown"' "$SR_LAST_SESSION" 2>/dev/null)
        last_summary=$(jq -r '.summary // ""' "$SR_LAST_SESSION" 2>/dev/null)
        last_ended=$(jq -r '.ended_at // ""' "$SR_LAST_SESSION" 2>/dev/null)
        last_duration=$(jq -r '.duration_min // 0' "$SR_LAST_SESSION" 2>/dev/null)

        # Calculate time since last session
        local time_ago=""
        if [ -n "$last_ended" ] && [ "$last_ended" != "null" ]; then
            local last_epoch now_epoch
            last_epoch=$(iso_epoch "$last_ended")
            now_epoch=$(date +%s)
            local diff_min=$(( (now_epoch - last_epoch) / 60 ))

            if [ "$diff_min" -lt 60 ]; then
                time_ago="${diff_min} мин назад"
            elif [ "$diff_min" -lt 1440 ]; then
                time_ago="$(( diff_min / 60 ))ч назад"
            else
                time_ago="$(( diff_min / 1440 ))д назад"
            fi
        fi

        # Knowledge delta from last session
        local k_created k_updated
        k_created=$(jq -r '.knowledge_delta.created | length' "$SR_LAST_SESSION" 2>/dev/null || echo 0)
        k_updated=$(jq -r '.knowledge_delta.updated | length' "$SR_LAST_SESSION" 2>/dev/null || echo 0)

        msg+="📍 Последняя сессия: ${time_ago} (${last_project}, ${last_duration}мин)"
        if [ -n "$last_summary" ] && [ "$last_summary" != "" ] && [ "$last_summary" != "null" ]; then
            msg+="\\n   → ${last_summary}"
        fi
        if [ "$k_created" -gt 0 ] || [ "$k_updated" -gt 0 ]; then
            msg+="\\n   📚 Знания: +${k_created} новых, ↑${k_updated} обновлённых"
            # List created knowledge files
            if [ "$k_created" -gt 0 ]; then
                local created_list
                created_list=$(jq -r '.knowledge_delta.created[]' "$SR_LAST_SESSION" 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
                msg+="\\n      Новые: ${created_list}"
            fi
        fi
    fi

    # 2. Parallel sessions
    local parallel
    parallel=$(sr_detect_parallel)
    local parallel_count
    parallel_count=$(echo "$parallel" | jq 'length' 2>/dev/null || echo 0)

    if [ "$parallel_count" -gt 0 ]; then
        msg+="\\n\\n⚡ Параллельные сессии: ${parallel_count}"
        echo "$parallel" | jq -r '.[] | "   → \(.project_name) (с \(.started_at | split("T")[1] | split("Z")[0]))"' 2>/dev/null | while IFS= read -r line; do
            msg+="\\n${line}"
        done
    fi

    # 3. Interrupted sessions
    local interrupted
    interrupted=$(sr_detect_interrupted 6)
    local interrupted_count
    interrupted_count=$(echo "$interrupted" | jq 'length' 2>/dev/null || echo 0)

    if [ "$interrupted_count" -gt 0 ]; then
        msg+="\\n\\n⚠️ Прерванные сессии: ${interrupted_count}"
        echo "$interrupted" | jq -r '.[] | "   → \(.project_name) (\(.age_hours)ч назад)"' 2>/dev/null | while IFS= read -r line; do
            msg+="\\n${line}"
        done
    fi

    # 4. Knowledge created since last session by OTHER sessions (from registry)
    # This catches knowledge from parallel sessions we didn't see
    if [ -f "$SR_REGISTRY" ] && [ -f "$SR_LAST_SESSION" ] && command -v jq &>/dev/null; then
        local my_last_ended
        my_last_ended=$(jq -r '.ended_at // ""' "$SR_LAST_SESSION" 2>/dev/null)
        # Find sessions that ended after our last session (from other sessions)
        if [ -n "$my_last_ended" ] && [ "$my_last_ended" != "null" ]; then
            local other_knowledge
            other_knowledge=$(tail -20 "$SR_REGISTRY" 2>/dev/null | jq -s --arg after "$my_last_ended" --arg mysid "$SR_SESSION_ID" \
                '[.[] | select(.ended_at > $after and .session_id != $mysid) | .knowledge_delta.created[]] | unique | .[]' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
            if [ -n "$other_knowledge" ]; then
                msg+="\\n\\n🆕 Знания из других сессий: ${other_knowledge}"
            fi
        fi
    fi

    echo "$msg"
}
