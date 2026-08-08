#!/usr/bin/env bash
# intrusiveness-state-lib.sh — library for the L6 Prediction intrusiveness gate
#
# State file: ~/.claude/hooks/state/intrusiveness-<SESSION_ID>.json
# Schema (v4, backward-compatible with v1/v2/v3 — missing sections auto-migrated):
#   {
#     "session_id": "...",
#     "created_at": "ISO8601",
#     "schema_version": 4,
#     "budget": { ... },             # unchanged since v1
#     "events": [ ... ],             # unchanged since v1
#     "silence_debt": [ ... ],       # unchanged since v1
#     "metrics": { ... },            # unchanged since v1
#     "cost_hints": {                # v2 additions — rule-based detectors
#       "timing_cost_current": 0-5,    # latest UserPromptSubmit timing cost
#       "timing_cost_peak": 0-5,       # running max of timing_cost across session (v1.3.2)
#       "silence_cost_max": 0-5,       # highest silence_cost signal seen this session
#       "last_destructive": "...",     # last detected destructive command (or "")
#       "last_closing_cost": 0-5,      # last closing_cost computed at Stop
#       "last_updated": "ISO8601"
#     },
#     "state": {                     # v3 additions — 4th axis of 4D gate (L3 pragmatic)
#       "current": "idle",             # focus | stuck | exploration | idle
#       "confidence": 1,               # 1 (weak) .. 3 (multiple converging signals)
#       "reasons": ["..."],            # signals that drove the classification
#       "last_updated": "ISO8601",
#       "distribution": {              # per-session counter, feeds metrics-collector
#         "focus": 0, "stuck": 0, "exploration": 0, "idle": 0
#       }
#     }
#   }
#
# History log (v1.3.2): ~/.claude/hooks/state/intrusiveness-history.jsonl
#   One line per session close. Written by itr_append_history (called from
#   session-collector Stop). Schema is denormalised digest of the session
#   state — source of truth for H13/H14/H15 long-term verification.
#
# Usage:
#   source "$HOME/.claude/hooks/intrusiveness-state-lib.sh"
#   itr_init_state <session_id>
#   itr_log_event <session_id> <type> <outcome> <silence_cost> <reason>
#   itr_add_silence_debt <session_id> <topic> <silence_cost>
#   itr_remaining_budget <session_id> <type>   # echoes integer
#   itr_apply_ignore <session_id>              # called when prior gentle was ignored
#   itr_format_context <session_id>            # prints "🎚️ Intrusiveness state" block
#   itr_summary <session_id>                   # prints end-of-session summary

ITR_STATE_DIR="${ITR_STATE_DIR:-$HOME/.claude/hooks/state}"
mkdir -p "$ITR_STATE_DIR" 2>/dev/null

ITR_DEFAULT_GENTLE_MAX=5
ITR_DEFAULT_PROACTIVE_MAX=3
ITR_EMERGENCY_SILENCE_COST=4
ITR_SCHEMA_VERSION=4

_itr_state_path() {
    local sid="$1"
    [ -z "$sid" ] && sid="unknown"
    printf '%s/intrusiveness-%s.json' "$ITR_STATE_DIR" "$sid"
}

_itr_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_itr_jq_available() {
    command -v jq >/dev/null 2>&1
}

# Create state file if it does not exist. Idempotent.
# If an older v1 file exists, upgrade it in place to v2 (add cost_hints, bump version).
itr_init_state() {
    local sid="$1"
    [ -z "$sid" ] && return 1
    local path
    path=$(_itr_state_path "$sid")
    _itr_jq_available || return 1
    if [ -f "$path" ]; then
        _itr_migrate_state "$path"
        return 0
    fi
    jq -n \
        --arg sid "$sid" \
        --arg now "$(_itr_now)" \
        --argjson gmax "$ITR_DEFAULT_GENTLE_MAX" \
        --argjson pmax "$ITR_DEFAULT_PROACTIVE_MAX" \
        --argjson sv "$ITR_SCHEMA_VERSION" \
        '{
            session_id: $sid,
            created_at: $now,
            schema_version: $sv,
            budget: {
                gentle_max: $gmax, gentle_used: 0,
                proactive_max: $pmax, proactive_used: 0,
                shrink_events: 0
            },
            events: [],
            silence_debt: [],
            metrics: {
                gentle_accepted: 0, gentle_ignored: 0,
                proactive_events: 0, override_events: 0,
                silence_debt_surfaced: 0
            },
            cost_hints: {
                timing_cost_current: 0,
                timing_cost_peak: 0,
                silence_cost_max: 0,
                last_destructive: "",
                last_closing_cost: 0,
                last_updated: $now
            },
            state: {
                current: "idle",
                confidence: 1,
                reasons: [],
                last_updated: $now,
                distribution: { focus: 0, stuck: 0, exploration: 0, idle: 0, distressed: 0 }
            }
        }' > "$path"
}

# Migrate state file to current schema. Idempotent, safe on v2 files.
# Detects missing top-level blocks AND missing fields within cost_hints,
# so adding new fields (e.g. timing_cost_peak in v1.3.2) does not require
# a schema_version bump — all pre-existing v2 files self-heal on first touch.
_itr_migrate_state() {
    local path="$1"
    [ -f "$path" ] || return 0
    _itr_jq_available || return 0
    local needs_migration
    needs_migration=$(jq -r '
        (.schema_version // 1) < 4
        or (has("cost_hints") | not)
        or (.cost_hints | has("timing_cost_peak") | not)
        or (has("state") | not)
        or (.state | has("distribution") | not)
        or (.state.distribution | has("distressed") | not)
    ' "$path" 2>/dev/null || echo "false")
    [ "$needs_migration" != "true" ] && return 0
    local now
    now=$(_itr_now)
    local tmp="$path.tmp.$$"
    jq \
        --arg now "$now" \
        --argjson sv "$ITR_SCHEMA_VERSION" \
        '
        .schema_version = $sv
        | .cost_hints = (.cost_hints // {
            timing_cost_current: 0,
            timing_cost_peak: 0,
            silence_cost_max: 0,
            last_destructive: "",
            last_closing_cost: 0,
            last_updated: $now
          })
        | .cost_hints.timing_cost_peak = (.cost_hints.timing_cost_peak // 0)
        | .state = (.state // {
            current: "idle",
            confidence: 1,
            reasons: [],
            last_updated: $now,
            distribution: { focus: 0, stuck: 0, exploration: 0, idle: 0, distressed: 0 }
          })
        | .state.distribution = (.state.distribution // { focus: 0, stuck: 0, exploration: 0, idle: 0, distressed: 0 })
        | .state.distribution.focus       = (.state.distribution.focus       // 0)
        | .state.distribution.stuck       = (.state.distribution.stuck       // 0)
        | .state.distribution.exploration = (.state.distribution.exploration // 0)
        | .state.distribution.idle        = (.state.distribution.idle        // 0)
        | .state.distribution.distressed  = (.state.distribution.distressed  // 0)
        ' "$path" > "$tmp" && mv "$tmp" "$path"
}

# Append an event and update counters/metrics.
# Args: sid, type, outcome, silence_cost (int 0-5), reason
itr_log_event() {
    local sid="$1" type="$2" outcome="$3" scost="${4:-0}" reason="${5:-}"
    [ -z "$sid" ] || [ -z "$type" ] && return 1
    _itr_jq_available || return 1
    itr_init_state "$sid"
    local path
    path=$(_itr_state_path "$sid")
    local now
    now=$(_itr_now)
    local tmp="$path.tmp.$$"
    jq \
        --arg ts "$now" \
        --arg type "$type" \
        --arg outcome "$outcome" \
        --argjson scost "$scost" \
        --arg reason "$reason" \
        --argjson emergency_threshold "$ITR_EMERGENCY_SILENCE_COST" \
        '
        . as $st
        | .events += [{ts:$ts, type:$type, outcome:$outcome, silence_cost:$scost, reason:$reason}]
        | if $type == "gentle" and $outcome != "ignored" then
            .budget.gentle_used += 1
          else . end
        | if $type == "proactive" and $outcome != "ignored" then
            .budget.proactive_used += 1
          else . end
        | if $type == "gentle" and $outcome == "accepted" then
            .metrics.gentle_accepted += 1
          else . end
        | if $type == "gentle" and $outcome == "ignored" then
            .metrics.gentle_ignored += 1
            | .budget.gentle_max = ([.budget.gentle_max - 1, 0] | max)
            | .budget.shrink_events += 1
          else . end
        | if $type == "proactive" then
            .metrics.proactive_events += 1
          else . end
        | if $type == "override" or ($scost >= $emergency_threshold and ($type == "gentle" or $type == "proactive")) then
            .metrics.override_events += 1
          else . end
        | if $type == "silence_debt" and $outcome == "surfaced" then
            .metrics.silence_debt_surfaced += 1
          else . end
        ' "$path" > "$tmp" && mv "$tmp" "$path"
}

# Append to silence debt queue.
itr_add_silence_debt() {
    local sid="$1" topic="$2" scost="${3:-0}"
    [ -z "$sid" ] || [ -z "$topic" ] && return 1
    _itr_jq_available || return 1
    itr_init_state "$sid"
    local path
    path=$(_itr_state_path "$sid")
    local now
    now=$(_itr_now)
    local tmp="$path.tmp.$$"
    jq \
        --arg ts "$now" \
        --arg topic "$topic" \
        --argjson scost "$scost" \
        '.silence_debt += [{ts:$ts, topic:$topic, silence_cost:$scost, status:"pending"}]' \
        "$path" > "$tmp" && mv "$tmp" "$path"
}

# Mark a debt item as surfaced (matched by topic prefix).
itr_mark_debt_surfaced() {
    local sid="$1" topic_prefix="$2"
    [ -z "$sid" ] || [ -z "$topic_prefix" ] && return 1
    _itr_jq_available || return 1
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && return 0
    local tmp="$path.tmp.$$"
    jq \
        --arg prefix "$topic_prefix" \
        '.silence_debt |= map(
            if .status == "pending" and (.topic | startswith($prefix))
            then .status = "surfaced" else . end
         )' \
        "$path" > "$tmp" && mv "$tmp" "$path"
}

# --- Cost-model функции (timing/destructive/closing) ---
# Вынесены в sibling-библиотеку для модуляризации (Ф4). Подключаются здесь,
# чтобы все потребители intrusiveness-state-lib получали их прозрачно.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/intrusiveness-cost-lib.sh"
# --- Классификатор состояния (itr_compute_state) — вынесен в sibling-библиотеку (Ф4) ---
# Подключается после общих хелперов (_itr_state_path, _itr_jq_available);
# потребители получают функцию через эту библиотеку прозрачно.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/intrusiveness-classify-lib.sh"

# Write computed state to the session state file.
# Args: sid, state, confidence, reasons_csv
# Also increments distribution counter for the chosen state.
itr_set_state() {
    local sid="$1" state="$2" confidence="${3:-1}" reasons="${4:-}"
    [ -z "$sid" ] || [ -z "$state" ] && return 1
    _itr_jq_available || return 1
    case "$state" in
        focus|stuck|exploration|idle|distressed) ;;
        *) return 1 ;;
    esac
    itr_init_state "$sid"
    local path
    path=$(_itr_state_path "$sid")
    local now tmp
    now=$(_itr_now)
    tmp="$path.tmp.$$"
    # Split reasons by comma into a jq array.
    local reasons_json="[]"
    if [ -n "$reasons" ]; then
        reasons_json=$(printf '%s' "$reasons" | jq -R 'split(",") | map(select(length > 0))')
    fi
    jq \
        --arg state "$state" \
        --argjson conf "$confidence" \
        --argjson reasons "$reasons_json" \
        --arg now "$now" \
        '
        .state.current = $state
        | .state.confidence = $conf
        | .state.reasons = $reasons
        | .state.last_updated = $now
        | .state.distribution[$state] = ((.state.distribution[$state] // 0) + 1)
        ' "$path" > "$tmp" && mv "$tmp" "$path"
}

# Echo current state as "state|confidence|reasons_csv".
itr_get_state() {
    local sid="$1"
    [ -z "$sid" ] && { echo "idle|1|unknown"; return; }
    _itr_jq_available || { echo "idle|1|unknown"; return; }
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && { echo "idle|1|unknown"; return; }
    jq -r '
        (.state.current // "idle") + "|" +
        ((.state.confidence // 1) | tostring) + "|" +
        ((.state.reasons // []) | join(","))
    ' "$path" 2>/dev/null || echo "idle|1|unknown"
}

# Set a cost_hints field. Tracks silence_cost_max as running maximum.
# Args: sid, field, value
# Fields: timing_cost_current | silence_cost_max | last_destructive | last_closing_cost
itr_set_cost_hint() {
    local sid="$1" field="$2" value="$3"
    [ -z "$sid" ] || [ -z "$field" ] && return 1
    _itr_jq_available || return 1
    itr_init_state "$sid"
    local path
    path=$(_itr_state_path "$sid")
    local now tmp
    now=$(_itr_now)
    tmp="$path.tmp.$$"
    local is_numeric=false
    case "$field" in
        timing_cost_current|silence_cost_max|last_closing_cost) is_numeric=true ;;
    esac
    if [ "$is_numeric" = "true" ]; then
        # Clamp numeric values to 0..5
        local vnum
        vnum=$(printf '%s' "$value" | awk '{v=$0+0; if(v<0)v=0; if(v>5)v=5; print v}')
        if [ "$field" = "silence_cost_max" ]; then
            # Running max: only update if vnum > current
            jq \
                --arg field "$field" \
                --argjson v "$vnum" \
                --arg now "$now" \
                '
                .cost_hints[$field] = ([.cost_hints[$field] // 0, $v] | max)
                | .cost_hints.last_updated = $now
                ' "$path" > "$tmp" && mv "$tmp" "$path"
        elif [ "$field" = "timing_cost_current" ]; then
            # Set current AND pull timing_cost_peak as running max in one update.
            # Peak is the signal that survives to history.jsonl (current decays
            # between prompts).
            jq \
                --argjson v "$vnum" \
                --arg now "$now" \
                '
                .cost_hints.timing_cost_current = $v
                | .cost_hints.timing_cost_peak = ([.cost_hints.timing_cost_peak // 0, $v] | max)
                | .cost_hints.last_updated = $now
                ' "$path" > "$tmp" && mv "$tmp" "$path"
        else
            jq \
                --arg field "$field" \
                --argjson v "$vnum" \
                --arg now "$now" \
                '
                .cost_hints[$field] = $v
                | .cost_hints.last_updated = $now
                ' "$path" > "$tmp" && mv "$tmp" "$path"
        fi
    else
        jq \
            --arg field "$field" \
            --arg v "$value" \
            --arg now "$now" \
            '
            .cost_hints[$field] = $v
            | .cost_hints.last_updated = $now
            ' "$path" > "$tmp" && mv "$tmp" "$path"
    fi
}

# Echo a cost_hints field (numeric or string).
itr_get_cost_hint() {
    local sid="$1" field="$2"
    [ -z "$sid" ] || [ -z "$field" ] && { echo ""; return; }
    _itr_jq_available || { echo ""; return; }
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && { echo ""; return; }
    jq -r --arg field "$field" '.cost_hints[$field] // ""' "$path" 2>/dev/null || echo ""
}

# Echo remaining budget for a type (gentle or proactive). 0 if exhausted.
# v1.5.7 — AP2 affect prosthetic: when state=distressed, proactive budget is
# forced to 0 and gentle budget is halved (rounded down). This is infrastructural,
# not optional — the agent cannot override a distressed-state gate via scoring.
itr_remaining_budget() {
    local sid="$1" type="$2"
    [ -z "$sid" ] || [ -z "$type" ] && { echo 0; return; }
    _itr_jq_available || { echo 0; return; }
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && { echo "$ITR_DEFAULT_GENTLE_MAX"; return; }
    local state_current
    state_current=$(jq -r '.state.current // "idle"' "$path" 2>/dev/null || echo "idle")
    case "$type" in
        gentle)
            local raw
            raw=$(jq -r '[.budget.gentle_max - .budget.gentle_used, 0] | max' "$path" 2>/dev/null || echo 0)
            if [ "$state_current" = "distressed" ]; then
                echo $((raw / 2))
            else
                echo "$raw"
            fi
            ;;
        proactive)
            if [ "$state_current" = "distressed" ]; then
                echo 0
            else
                jq -r '[.budget.proactive_max - .budget.proactive_used, 0] | max' "$path" 2>/dev/null || echo 0
            fi
            ;;
        *)
            echo 0
            ;;
    esac
}

# --- Метрики/история/очистка сессии — вынесено в sibling-библиотеку (Ф4) ---
# Слой завершения сессии: финализация метрик, дайджест истории, очистка старых
# файлов состояния. Подключается после lifecycle-хелперов.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/intrusiveness-metrics-lib.sh"

# --- Форматирование/вывод (itr_format_context, itr_summary) — вынесено (Ф4) ---
# Презентационный слой: блок контекста для UserPromptSubmit + итог сессии.
# Подключается последним — использует API состояния выше через вызовы функций.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/intrusiveness-format-lib.sh"
