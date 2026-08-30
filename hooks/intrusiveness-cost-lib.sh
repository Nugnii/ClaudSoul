#!/usr/bin/env bash
# intrusiveness-cost-lib.sh — cost-model функции L6-гейта интрузивности.
#
# Извлечено из intrusiveness-state-lib.sh (Ф4 — модуляризация монолита).
# Три оси: timing (стоимость прерывания), destructive (необратимость команды),
# closing (давление невысказанного silence_debt на закрытии сессии).
#
# Подключается intrusiveness-state-lib.sh ПОСЛЕ её общих хелперов
# (_itr_state_path, _itr_jq_available) — itr_compute_closing_cost зовёт их
# в момент вызова. Не предназначено для standalone-подключения.
#
# Локаль прибита к UTF-8 у каждого регистронезависимого сопоставления и у счётчика длины.
# Различие систем измерено: под локалью C (типична для контейнеров, cron и CI) GNU grep
# складывает регистр только для ASCII — «Сначала» не совпадает с шаблоном «сначала», и ось
# multi-step молча даёт ноль. Тот же C ломает `wc -m`: он считает байты, и русский текст
# в 300 символов выглядит как 449, то есть порог длины срабатывает раньше времени.
# На macOS BSD grep складывает Unicode независимо от локали, поэтому расхождение видно
# только на Linux — и ровно поэтому его нельзя поймать на машине разработки.

# Compute timing_cost (0..5) from a user prompt text.
# Pure function: reads stdin if no arg, echoes a single integer.
#
# Rules (additive, then clamped to 0..5):
#   +1  length > 500 chars (deep-work signal: user wrote something substantial)
#   +1  contains >= 2 fenced code blocks (```...```) — technical payload
#   +1  contains technical markers (stack trace, error:, file paths .ts/.py/.sh/.js,
#       line refs like :123, Bash commands git/npm/cargo)
#   +2  explicit focus markers ("не отвлекай", "в работе", "focus", "concentrate",
#       "не прерывай", "deep work", "flow")
#   +1  multi-step imperative ("сначала", "потом", "затем", "после этого",
#       "step 1", "step 2", "first,", "then,")
#
# Rationale: distinguishes "quick question" (→ 0, gentle OK) from "don't interrupt
# me, I'm mid-task with code" (→ 4-5, gentle expensive). Matches architecture.md §L6
# timing_cost axis (out of cost-of-speaking 5-axis model).
itr_compute_timing_cost() {
    local text="${1:-}"
    if [ -z "$text" ] && [ ! -t 0 ]; then
        text=$(cat)
    fi
    [ -z "$text" ] && { echo 0; return; }
    local cost=0 len
    # length (wc -m counts characters; fallback to bytes if multi-byte problems)
    len=$(printf '%s' "$text" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')
    [ "${len:-0}" -gt 500 ] && cost=$((cost + 1))
    # >= 2 fenced code blocks (count opening ``` — every pair = one block)
    local fence_count
    fence_count=$(printf '%s' "$text" | grep -c '^```' || true)
    [ "${fence_count:-0}" -ge 4 ] && cost=$((cost + 1))   # 4 lines = 2 blocks
    # technical markers (any of these = +1)
    if grep -qE '(stack trace|traceback|error:|exception:|stderr:|\.ts[^a-zA-Z]|\.py[^a-zA-Z]|\.sh[^a-zA-Z]|\.js[^a-zA-Z]|\.tsx[^a-zA-Z]|\.go[^a-zA-Z]|\.rs[^a-zA-Z]|:[0-9]+[: ]|git (commit|push|pull|rebase|merge)|npm (install|run|test)|cargo (build|run|test))' <<< "$text"; then
        cost=$((cost + 1))
    fi
    # explicit focus markers (+2)
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(не отвлек|не прерыва|в работе|сосредото|focus mode|deep[[:space:]]*work|in[[:space:]]*the[[:space:]]*zone|don'"'"'t interrupt|do not interrupt|concentrat)'; then
        cost=$((cost + 2))
    fi
    # multi-step imperative (+1)
    if printf '%s' "$text" | LC_ALL=C.UTF-8 grep -qiE '(сначала.*(потом|затем)|после этого|step[[:space:]]*[0-9]|шаг[[:space:]]*[0-9]|first,.*then,|1\.[[:space:]].+2\.[[:space:]])'; then
        cost=$((cost + 1))
    fi
    # Clamp 0..5
    [ "$cost" -gt 5 ] && cost=5
    [ "$cost" -lt 0 ] && cost=0
    echo "$cost"
}

# Compute destructive_cost (0..5) from a Bash command string.
# Pure function. Used by PreToolUse:Bash hook to decide if silence about
# concerns would be costly (irreversible action = high silence_cost).
#
# Rules (return highest match, not additive — one catastrophic pattern is enough):
#   5 — truly irreversible, wide blast: rm -rf /, dd if=* of=/dev/sd*,
#       DROP DATABASE, TRUNCATE TABLE, DELETE FROM without WHERE, mkfs.*
#   4 — dangerous but recoverable with effort: rm -rf paths, git push --force,
#       git reset --hard, git branch -D main|master|develop
#   3 — moderate risk: rm -r of non-trivial dirs, DROP TABLE (single),
#       git push --force-with-lease, force-overwriting config
#   0 — everything else (safe by default)
#
# Note: does NOT decide whether to block — only emits the cost signal.
# The PreToolUse hook + L6 gate decide action based on this + context.
itr_compute_destructive_cost() {
    local cmd="${1:-}"
    if [ -z "$cmd" ] && [ ! -t 0 ]; then
        cmd=$(cat)
    fi
    [ -z "$cmd" ] && { echo 0; return; }
    # Level 5: catastrophic
    if grep -qE '(^|[[:space:]]|;|&&|\|\|)(rm[[:space:]]+-rf?[[:space:]]+(/|\$HOME|\$\{HOME\}|~[[:space:]]|~$|/\*))' <<< "$cmd"; then
        echo 5; return
    fi
    if printf '%s' "$cmd" | LC_ALL=C.UTF-8 grep -qiE '(DROP[[:space:]]+DATABASE|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(;|$))'; then
        echo 5; return
    fi
    if grep -qE '(dd[[:space:]]+.*of=/dev/(sd|nvme|disk|hda)|mkfs\.[a-z0-9]+[[:space:]]+/dev/)' <<< "$cmd"; then
        echo 5; return
    fi
    # --force-with-lease is checked BEFORE --force so plain --force doesn't shadow it.
    # Split explicitly because BSD grep (macOS) lacks negative lookahead.
    local has_force_with_lease=0 has_plain_force=0
    if grep -qE 'git[[:space:]]+push[[:space:]]+.*--force-with-lease' <<< "$cmd"; then
        has_force_with_lease=1
    fi
    if [ "$has_force_with_lease" -eq 0 ]; then
        if grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force([[:space:]]|$)|-f([[:space:]]|$))' <<< "$cmd"; then
            has_plain_force=1
        fi
    fi
    # Level 4: dangerous, recoverable with effort.
    # rm -rf / rm -fr / rm -r -f / rm -f -r (any order) — but NOT plain rm -r.
    if grep -qE '(^|[[:space:]]|;|&&|\|\|)rm[[:space:]]+(-[a-zA-Z]*rf[a-zA-Z]*|-[a-zA-Z]*fr[a-zA-Z]*)[[:space:]]+[^-]' <<< "$cmd"; then
        echo 4; return
    fi
    if grep -qE '(^|[[:space:]]|;|&&|\|\|)rm[[:space:]]+-r[[:space:]]+-f[[:space:]]+|(^|[[:space:]]|;|&&|\|\|)rm[[:space:]]+-f[[:space:]]+-r[[:space:]]+' <<< "$cmd"; then
        echo 4; return
    fi
    if [ "$has_plain_force" -eq 1 ]; then
        echo 4; return
    fi
    if grep -qE 'git[[:space:]]+reset[[:space:]]+--hard' <<< "$cmd"; then
        echo 4; return
    fi
    if grep -qE 'git[[:space:]]+branch[[:space:]]+-D[[:space:]]+(main|master|develop|release)' <<< "$cmd"; then
        echo 4; return
    fi
    # Level 3: moderate
    if printf '%s' "$cmd" | LC_ALL=C.UTF-8 grep -qiE 'DROP[[:space:]]+TABLE'; then
        echo 3; return
    fi
    if [ "$has_force_with_lease" -eq 1 ]; then
        echo 3; return
    fi
    # rm -r (plain recursive, no -f) on a non-flag non-root target
    if grep -qE '(^|[[:space:]]|;|&&|\|\|)rm[[:space:]]+-r[[:space:]]+[^-/]' <<< "$cmd"; then
        echo 3; return
    fi
    echo 0
}

# Compute closing_cost (0..5) for end-of-session silence pressure.
# When a session closes with pending high-value silence_debt, the cost of
# NOT surfacing it grows (next session may not reach the same state).
# Args: sid
#
# Rules:
#   base 2 if ANY pending silence_debt
#   +1 per pending debt item with silence_cost >= 3 (cap at +3)
#   clamped to 0..5
itr_compute_closing_cost() {
    local sid="$1"
    [ -z "$sid" ] && { echo 0; return; }
    _itr_jq_available || { echo 0; return; }
    local path
    path=$(_itr_state_path "$sid")
    [ ! -f "$path" ] && { echo 0; return; }
    local pending high
    pending=$(jq -r '[.silence_debt[] | select(.status=="pending")] | length' "$path" 2>/dev/null || echo 0)
    high=$(jq -r '[.silence_debt[] | select(.status=="pending" and .silence_cost >= 3)] | length' "$path" 2>/dev/null || echo 0)
    [ "${pending:-0}" -eq 0 ] && { echo 0; return; }
    local cost=2
    local bonus="${high:-0}"
    [ "$bonus" -gt 3 ] && bonus=3
    cost=$((cost + bonus))
    [ "$cost" -gt 5 ] && cost=5
    echo "$cost"
}

