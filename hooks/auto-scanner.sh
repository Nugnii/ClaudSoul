#!/usr/bin/env bash
# auto-scanner.sh — launchd (каждые 4ч): read-only сканирование проектов, запись находок в scan-results.md для следующей сессии.
# en: launchd (every 4h): read-only scan of projects, findings written to scan-results.md for the next session.
# Запускается по расписанию через launchd (каждые 4 часа)
# Результаты пишет в ~/.claude/hooks/state/scan-results.md
# knowledge-activator подхватывает при старте следующей сессии
#
# КРИТИЧНО: только чтение. Никаких git commit, push, edit, write.
# Разведка, не атака.

set -euo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

# Сканер ходит по времени изменения файлов, а у stat синтаксис расходится: GNU `-c`, BSD `-f`.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then source "$PORTABLE_LIB"; else file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }; fi

PROJECTS_DIR="$HOME/.claude/projects"
# STATE_DIR — из paths-lib (источается выше)
KNOWLEDGE_DIR="$LESSONS_DIR"
RESULTS_FILE="$STATE_DIR/scan-results.md"
LAST_SCAN_FILE="$STATE_DIR/last-scan-timestamp"
LOG_FILE="$STATE_DIR/scanner.log"

mkdir -p "$STATE_DIR"

# --- Logging ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true; }

log "Scanner started"

# --- Gate: don't re-scan within 3 hours ---
MIN_INTERVAL_SEC=10800  # 3 hours
if [ -f "$LAST_SCAN_FILE" ]; then
    LAST_SCAN=$(cat "$LAST_SCAN_FILE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_SCAN))
    if [ "$ELAPSED" -lt "$MIN_INTERVAL_SEC" ]; then
        log "Skipped: last scan ${ELAPSED}s ago (min ${MIN_INTERVAL_SEC}s)"
        exit 0
    fi
fi

# --- Resolve project path from Claude's encoding ---
# "-Users-user-My-Project-ClaudSoul" → "~/My Project/ClaudSoul"
# Tricky: spaces in paths become single `-`, same as path separators
# Strategy: try to resolve by checking if path exists, expanding greedily
resolve_path() {
    local encoded="$1"
    # Remove leading dash
    encoded="${encoded#-}"
    # Replace dashes with slashes
    local candidate="/${encoded//-//}"

    if [ -d "$candidate" ]; then
        echo "$candidate"
        return 0
    fi

    # If not found, try replacing some slashes back to spaces or dashes
    # Heuristic: try the most common pattern (spaces in "My Project" etc.)
    # Walk segments and try joining with space
    local IFS='-'
    read -ra PARTS <<< "$1"
    local path=""
    local i=0

    # Skip first empty element (leading dash)
    for ((i=1; i<${#PARTS[@]}; i++)); do
        local segment="${PARTS[$i]}"
        # Try appending as new directory segment
        local try_slash="${path}/${segment}"
        # Try appending as space-joined continuation
        local try_space="${path} ${segment}"

        if [ -d "$try_slash" ]; then
            path="$try_slash"
        elif [ -d "$try_space" ]; then
            path="$try_space"
        elif [ $i -eq $((${#PARTS[@]}-1)) ]; then
            # Last segment — try both, prefer slash
            if [ -d "$try_slash" ]; then
                path="$try_slash"
            elif [ -d "$try_space" ]; then
                path="$try_space"
            else
                path="$try_slash"  # best guess
            fi
        else
            # Neither exists yet — try slash (most common)
            path="$try_slash"
        fi
    done

    if [ -d "$path" ]; then
        echo "$path"
        return 0
    fi

    return 1
}

# --- Scan a single project ---
scan_project() {
    local project_path="$1"
    local project_name
    project_name=$(basename "$project_path")
    local findings=""
    local finding_count=0

    # Skip if not a git repo
    if [ ! -d "$project_path/.git" ]; then
        return
    fi

    # 1. Uncommitted changes
    local status
    status=$(cd "$project_path" && git status --porcelain 2>/dev/null | head -20) || true
    if [ -n "$status" ]; then
        local change_count
        change_count=$(echo "$status" | wc -l | tr -d ' ')
        findings="${findings}\n- **Незакоммиченные изменения:** ${change_count} файлов"
        finding_count=$((finding_count + 1))
    fi

    # 2. Recent commits (last 7 days)
    local recent_commits
    recent_commits=$(cd "$project_path" && git log --oneline --since="7 days ago" 2>/dev/null | head -10) || true
    if [ -n "$recent_commits" ]; then
        local commit_count
        commit_count=$(echo "$recent_commits" | wc -l | tr -d ' ')
        findings="${findings}\n- **Активность (7 дней):** ${commit_count} коммитов"
    fi

    # 3. Stale branches (no commits in 30 days)
    local stale_branches
    stale_branches=$(cd "$project_path" && git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:relative)' refs/heads/ 2>/dev/null | \
        grep -E '(months?|years?) ago' | head -5) || true
    if [ -n "$stale_branches" ]; then
        local stale_count
        stale_count=$(echo "$stale_branches" | wc -l | tr -d ' ')
        findings="${findings}\n- **Stale ветки:** ${stale_count} (без коммитов 30+ дней)"
        finding_count=$((finding_count + 1))
    fi

    # 4. TODO/FIXME count
    local todo_count=0
    todo_count=$(cd "$project_path" && grep -r --include='*.{js,ts,tsx,jsx,py,sh,md}' -c 'TODO\|FIXME\|HACK\|XXX' . 2>/dev/null | \
        awk -F: '{s+=$2} END {print s+0}') || true
    if [ "$todo_count" -gt 0 ]; then
        findings="${findings}\n- **TODO/FIXME:** ${todo_count} штук"
        if [ "$todo_count" -gt 10 ]; then
            finding_count=$((finding_count + 1))
        fi
    fi

    # 5. Cross-reference with knowledge base — check if any patterns mention this project's tech
    local project_files
    project_files=$(cd "$project_path" && ls -1 2>/dev/null) || true
    local tech_keywords=""

    # Detect tech stack from files
    grep -q "package.json" <<< "$project_files" && tech_keywords="${tech_keywords} node javascript"
    grep -q "next.config" <<< "$project_files" && tech_keywords="${tech_keywords} nextjs react"
    grep -q "requirements.txt\|pyproject.toml" <<< "$project_files" && tech_keywords="${tech_keywords} python"
    grep -q "Cargo.toml" <<< "$project_files" && tech_keywords="${tech_keywords} rust"
    grep -q "go.mod" <<< "$project_files" && tech_keywords="${tech_keywords} golang"
    grep -q "docker-compose\|Dockerfile" <<< "$project_files" && tech_keywords="${tech_keywords} docker"

    # Check knowledge base for warnings about this tech
    if [ -n "$tech_keywords" ] && [ -d "$KNOWLEDGE_DIR" ]; then
        local kb_warnings=""
        for kw in $tech_keywords; do
            for kfile in "$KNOWLEDGE_DIR"/pattern-*.md "$KNOWLEDGE_DIR"/principle-*.md; do
                [ -f "$kfile" ] || continue
                if grep -qi "$kw" "$kfile" 2>/dev/null; then
                    local kname
                    kname=$(basename "$kfile" .md)
                    # Avoid duplicates
                    if ! grep -q "$kname" 2>/dev/null <<< "$kb_warnings"; then
                        kb_warnings="${kb_warnings} ${kname}"
                    fi
                fi
            done
        done
        if [ -n "$kb_warnings" ]; then
            findings="${findings}\n- **Релевантные знания:**${kb_warnings}"
        fi
    fi

    # 6. SESSION.md staleness
    if [ -f "$project_path/SESSION.md" ]; then
        local session_age
        session_age=$(( ( $(date +%s) - $(file_mtime "$project_path/SESSION.md") ) / 86400 ))
        if [ "$session_age" -gt 14 ]; then
            findings="${findings}\n- **SESSION.md устарел:** ${session_age} дней без обновления"
            finding_count=$((finding_count + 1))
        fi
    fi

    # 7. Документация отстала от кода (docs drift) — сколько коммитов кода (web/bot)
    #    прошло после последнего коммита, тронувшего доки. Делает дрейф видимым владельцу,
    #    даже если per-commit напоминание docs-family-check было пропущено.
    local last_doc_commit code_ahead
    last_doc_commit=$(cd "$project_path" && git log -1 --format=%H -- \
        CHANGELOG.md PLAN.md docs/architecture.md README.md CLAUDE.md .claude-docs/modules/ 2>/dev/null) || true
    if [ -n "$last_doc_commit" ]; then
        # Кодом считается ВСЁ, кроме самих документов, а не перечень каталогов (D52).
        # Раньше здесь стояло `-- web/ bot/` — имена из одного конкретного проекта.
        # В любом репозитории без этих каталогов показатель равнялся нулю, и ноль
        # означал не «расхождения нет», а «не измеряли». Замер на проекте, где `web/`
        # есть: жёсткие пути дали 1 коммит, «всё кроме доков» — 2.
        code_ahead=$(cd "$project_path" && git rev-list "${last_doc_commit}..HEAD" --count -- . \
            ':(exclude)CHANGELOG.md' ':(exclude)PLAN.md' ':(exclude)docs/architecture.md' \
            ':(exclude)README.md' ':(exclude)CLAUDE.md' ':(exclude).claude-docs/*' \
            ':(exclude)SESSION.md' 2>/dev/null) || code_ahead=0
        [ -z "$code_ahead" ] && code_ahead=0
        if [ "$code_ahead" -gt 10 ]; then
            findings="${findings}\n- **Документация отстала:** ${code_ahead} коммитов кода после последнего обновления доков (модули/PLAN/architecture/CHANGELOG)"
            finding_count=$((finding_count + 1))
        fi
    fi

    # Only report if there are noteworthy findings
    if [ "$finding_count" -gt 0 ]; then
        echo "### ${project_name}"
        echo -e "$findings"
        echo ""
    fi
}

# --- Main scan ---
SCAN_DATE=$(date '+%Y-%m-%d %H:%M')
SCAN_OUTPUT=""
PROJECT_COUNT=0
FINDING_PROJECTS=0

for proj_dir in "$PROJECTS_DIR"/*/; do
    [ -d "$proj_dir" ] || continue
    proj_encoded=$(basename "$proj_dir")

    # Skip non-project dirs
    [ "$proj_encoded" = "-private-tmp" ] && continue

    resolved=$(resolve_path "$proj_encoded" 2>/dev/null) || continue
    [ -d "$resolved" ] || continue

    PROJECT_COUNT=$((PROJECT_COUNT + 1))
    result=$(scan_project "$resolved" 2>/dev/null) || true

    if [ -n "$result" ]; then
        SCAN_OUTPUT="${SCAN_OUTPUT}${result}\n"
        FINDING_PROJECTS=$((FINDING_PROJECTS + 1))
    fi
done

# --- Write results ---
{
    echo "# Auto-scan results"
    echo "**Дата:** ${SCAN_DATE}"
    echo "**Проектов просканировано:** ${PROJECT_COUNT}"
    echo "**С находками:** ${FINDING_PROJECTS}"
    echo ""
    if [ -n "$SCAN_OUTPUT" ]; then
        echo -e "$SCAN_OUTPUT"
    else
        echo "_Ничего примечательного не найдено._"
    fi
} > "$RESULTS_FILE"

# --- Run metrics collector ---
METRICS_SCRIPT="$HOME/.claude/hooks/metrics-collector.sh"
if [ -f "$METRICS_SCRIPT" ]; then
    bash "$METRICS_SCRIPT" >> "$LOG_FILE" 2>&1 || true
fi

# Update timestamp
date +%s > "$LAST_SCAN_FILE"

log "Scan complete: ${PROJECT_COUNT} projects, ${FINDING_PROJECTS} with findings"
