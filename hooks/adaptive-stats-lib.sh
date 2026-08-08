#!/bin/bash
# adaptive-stats-lib.sh — v1.0.9
# Library for adaptive coefficients, speaker scoring, and domain-graph distance.
#
# Provides:
#   update_stats_on_promotion <tier>
#   update_stats_on_weakening <tier>
#   compute_source_factor <tier>        → stdout: float 0.3..2.0 (1.0 before 5+ patterns)
#   score_speaker <session_id>          → stdout: primary | anomaly_* | unknown_*
#   get_domain_distance <orig> <target> → stdout: int (0..99, 99 = unreachable)
#
# All functions are idempotent and fail silently — designed to be sourced from hooks
# where errors must never crash the pipeline.

# Единый источник путей (paths-lib.sh); аварийный inline-fallback если не задеплоена.
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; fi

ADAPTIVE_STATS_FILE="${CLAUDE_HOOKS_STATE_DIR:-$HOME/.claude/hooks/state}/adaptive-stats.json"
DOMAINS_DIR="${CLAUDE_DOMAINS_DIR:-$CLAUDSOUL_ROOT/domains}"
USER_PROFILE="${CLAUDE_USER_PROFILE:-$HOME/.claude/projects/-Users-user/memory/user_profile.md}"
STATE_DIR_LIB="${CLAUDE_HOOKS_STATE_DIR:-$HOME/.claude/hooks/state}"

_ensure_adaptive_stats() {
    [ -f "$ADAPTIVE_STATS_FILE" ] && return 0
    mkdir -p "$(dirname "$ADAPTIVE_STATS_FILE")" 2>/dev/null
    cat > "$ADAPTIVE_STATS_FILE" <<'EOF'
{
  "version": "1.0.9",
  "last_recomputed": null,
  "per_tier": {
    "1": {"total": 0, "weakened": 0, "natural_rate": null},
    "2": {"total": 0, "weakened": 0, "natural_rate": null},
    "3": {"total": 0, "weakened": 0, "natural_rate": null}
  }
}
EOF
}

update_stats_on_promotion() {
    local tier="$1"
    case "$tier" in 1|2|3) ;; *) return 1 ;; esac
    _ensure_adaptive_stats
    local tmp
    tmp=$(mktemp 2>/dev/null) || tmp="${ADAPTIVE_STATS_FILE}.tmp.$$"
    if jq --arg t "$tier" '.per_tier[$t].total += 1' "$ADAPTIVE_STATS_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$ADAPTIVE_STATS_FILE" 2>/dev/null
    else
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
}

update_stats_on_weakening() {
    local tier="$1"
    case "$tier" in 1|2|3) ;; *) return 1 ;; esac
    _ensure_adaptive_stats
    local tmp
    tmp=$(mktemp 2>/dev/null) || tmp="${ADAPTIVE_STATS_FILE}.tmp.$$"
    if jq --arg t "$tier" '.per_tier[$t].weakened += 1' "$ADAPTIVE_STATS_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$ADAPTIVE_STATS_FILE" 2>/dev/null
    else
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
}

compute_source_factor() {
    local tier="$1"
    case "$tier" in 1|2|3) ;; *) echo "1.0"; return 0 ;; esac
    _ensure_adaptive_stats

    local total
    total=$(jq '(.per_tier."1".total + .per_tier."2".total + .per_tier."3".total)' "$ADAPTIVE_STATS_FILE" 2>/dev/null)
    total="${total:-0}"

    if [ "$total" -lt 5 ] 2>/dev/null; then
        echo "1.0"
        return 0
    fi

    local factor
    factor=$(jq -r --arg t "$tier" '
        def natural_rate(tier):
            if .per_tier[tier].total == 0 then 0.0
            else (.per_tier[tier].weakened / .per_tier[tier].total) end;
        def clamp(v; mn; mx):
            if v < mn then mn elif v > mx then mx else v end;
        (natural_rate("2")) as $base |
        if $base == 0 then 1.0
        else clamp((natural_rate($t) / $base); 0.3; 2.0) end
    ' "$ADAPTIVE_STATS_FILE" 2>/dev/null)

    [ -z "$factor" ] && factor="1.0"
    echo "$factor"
}

# score_speaker — определяет speaker_id для текущей сессии.
# Сейчас v1.0.9: заглушка — всегда "primary" когда user_profile.md существует,
# потому что у системы один пользователь. Каркас на будущее: сравнение стиля
# session-сообщений с портретом в user_profile.md.
# Результат кэшируется в state/session-speaker_<session_id>.
score_speaker() {
    local session_id="$1"
    [ -z "$session_id" ] && session_id="default"
    local output_file="${STATE_DIR_LIB}/session-speaker_${session_id}"

    if [ -f "$output_file" ]; then
        cat "$output_file" 2>/dev/null
        return 0
    fi

    local speaker_id="primary"
    if [ ! -f "$USER_PROFILE" ]; then
        speaker_id="unknown_session_${session_id:0:8}"
    fi

    echo "$speaker_id" > "$output_file" 2>/dev/null
    echo "$speaker_id"
}

# get_domain_distance — BFS в graph доменов.
# Отношения: parent/children/overlaps/applies_to/analogous — все symmetric edges.
# Возвращает path length (0 = same, 1+ = hops, 99 = unreachable или missing graph).
get_domain_distance() {
    local origin="$1"
    local target="$2"

    [ -z "$origin" ] || [ -z "$target" ] && { echo "99"; return 0; }
    [ "$origin" = "$target" ] && { echo "0"; return 0; }
    [ ! -d "$DOMAINS_DIR" ] && { echo "99"; return 0; }

    local -a queue=("${origin}:0")
    local visited=" ${origin} "
    local head=0 current name depth file neighbors n
    local max_depth=3

    while [ $head -lt ${#queue[@]} ]; do
        current="${queue[$head]}"
        head=$((head + 1))
        name="${current%:*}"
        depth="${current##*:}"

        [ "$depth" -ge "$max_depth" ] && continue

        file="$DOMAINS_DIR/${name}.md"
        [ ! -f "$file" ] && continue

        neighbors=$(grep -E '^(parent|children|overlaps|applies_to|analogous):' "$file" 2>/dev/null \
            | sed -E 's/^[a-z_]+:[[:space:]]*\[//; s/\].*$//; s/,/ /g; s/[[:space:]]+/ /g' \
            | tr -s ' ' '\n' | grep -v '^$' || true)

        for n in $neighbors; do
            [ -z "$n" ] && continue
            if [ "$n" = "$target" ]; then
                echo "$((depth + 1))"
                return 0
            fi
            case "$visited" in
                *" $n "*) ;;
                *) queue+=("${n}:$((depth + 1))"); visited="${visited}${n} " ;;
            esac
        done
    done

    echo "99"
}

# When sourced, these become available in the caller's shell.
# No explicit export — bash function export via `export -f` is platform-dependent
# and not needed for `source`-based use.
