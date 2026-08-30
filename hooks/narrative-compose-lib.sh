#!/usr/bin/env bash
# narrative-compose-lib.sh — pure helper: SESSION.md + git log + global-lessons → orientation brief.
# Invoked from session-start.sh (auto path) and skills/narrative (manual override).
#
# Contract: no hallucination. All lines reference real artefacts (commits, session entries, case files).
# Output format: plain text block. Reads from $PROJECT_ROOT, $ENTRIES (default 3), $WINDOW_DAYS (default 14),
#               $GLOBAL_LESSONS (default ~/.claude/global-lessons).
# Empty output = abort conditions (no SESSION.md, <2 entries, no history in window).

# Время изменения файла (single source — see portable-lib.sh): `stat -f` понимает только BSD.
# Запасная ветка не фатальна намеренно: библиотеку источает session-start.sh на старте сессии,
# и `exit 1` при недоставленном файле убил бы хук, а не одну строку брифа.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
else
    file_mtime() { stat -c %Y "${1:-}" 2>/dev/null || stat -f %m "${1:-}" 2>/dev/null || echo 0; }
fi

narrative_compose() {
    local project_root="${1:-}"
    local entries="${2:-3}"
    local window_days="${3:-14}"
    local global_lessons="${4:-$HOME/.claude/global-lessons}"

    [ -d "$project_root" ] || return 1
    local session="$project_root/SESSION.md"
    [ -f "$session" ] || return 1

    # Parse last N entries by '## YYYY-MM-DD' headers
    local session_dates session_titles
    session_dates=$(grep -nE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$session" \
        | awk -F'##' '{gsub(/^ +/,"",$2); print $2}' \
        | tail -n "$entries")
    local entry_count
    entry_count=$(printf '%s\n' "$session_dates" | grep -c . || true)
    [ "$entry_count" -ge 2 ] || return 2

    # First date of last N entries (oldest), last (newest)
    local first_date last_date
    first_date=$(printf '%s\n' "$session_dates" | head -1 | awk '{print $1}')
    last_date=$(printf '%s\n' "$session_dates" | tail -1 | awk '{print $1}')

    # Last entry title (headline)
    local last_title
    last_title=$(printf '%s\n' "$session_dates" | tail -1 | sed 's/^[0-9-]* *—* *//')

    # Git log in window: counts + last 5 subjects
    local git_total git_feat git_fix git_docs git_refactor recent_commits
    if [ -d "$project_root/.git" ]; then
        git_total=$(git -C "$project_root" log --oneline --since="${window_days} days ago" 2>/dev/null | wc -l | tr -d ' ')
        git_feat=$(git -C "$project_root" log --oneline --since="${window_days} days ago" 2>/dev/null | grep -cE '^[a-f0-9]+ feat' || true)
        git_fix=$(git -C "$project_root" log --oneline --since="${window_days} days ago" 2>/dev/null | grep -cE '^[a-f0-9]+ fix' || true)
        git_docs=$(git -C "$project_root" log --oneline --since="${window_days} days ago" 2>/dev/null | grep -cE '^[a-f0-9]+ docs' || true)
        git_refactor=$(git -C "$project_root" log --oneline --since="${window_days} days ago" 2>/dev/null | grep -cE '^[a-f0-9]+ refactor' || true)
        recent_commits=$(git -C "$project_root" log --oneline --since="${window_days} days ago" -n 5 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')
    else
        git_total=0; git_feat=0; git_fix=0; git_docs=0; git_refactor=0; recent_commits=""
    fi

    # Recent knowledge in global-lessons (mtime in window)
    local recent_cases recent_patterns
    if [ -d "$global_lessons" ]; then
        recent_cases=$(find "$global_lessons" -maxdepth 1 -name 'case-*.md' -type f -mtime "-${window_days}" 2>/dev/null \
            | xargs -n1 basename 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        recent_patterns=$(find "$global_lessons" -maxdepth 1 -name 'pattern-*.md' -type f -mtime "-${window_days}" 2>/dev/null \
            | xargs -n1 basename 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    else
        recent_cases=""; recent_patterns=""
    fi

    local case_count pattern_count
    case_count=$(printf '%s' "$recent_cases" | tr ' ' '\n' | grep -c . || true)
    pattern_count=$(printf '%s' "$recent_patterns" | tr ' ' '\n' | grep -c . || true)

    # Abort if both histories empty
    if [ "$git_total" -eq 0 ] && [ "$case_count" -eq 0 ]; then
        return 2
    fi

    # H-chain: grep last '### Trajectory' block for H_n entries
    local h_chain
    h_chain=$(awk '/^### Trajectory/{found=1; next} found && /^##[^#]/{exit} found{print}' "$session" \
        | grep -E '^H[0-9]+' | tail -3 | sed 's/^/  /')

    # Compose brief (template-driven, fact-only)
    echo "📖 Where we are:"
    echo ""
    echo "За окно ${window_days}d последняя активная сессия — «${last_title}» (${last_date}). Окно охватывает ${entry_count} сессий, начиная с ${first_date}."
    if [ "$git_total" -gt 0 ]; then
        echo ""
        echo "Коммиты в окне: ${git_total} всего (feat:${git_feat} fix:${git_fix} refactor:${git_refactor} docs:${git_docs}). Последние: ${recent_commits}."
    fi
    if [ "$case_count" -gt 0 ] || [ "$pattern_count" -gt 0 ]; then
        echo ""
        # Top-5 recent by mtime — не перегружать инжект
        local recent_cases_top recent_patterns_top
        recent_cases_top=$(find "$global_lessons" -maxdepth 1 -name 'case-*.md' -type f -mtime "-${window_days}" 2>/dev/null \
            | while IFS= read -r f; do printf '%s %s\n' "$(file_mtime "$f")" "$f"; done \
            | sort -rn | head -5 | awk '{print $2}' | xargs -n1 basename 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        recent_patterns_top=$(find "$global_lessons" -maxdepth 1 -name 'pattern-*.md' -type f -mtime "-${window_days}" 2>/dev/null \
            | while IFS= read -r f; do printf '%s %s\n' "$(file_mtime "$f")" "$f"; done \
            | sort -rn | head -3 | awk '{print $2}' | xargs -n1 basename 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        echo "Knowledge delta (${case_count} case / ${pattern_count} pattern в окне). Свежие: ${recent_cases_top}${recent_patterns_top:+; $recent_patterns_top}."
    fi
    if [ -n "$h_chain" ]; then
        echo ""
        echo "Активная H-цепочка:"
        printf '%s\n' "$h_chain"
    fi
    echo ""
    echo "_Trace:_"
    [ -n "$recent_commits" ] && echo "  - commits: ${recent_commits}"
    local session_dates_inline
    session_dates_inline=$(printf '%s\n' "$session_dates" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    echo "  - sessions: ${session_dates_inline}"

    return 0
}

# When invoked directly: compose and print
if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
    narrative_compose "${1:-$PWD}" "${2:-3}" "${3:-14}" "${4:-$HOME/.claude/global-lessons}"
fi
