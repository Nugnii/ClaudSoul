#!/usr/bin/env bash
# intrusiveness-format-lib.sh — презентационный слой L6-гейта интрузивности.
#
# Извлечено из intrusiveness-state-lib.sh (Ф4 — модуляризация монолита).
# itr_format_context(sid) — строит блок "Intrusiveness state" для UserPromptSubmit;
# itr_summary(sid) — итог сессии для session-collector (Stop).
#
# Использует API состояния вызывающей библиотеки (_itr_state_path,
# _itr_jq_available, itr_log_event и др.) — резолвится в момент вызова.
# Не предназначено для standalone-подключения.

# Format the context block injected into UserPromptSubmit.
# Returns 0 on success (with block printed), or 1 if state has no interesting data
# (fresh session, no events, no debt) — caller can suppress injection.
itr_format_context() {
    local sid="$1"
    [ -z "$sid" ] && return 1
    _itr_jq_available || return 1
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && return 1

    local events_count gentle_used gentle_max gentle_remaining
    local proactive_used proactive_max proactive_remaining
    local shrink_events gentle_ignored pending_debt last_event_line
    local timing_cost silence_cost_max last_destructive
    local state_current state_confidence state_reasons

    events_count=$(jq -r '.events | length' "$path" 2>/dev/null || echo 0)
    pending_debt=$(jq -r '[.silence_debt[] | select(.status=="pending")] | length' "$path" 2>/dev/null || echo 0)
    timing_cost=$(jq -r '.cost_hints.timing_cost_current // 0' "$path" 2>/dev/null || echo 0)
    silence_cost_max=$(jq -r '.cost_hints.silence_cost_max // 0' "$path" 2>/dev/null || echo 0)
    last_destructive=$(jq -r '.cost_hints.last_destructive // ""' "$path" 2>/dev/null || echo "")
    state_current=$(jq -r '.state.current // "idle"' "$path" 2>/dev/null || echo "idle")
    state_confidence=$(jq -r '.state.confidence // 1' "$path" 2>/dev/null || echo 1)
    state_reasons=$(jq -r '(.state.reasons // []) | join(",")' "$path" 2>/dev/null || echo "")

    # Skip injection only if state is truly trivial: no events, no debt, no cost/state signals.
    # Non-idle classification (focus/stuck/exploration) is itself worth surfacing.
    if [ "$events_count" -eq 0 ] && [ "$pending_debt" -eq 0 ] \
       && [ "${timing_cost:-0}" -eq 0 ] && [ "${silence_cost_max:-0}" -eq 0 ] \
       && [ -z "$last_destructive" ] && [ "$state_current" = "idle" ]; then
        return 1
    fi

    gentle_used=$(jq -r '.budget.gentle_used' "$path")
    gentle_max=$(jq -r '.budget.gentle_max' "$path")
    gentle_remaining=$((gentle_max - gentle_used))
    [ "$gentle_remaining" -lt 0 ] && gentle_remaining=0
    proactive_used=$(jq -r '.budget.proactive_used' "$path")
    proactive_max=$(jq -r '.budget.proactive_max' "$path")
    proactive_remaining=$((proactive_max - proactive_used))
    [ "$proactive_remaining" -lt 0 ] && proactive_remaining=0
    shrink_events=$(jq -r '.budget.shrink_events' "$path")
    gentle_ignored=$(jq -r '.metrics.gentle_ignored' "$path")

    last_event_line=$(jq -r '
        .events
        | if length > 0
          then .[-1] as $e
               | "Last: \($e.type) / \($e.outcome)" + (if $e.reason != "" then " — \($e.reason)" else "" end)
          else ""
          end' "$path" 2>/dev/null || echo "")

    printf '🎚️ Intrusiveness state (L6 gate):\n'
    # 4th axis — state classification from last user prompt.
    if [ -n "$state_reasons" ] && [ "$state_reasons" != "default" ]; then
        printf '  · State: %s (conf %s) — %s\n' "$state_current" "$state_confidence" "$state_reasons"
    else
        printf '  · State: %s (conf %s)\n' "$state_current" "$state_confidence"
    fi
    # AP2: when distressed, surface effective (clamped) budgets so agent sees
    # the gate restriction explicitly, not just the raw bookkeeping.
    if [ "$state_current" = "distressed" ]; then
        local effective_gentle=$((gentle_remaining / 2))
        printf '  · Budget gentle: %d/%d (effective %d in distressed)\n' "$gentle_used" "$gentle_max" "$effective_gentle"
        printf '  · Budget proactive: %d/%d (effective 0 in distressed)\n' "$proactive_used" "$proactive_max"
        printf '  · ⚙️ AP2 distressed — downgrade любой outcome до silent_prep/ignore, proactive запрещён, gentle halved.\n'
    else
        printf '  · Budget gentle: %d/%d (remaining %d)\n' "$gentle_used" "$gentle_max" "$gentle_remaining"
        printf '  · Budget proactive: %d/%d (remaining %d)\n' "$proactive_used" "$proactive_max" "$proactive_remaining"
    fi
    if [ "$shrink_events" -gt 0 ] || [ "$gentle_ignored" -gt 0 ]; then
        printf '  · Shrinks: %d (ignored gentle: %d)\n' "$shrink_events" "$gentle_ignored"
    fi
    if [ "$pending_debt" -gt 0 ]; then
        local topics
        topics=$(jq -r '[.silence_debt[] | select(.status=="pending") | .topic] | join(", ")' "$path")
        printf '  · Silence debt pending (%d): %s\n' "$pending_debt" "$topics"
    fi
    # v2 cost hints (timing/silence/destructive) — surface non-zero signals only.
    if [ "${timing_cost:-0}" -gt 0 ] || [ "${silence_cost_max:-0}" -gt 0 ] || [ -n "$last_destructive" ]; then
        printf '  · Cost hints:'
        [ "${timing_cost:-0}" -gt 0 ] && printf ' timing=%s' "$timing_cost"
        [ "${silence_cost_max:-0}" -gt 0 ] && printf ' silence_max=%s' "$silence_cost_max"
        [ -n "$last_destructive" ] && printf ' last_destructive="%s"' "$last_destructive"
        printf '\n'
    fi
    if [ -n "$last_event_line" ]; then
        printf '  · %s\n' "$last_event_line"
    fi
    printf '\n'
    printf 'Apply gate before gentle/proactive: E[regret_if_silent] > E[regret_if_speak] AND state_allows AND reversible_or_authorized.\n'
    printf 'If budget exhausted but silence_cost >= %d — emergency override, log via itr_log_event.\n' "$ITR_EMERGENCY_SILENCE_COST"
    return 0
}

# Print end-of-session summary (used by session-collector).
itr_summary() {
    local sid="$1"
    [ -z "$sid" ] && return 1
    _itr_jq_available || return 1
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && return 1
    local total
    total=$(jq -r '.events | length' "$path")
    [ "$total" -eq 0 ] && return 1

    local pending_debt surfaced_debt
    pending_debt=$(jq -r '[.silence_debt[] | select(.status=="pending")] | length' "$path")
    surfaced_debt=$(jq -r '.metrics.silence_debt_surfaced' "$path")
    jq -r \
        --argjson pending "$pending_debt" \
        --argjson surfaced "$surfaced_debt" \
        '
        "### Intrusiveness summary\n" +
        "- Events total: \(.events | length)\n" +
        "- Gentle used / max: \(.budget.gentle_used) / \(.budget.gentle_max)\n" +
        "- Proactive used / max: \(.budget.proactive_used) / \(.budget.proactive_max)\n" +
        "- Gentle accepted: \(.metrics.gentle_accepted)\n" +
        "- Gentle ignored: \(.metrics.gentle_ignored)\n" +
        "- Proactive events: \(.metrics.proactive_events)\n" +
        "- Emergency overrides: \(.metrics.override_events)\n" +
        "- Silence debt surfaced / pending: \($surfaced) / \($pending)"
        ' "$path"
}

# CLI shim: if script is invoked directly with arguments, dispatch to functions.
# This lets the agent call helpers via Bash tool without sourcing.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        init)            itr_init_state "$@" ;;
        log)             itr_log_event "$@" ;;
        debt)            itr_add_silence_debt "$@" ;;
        surface)         itr_mark_debt_surfaced "$@" ;;
        remaining)       itr_remaining_budget "$@" ;;
        context)         itr_format_context "$@" ;;
        summary)         itr_summary "$@" ;;
        set_hint)        itr_set_cost_hint "$@" ;;
        get_hint)        itr_get_cost_hint "$@" ;;
        compute_timing)       itr_compute_timing_cost "$@" ;;
        compute_destructive)  itr_compute_destructive_cost "$@" ;;
        compute_closing)      itr_compute_closing_cost "$@" ;;
        compute_state)        itr_compute_state "$@" ;;
        set_state)            itr_set_state "$@" ;;
        get_state)            itr_get_state "$@" ;;
        finalize)             itr_finalize_metrics "$@" ;;
        history)              itr_append_history "$@" ;;
        cleanup)              itr_cleanup_old_states "$@" ;;
        *)
            cat <<EOF
Usage: $0 <command> [args]
Commands:
  init <session_id>
  log <session_id> <type> <outcome> <silence_cost> <reason>
    type:    gentle | proactive | override | silence_debt | ignore
    outcome: accepted | ignored | pending | surfaced
  debt <session_id> <topic> <silence_cost>
  surface <session_id> <topic_prefix>
  remaining <session_id> <gentle|proactive>
  context <session_id>
  summary <session_id>
  set_hint <session_id> <field> <value>
    field: timing_cost_current | silence_cost_max | last_destructive | last_closing_cost
  get_hint <session_id> <field>
  compute_timing [prompt_text]        # reads stdin if arg omitted; echoes 0..5
  compute_destructive [cmd]           # reads stdin if arg omitted; echoes 0..5
  compute_closing <session_id>        # echoes 0..5 based on pending debt
  compute_state [sid] [prompt_text]   # classify; echoes "state|confidence|reasons"
  set_state <session_id> <state> <confidence> [reasons_csv]
    state: focus | stuck | exploration | idle
  get_state <session_id>              # echoes current "state|confidence|reasons"
  finalize <session_id>               # recompute metrics from events (idempotent)
  history <session_id> [boundary]     # append session digest; boundary=stop|precompact (default stop)
  cleanup [days]                      # delete stale state files (default 30d); echoes count
EOF
            exit 1
            ;;
    esac
fi
