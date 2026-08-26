#!/usr/bin/env bash
# intrusiveness-classify-lib.sh — классификатор состояния L6-гейта (4-я ось 4D-гейта).
#
# Извлечено из intrusiveness-state-lib.sh (Ф4 — модуляризация монолита).
# itr_compute_state(sid, text) — чистый классификатор реплики пользователя:
# echoes "state|confidence|reasons"
# (приоритет distressed > stuck > focus > exploration > idle).
#
# Зависит от общих хелперов (_itr_state_path, _itr_jq_available) и ITR_STATE_DIR
# вызывающей библиотеки. Не предназначено для standalone-подключения.
#
# Локаль прибита к UTF-8 у каждого регистронезависимого сопоставления и у счётчика длины —
# причина та же, что в intrusiveness-cost-lib.sh: под локалью C GNU grep складывает регистр
# только для ASCII, поэтому «Не отвлекай» не совпадает с шаблоном «не отвлек», и реплика
# с заглавной буквы теряет состояние distressed/focus. На macOS этого не видно.

# Compute conversational state (v1.3.3) — 4th axis of the L6 4D gate.
# Pure classifier over a user prompt (+ optional session context for stuck detection).
# Echoes a pipe-delimited triple: "state|confidence|reason1,reason2,..."
#   state:      focus | stuck | exploration | idle
#   confidence: 1 (weak / default) .. 3 (multiple converging signals)
#   reasons:    comma-separated signal names that drove the classification
#
# Args: sid (optional — for reading recent-events context; "" to skip)
#       prompt_text (optional — reads stdin if absent)
#
# Priority: stuck > focus > exploration > idle
# (Most "defensive" state wins. Agent downgrades ladder based on this state.)
#
# Why pipe-delimited and not JSON:
#   Consumers (intrusiveness-tracker.sh, tests) parse with bash IFS split, no jq
#   on the read path. State is written to JSON via itr_set_state below.
itr_compute_state() {
    local sid="${1:-}"
    local text="${2:-}"
    # Читаем stdin, только если аргумент текста ВООБЩЕ не передан ($# < 2).
    # Было `[ -z "$text" ] && [ ! -t 0 ]` — два бага в одном условии:
    #   1. пустой второй аргумент неотличим от отсутствующего, поэтому явный
    #      вызов itr_compute_state "$sid" "" уходил читать stdin;
    #   2. «не tty» ≠ «данные придут»: если stdin — открытая труба, которую никто
    #      не закроет (типичный запуск из хук-раннера, CI, обёртки), `cat` висит
    #      вечно. Прогон hooks/tests/run_all.sh в таком окружении вставал намертво.
    if [ "$#" -lt 2 ] && [ ! -t 0 ]; then
        text=$(cat)
    fi
    if [ -z "$text" ]; then
        echo "idle|1|empty"
        return
    fi

    local score_focus=0 score_stuck=0 score_exploration=0 score_distressed=0
    local reasons_focus="" reasons_stuck="" reasons_exploration=""
    local reasons_idle="" reasons_distressed=""
    # Distressed classes bitmask: 1=frustration_phrase, 2=backward_cascade, 4=explicit_distress
    local distressed_classes=0

    # ─── distressed signals (v1.5.7 — affect prosthetic AP2) ──────────────
    # Interlocutor emotional distress ≠ technical stuck. Requires 2+ classes.
    # Class A: frustration / fatigue phrases
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(я[[:space:]]+устал|устала|надоело|сдаюсь|не[[:space:]]+могу[[:space:]]+больше|всё[[:space:]]+ломается|всё[[:space:]]+не[[:space:]]+так|выдохся|i[[:space:]]+am[[:space:]]+tired|i[[:space:]]+am[[:space:]]+frustrated|i'"'"'m[[:space:]]+done[[:space:]]+with[[:space:]]+this|exhausted|fed[[:space:]]+up|give[[:space:]]+up)'; then
        score_distressed=$((score_distressed + 2))
        distressed_classes=$((distressed_classes | 1))
        reasons_distressed="${reasons_distressed}${reasons_distressed:+,}frustration_phrase"
    fi
    # Class B: cross-hook BACKWARD cascade (≥3 confirmed gaps) from reformulation-tracker
    if [ -n "$sid" ]; then
        local _cascade_file="$ITR_STATE_DIR/cascading-events-${sid}.jsonl"
        if [ -f "$_cascade_file" ]; then
            local _backward_n
            _backward_n=$(wc -l < "$_cascade_file" 2>/dev/null | tr -d '[:space:]')
            case "$_backward_n" in
                ''|*[!0-9]*) _backward_n=0 ;;
            esac
            if [ "$_backward_n" -ge 3 ]; then
                score_distressed=$((score_distressed + 1))
                distressed_classes=$((distressed_classes | 2))
                reasons_distressed="${reasons_distressed}${reasons_distressed:+,}backward_cascade_${_backward_n}"
            fi
        fi
    fi
    # Class C: explicit distress markers (strong, can fire alone)
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(помоги[[:space:]]+хоть[[:space:]]+как|умоляю|please[[:space:]]+just[[:space:]]+help|i[[:space:]]+don'"'"'t[[:space:]]+know[[:space:]]+what[[:space:]]+to[[:space:]]+do|я[[:space:]]+в[[:space:]]+отчаянии|sos\b|помогите)'; then
        score_distressed=$((score_distressed + 3))
        distressed_classes=$((distressed_classes | 4))
        reasons_distressed="${reasons_distressed}${reasons_distressed:+,}explicit_distress"
    fi

    # ─── stuck signals ─────────────────────────────────────────────────────
    # Explicit frustration / repetition markers.
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(не[[:space:]]работает|не[[:space:]]получа|не[[:space:]]выход|ещё[[:space:]]раз|опять|снова|still[[:space:]]+(broken|not[[:space:]]working|failing)|same[[:space:]]+(error|problem|issue)|doesn'"'"'t[[:space:]]+work|won'"'"'t[[:space:]]+work)'; then
        score_stuck=$((score_stuck + 2))
        reasons_stuck="${reasons_stuck}${reasons_stuck:+,}frustration_phrase"
    fi
    # Punctuation-heavy frustration (multiple ?, !?).
    if grep -qE '(\?\?+|!\?|\?!)' <<< "$text"; then
        score_stuck=$((score_stuck + 1))
        reasons_stuck="${reasons_stuck}${reasons_stuck:+,}frustration_punct"
    fi
    # Session-context signal: recent ignored gentles (agent-side stuck hint).
    # Only if sid provided, state file exists, and jq available.
    if [ -n "$sid" ] && _itr_jq_available; then
        local _path
        _path=$(_itr_state_path "$sid")
        if [ -f "$_path" ]; then
            local recent_ignored
            recent_ignored=$(jq -r '
                [.events | .[-5:][] | select(.type=="gentle" and .outcome=="ignored")] | length
            ' "$_path" 2>/dev/null || echo 0)
            if [ "${recent_ignored:-0}" -ge 2 ]; then
                score_stuck=$((score_stuck + 1))
                reasons_stuck="${reasons_stuck}${reasons_stuck:+,}recent_ignored_gentles"
            fi
        fi
        # Cross-hook signal: consecutive Bash failures from error-tracker.sh
        # (file format: single-line integer count, same STATE_DIR).
        local _err_file="$ITR_STATE_DIR/error_count_${sid}"
        if [ -f "$_err_file" ]; then
            local _err_n
            _err_n=$(head -n 1 "$_err_file" 2>/dev/null | tr -d '[:space:]')
            case "$_err_n" in
                ''|*[!0-9]*) _err_n=0 ;;
            esac
            if [ "$_err_n" -ge 2 ]; then
                score_stuck=$((score_stuck + 2))
                reasons_stuck="${reasons_stuck}${reasons_stuck:+,}error_streak_${_err_n}"
            fi
        fi
    fi

    # ─── focus signals ─────────────────────────────────────────────────────
    local len
    len=$(printf '%s' "$text" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')
    if [ "${len:-0}" -gt 500 ]; then
        score_focus=$((score_focus + 1))
        reasons_focus="${reasons_focus}${reasons_focus:+,}long"
    fi
    local fence_count
    fence_count=$(printf '%s' "$text" | grep -c '^```' || true)
    if [ "${fence_count:-0}" -ge 4 ]; then
        score_focus=$((score_focus + 1))
        reasons_focus="${reasons_focus}${reasons_focus:+,}code_blocks"
    fi
    if grep -qE '(stack trace|traceback|error:|exception:|stderr:|\.ts[^a-zA-Z]|\.py[^a-zA-Z]|\.sh[^a-zA-Z]|\.js[^a-zA-Z]|\.tsx[^a-zA-Z]|\.go[^a-zA-Z]|\.rs[^a-zA-Z]|:[0-9]+[: ]|git (commit|push|pull|rebase|merge)|npm (install|run|test)|cargo (build|run|test))' <<< "$text"; then
        score_focus=$((score_focus + 1))
        reasons_focus="${reasons_focus}${reasons_focus:+,}tech_markers"
    fi
    # Explicit focus phrases — strong signal, +2.
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(не[[:space:]]отвлек|не[[:space:]]прерыва|в[[:space:]]работе|сосредото|focus[[:space:]]mode|deep[[:space:]]*work|in[[:space:]]the[[:space:]]zone|don'"'"'t[[:space:]]interrupt|do[[:space:]]not[[:space:]]interrupt|concentrat)'; then
        score_focus=$((score_focus + 2))
        reasons_focus="${reasons_focus}${reasons_focus:+,}focus_phrase"
    fi
    # Multi-step imperative.
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(сначала.*(потом|затем)|после[[:space:]]этого|step[[:space:]]*[0-9]|шаг[[:space:]]*[0-9]|first,.*then,|1\.[[:space:]].+2\.[[:space:]])'; then
        score_focus=$((score_focus + 1))
        reasons_focus="${reasons_focus}${reasons_focus:+,}multi_step"
    fi

    # ─── exploration signals ───────────────────────────────────────────────
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(а[[:space:]]что[[:space:]]если|а[[:space:]]если|what[[:space:]]if|would[[:space:]]it|could[[:space:]]we)'; then
        score_exploration=$((score_exploration + 1))
        reasons_exploration="${reasons_exploration}${reasons_exploration:+,}hypothetical"
    fi
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(альтернатив|alternative|варианты?\b|other[[:space:]]options)'; then
        score_exploration=$((score_exploration + 1))
        reasons_exploration="${reasons_exploration}${reasons_exploration:+,}alternatives"
    fi
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(можно[[:space:]]ли[[:space:]]иначе|по-другому|differently|another[[:space:]]way|other[[:space:]]way)'; then
        score_exploration=$((score_exploration + 1))
        reasons_exploration="${reasons_exploration}${reasons_exploration:+,}other_way"
    fi
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(подумаем|давай[[:space:]]подумаем|let'"'"'?s[[:space:]]think|brainstorm|обсудим)'; then
        score_exploration=$((score_exploration + 1))
        reasons_exploration="${reasons_exploration}${reasons_exploration:+,}brainstorm"
    fi
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(сравни|compare|trade-?offs?|pros[[:space:]]and[[:space:]]cons|плюсы[[:space:]]и[[:space:]]минусы)'; then
        score_exploration=$((score_exploration + 1))
        reasons_exploration="${reasons_exploration}${reasons_exploration:+,}compare"
    fi
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(гипотетическ|hypothetical)'; then
        score_exploration=$((score_exploration + 1))
        reasons_exploration="${reasons_exploration}${reasons_exploration:+,}hypothetical_explicit"
    fi

    # ─── idle markers (used only when no other state wins) ──────────────────
    if [ "${len:-0}" -lt 200 ]; then
        reasons_idle="${reasons_idle}${reasons_idle:+,}short"
    fi
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(что[[:space:]]дальше|что[[:space:]]там|статус|what.?s[[:space:]]next|progress|ещё[[:space:]]вопрос)'; then
        reasons_idle="${reasons_idle}${reasons_idle:+,}meta"
    fi

    # ─── decision (priority: distressed > stuck > focus > exploration > idle) ─
    local state confidence reasons
    # Count distinct distressed classes that fired.
    local distressed_class_count=0
    [ $((distressed_classes & 1)) -ne 0 ] && distressed_class_count=$((distressed_class_count + 1))
    [ $((distressed_classes & 2)) -ne 0 ] && distressed_class_count=$((distressed_class_count + 1))
    [ $((distressed_classes & 4)) -ne 0 ] && distressed_class_count=$((distressed_class_count + 1))
    # Fire distressed if 2+ classes OR explicit-distress class alone.
    if [ "$distressed_class_count" -ge 2 ] || [ $((distressed_classes & 4)) -ne 0 ]; then
        state="distressed"
        reasons="$reasons_distressed"
        if [ "$score_distressed" -ge 4 ]; then confidence=3
        elif [ "$score_distressed" -ge 2 ]; then confidence=2
        else confidence=1
        fi
    elif [ "$score_stuck" -ge 2 ]; then
        state="stuck"
        reasons="$reasons_stuck"
        if [ "$score_stuck" -ge 3 ]; then confidence=3
        else confidence=2
        fi
    elif [ "$score_focus" -ge 2 ]; then
        state="focus"
        reasons="$reasons_focus"
        if [ "$score_focus" -ge 3 ]; then confidence=3
        elif [ "$score_focus" -ge 2 ]; then confidence=2
        else confidence=1
        fi
    elif [ "$score_exploration" -ge 1 ]; then
        state="exploration"
        reasons="$reasons_exploration"
        if [ "$score_exploration" -ge 2 ]; then confidence=2
        else confidence=1
        fi
    else
        state="idle"
        reasons="${reasons_idle:-default}"
        confidence=1
    fi

    echo "${state}|${confidence}|${reasons}"
}

