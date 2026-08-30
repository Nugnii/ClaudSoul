#!/usr/bin/env bash
# bridge-health-digest.sh — monthly mechanical digest for the 16 bridges in bridges/ (inter-layer ones plus the intra-layer L2↔L2 one).
# Reads BRIDGES_DIR, extracts status + layers + version, counts aggregates.
# Writes digest to ~/.claude/bridges-history/health-YYYY-MM.md and brief hint
# to $STATE_DIR/bridge-hint.txt for session-start surfacing.
#
# Mechanical only — no semantic analysis of bridge body. For full audit agent
# invokes /bridge-health. Digest tracks bridge documentation drift between
# manual audits.
#
# Idempotent per calendar month. Default BRIDGES_DIR resolves relative to this
# script; override via env for tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY_DIR="${HISTORY_DIR:-$HOME/.claude/bridges-history}"
STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
HINT_FILE="$STATE_DIR/bridge-hint.txt"

# Shared YAML frontmatter parser (single source — see yaml-lib.sh).
YAML_LIB="${YAML_LIB:-$SCRIPT_DIR/yaml-lib.sh}"
if [ -f "$YAML_LIB" ]; then
    # shellcheck source=/dev/null
    source "$YAML_LIB"
else
    echo "Missing yaml-lib.sh: $YAML_LIB" >&2; exit 1
fi

# Единый источник путей (paths-lib.sh); аварийный inline-fallback если не задеплоена.
PATHS_LIB="${PATHS_LIB:-$SCRIPT_DIR/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; fi

# Resolve BRIDGES_DIR: honor explicit override; otherwise resolve relative to
# script, then fall back to known ClaudSoul project location.
if [ -z "${BRIDGES_DIR:-}" ]; then
    BRIDGES_DIR="$SCRIPT_DIR/../bridges"
    if [ ! -d "$BRIDGES_DIR" ] && [ -d "$CLAUDSOUL_ROOT/bridges" ]; then
        BRIDGES_DIR="$CLAUDSOUL_ROOT/bridges"
    fi
fi

[ -d "$BRIDGES_DIR" ] || { echo "No bridges dir: $BRIDGES_DIR" >&2; exit 1; }
mkdir -p "$HISTORY_DIR" "$STATE_DIR" 2>/dev/null || true

year=$(date +%Y)
month=$(date +%m)
today=$(date +%Y-%m-%d)
digest_file="$HISTORY_DIR/health-${year}-${month}.md"

total=0
implemented_n=0
designed_n=0
implicit_n=0
other_n=0

# Per-status bridge lists
declare -a implemented_list=()
declare -a designed_list=()
declare -a implicit_list=()
declare -a other_list=()

for f in "$BRIDGES_DIR"/L*-L*.md; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    base=$(basename "$f" .md)
    status=$(yaml_field "$f" status)
    status="${status:-unknown}"
    case "$status" in
        implemented) implemented_n=$((implemented_n + 1)); implemented_list+=("$base") ;;
        designed)    designed_n=$((designed_n + 1));       designed_list+=("$base") ;;
        implicit)    implicit_n=$((implicit_n + 1));       implicit_list+=("$base") ;;
        *)           other_n=$((other_n + 1));             other_list+=("$base ($status)") ;;
    esac
done

# Trend vs last month's digest — lexical sort works for YYYY-MM.
last_digest=$(ls -1 "$HISTORY_DIR"/health-*.md 2>/dev/null | grep -v "$(basename "$digest_file")$" | sort | tail -1)
trend_line=""
if [ -n "$last_digest" ] && [ -f "$last_digest" ]; then
    prev_impl=$(grep -E '^\*\*Implemented:\*\*' "$last_digest" 2>/dev/null | awk '{print $2}' | tr -d '[:alpha:]:')
    if [[ "$prev_impl" =~ ^[0-9]+$ ]]; then
        diff=$((implemented_n - prev_impl))
        prev_name=$(basename "$last_digest" .md | sed 's/^health-//')
        if [ "$diff" -gt 0 ]; then
            trend_line="+${diff} bridges promoted to implemented since ${prev_name}"
        elif [ "$diff" -lt 0 ]; then
            trend_line="${diff} bridges regressed from implemented since ${prev_name}"
        else
            trend_line="No status changes since ${prev_name}"
        fi
    fi
fi

# Health ratios
if [ "$total" -gt 0 ]; then
    impl_pct=$(awk -v i="$implemented_n" -v n="$total" 'BEGIN { printf "%.0f", i * 100 / n }')
else
    impl_pct=0
fi

{
    printf '# Bridge Health — %s-%s\n\n' "$year" "$month"
    printf '**Generated:** %s (mechanical digest — for full analysis run `/bridge-health`)\n\n' "$today"
    printf '## Totals\n\n'
    printf -- '- **Total bridges:** %s\n' "$total"
    printf -- '- **Implemented:** %s (%s%%)\n' "$implemented_n" "$impl_pct"
    printf -- '- **Designed:** %s\n' "$designed_n"
    printf -- '- **Implicit:** %s\n' "$implicit_n"
    [ "$other_n" -gt 0 ] && printf -- '- Other/unknown: %s\n' "$other_n"
    [ -n "$trend_line" ] && printf -- '- Trend: %s\n' "$trend_line"

    if [ "${#implemented_list[@]}" -gt 0 ]; then
        printf '\n## Implemented\n\n'
        for b in "${implemented_list[@]}"; do printf -- '- %s\n' "$b"; done
    fi
    if [ "${#designed_list[@]}" -gt 0 ]; then
        printf '\n## Designed (not implemented)\n\n'
        for b in "${designed_list[@]}"; do printf -- '- %s\n' "$b"; done
    fi
    if [ "${#implicit_list[@]}" -gt 0 ]; then
        printf '\n## Implicit (working without formal doc)\n\n'
        for b in "${implicit_list[@]}"; do printf -- '- %s\n' "$b"; done
    fi
    if [ "${#other_list[@]}" -gt 0 ]; then
        printf '\n## Other / unknown\n\n'
        for b in "${other_list[@]}"; do printf -- '- %s\n' "$b"; done
    fi
    printf '\n---\n_Generated by `bridge-health-digest.sh` via launchd. Mechanical metrics only._\n'
} > "$digest_file"

# Hint logic
if [ "$designed_n" -ge 3 ]; then
    printf '🔗 Bridge health: %s bridges designed but not implemented — рекомендую /bridge-health для приоритизации.\n' "$designed_n" > "$HINT_FILE"
elif [ -n "$trend_line" ] && [ "$implemented_n" -gt 0 ]; then
    printf '🔗 Monthly bridge health: %s/%s implemented (%s%%). %s. Digest: bridges-history/health-%s-%s.md\n' \
        "$implemented_n" "$total" "$impl_pct" "$trend_line" "$year" "$month" > "$HINT_FILE"
else
    rm -f "$HINT_FILE" 2>/dev/null || true
fi

exit 0
