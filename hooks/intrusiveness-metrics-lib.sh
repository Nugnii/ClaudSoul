#!/usr/bin/env bash
# intrusiveness-metrics-lib.sh — метрики/история/очистка L6-гейта интрузивности.
#
# Извлечено из intrusiveness-state-lib.sh (Ф4 — модуляризация монолита).
# itr_finalize_metrics(sid) — финализация метрик из events[];
# itr_append_history(sid) — однострочный дайджест сессии в intrusiveness-history.jsonl;
# itr_cleanup_old_states(days) — очистка старых файлов состояния.
#
# Использует helpers/API вызывающей библиотеки (_itr_state_path, _itr_jq_available,
# _itr_now, _itr_migrate_state) — резолвится в момент вызова. Не для standalone.

# Разбор created_at — через общий portable-lib.sh: ключ `date -j` есть только у BSD,
# GNU date отвечает «invalid option -- 'j'» и пустой строкой. Разбор при этом выглядит
# неудачным, файл считается неразбираемым и пропускается — то есть на Linux очистка
# молча не удаляла ничего и состояния копились без ограничения срока.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then source "$PORTABLE_LIB"; fi

# Finalize metrics from events[] (v1.3.2). Idempotent — can be called at any
# point. Authoritative: recomputes metrics{} from events (source of truth),
# overwriting any inline increments from itr_log_event. This handles both:
#   (a) normal session close: counters match inline increments (no-op effect)
#   (b) backfill of legacy state files that have events but zero metrics
#
# Must be called before itr_append_history so the digest reflects reality.
itr_finalize_metrics() {
    local sid="$1"
    [ -z "$sid" ] && return 1
    _itr_jq_available || return 1
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && return 0
    _itr_migrate_state "$path"
    local tmp="$path.tmp.$$"
    jq \
        --argjson et "$ITR_EMERGENCY_SILENCE_COST" \
        '
        .metrics = {
            gentle_accepted: ([.events[] | select(.type=="gentle" and .outcome=="accepted")] | length),
            gentle_ignored:  ([.events[] | select(.type=="gentle" and .outcome=="ignored")]  | length),
            proactive_events: ([.events[] | select(.type=="proactive")] | length),
            override_events: (
                [.events[]
                 | select(
                    .type=="override"
                    or ((.silence_cost // 0) >= $et and (.type=="gentle" or .type=="proactive"))
                   )
                ] | length
            ),
            silence_debt_surfaced: ([.events[] | select(.type=="silence_debt" and .outcome=="surfaced")] | length)
        }
        ' "$path" > "$tmp" && mv "$tmp" "$path"
}

# Append one-line session digest to ~/.claude/hooks/state/intrusiveness-history.jsonl.
# Source of truth for trend analytics and H13/H14/H15 verification.
# Must be called AFTER itr_finalize_metrics for accurate counters.
# Duration is computed as closed_at - created_at in minutes (floor).
#
# Args: sid, boundary (optional, default "stop")
#   boundary: "stop"       — normal session close (Stop event)
#             "precompact" — chunk boundary before context compaction
#
# On "precompact" the digest is a cumulative snapshot; analytics consumers
# derive chunk deltas by subtracting successive snapshots.
itr_append_history() {
    local sid="$1" boundary="${2:-stop}"
    [ -z "$sid" ] && return 1
    _itr_jq_available || return 1
    case "$boundary" in
        stop|precompact) ;;
        *) boundary="stop" ;;
    esac
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && return 1
    local history_path="$ITR_STATE_DIR/intrusiveness-history.jsonl"
    local now today
    now=$(_itr_now)
    today=$(date -u +"%Y-%m-%d")
    local digest
    digest=$(jq -c \
        --arg closed "$now" \
        --arg date "$today" \
        --arg boundary "$boundary" \
        '
        {
            session_id: .session_id,
            date: $date,
            boundary: $boundary,
            created_at: .created_at,
            closed_at: $closed,
            duration_min: (
                ( ($closed | fromdateiso8601) - (.created_at | fromdateiso8601) )
                / 60 | floor
            ),
            events_total: (.events | length),
            budget: {
                gentle_used:     .budget.gentle_used,
                gentle_max:      .budget.gentle_max,
                proactive_used:  .budget.proactive_used,
                proactive_max:   .budget.proactive_max,
                shrink_events:   .budget.shrink_events
            },
            metrics: .metrics,
            debt: {
                surfaced: (.metrics.silence_debt_surfaced // 0),
                pending:  ([.silence_debt[] | select(.status=="pending")] | length),
                pending_topics: ([.silence_debt[] | select(.status=="pending") | .topic][:5])
            },
            cost_peaks: {
                timing_max:  (.cost_hints.timing_cost_peak // .cost_hints.timing_cost_current // 0),
                silence_max: (.cost_hints.silence_cost_max // 0),
                closing:     (.cost_hints.last_closing_cost // 0),
                injection_bytes_max: (.cost_hints.injection_bytes_max // 0)
            },
            cascading: {
                backward_count: (.cost_hints.cascading_backward_count // 0)
            },
            state_distribution: (.state.distribution // {focus:0, stuck:0, exploration:0, idle:0})
        }
        ' "$path" 2>/dev/null)
    [ -z "$digest" ] && return 1
    printf '%s\n' "$digest" >> "$history_path"
}

# Delete stale per-session state files older than N days (default 30).
# Safe: only touches files matching `intrusiveness-*.json` in ITR_STATE_DIR,
# parses created_at from each, skips files with unparseable dates. Never
# touches the history log (different extension: .jsonl).
# Echoes count of files deleted.
itr_cleanup_old_states() {
    local days="${1:-30}"
    _itr_jq_available || { echo 0; return; }
    local now_epoch threshold deleted=0
    now_epoch=$(date -u +%s)
    threshold=$((days * 86400))
    local f created created_epoch age
    for f in "$ITR_STATE_DIR"/intrusiveness-*.json; do
        [ -f "$f" ] || continue
        created=$(jq -r '.created_at // ""' "$f" 2>/dev/null || echo "")
        [ -z "$created" ] && continue
        created_epoch=$(iso_epoch "$created" 2>/dev/null || echo 0)
        [ "$created_epoch" -eq 0 ] && continue
        age=$((now_epoch - created_epoch))
        if [ "$age" -gt "$threshold" ]; then
            rm -f "$f" && deleted=$((deleted + 1))
        fi
    done
    echo "$deleted"
}

