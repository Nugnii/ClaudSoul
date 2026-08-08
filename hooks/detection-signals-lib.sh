#!/usr/bin/env bash
# detection-signals-lib.sh — pure evaluator of pattern detection_signals (v0.3)
#
# Purpose: blocker-tier knowledge needs a relational pre-action check.
# Each blocker pattern declares detection_signals — named compositions of base
# matchers. At PreToolUse time, blocker-tier-check.sh calls ds_evaluate for
# every blocker pattern; first matching signal fires a silent additionalContext
# injection.
#
# Signal format (stored as JSON inside YAML block literal `detection_signals: |`):
#   [{"name":"...","all_of":[matcher, ...]}, ...]
#
# Base matchers (single-key dicts):
#   {"tool_matches": ["Edit","Write"]}            — current tool is one of
#   {"file_path_regex": "..."}                    — tool_input.file_path matches POSIX ERE
#   {"file_size_min_lines": 300}                  — wc -l of file_path ≥ N (0 if file missing)
#   {"prompt_contains": "..."}                    — last user prompt contains substring
#   {"tool_input_contains": "..."}                — JSON-stringified tool_input contains substring
#   {"tool_input_regex": "..."}                   — tool_input matches POSIX ERE под LC_ALL=C
#
# Почему появился regex по содержимому (v1.14.8). До него содержимое можно было
# сопоставлять ТОЛЬКО точной подстрокой, то есть сигнал умел перечислять известные
# формы и не умел выражать правило. Цена измерена: класс «не-ASCII символ вплотную
# к синтаксису оболочки» за одну сессию проявился ЧЕТЫРЬМЯ разными формами, блокер
# знал две из них списком и не сработал ни разу. Класс, описываемый правилом,
# а не перечнем, при списочном сигнале обречён ловиться постфактум столько раз,
# сколько у него форм.
#
# `LC_ALL=C` обязателен: сопоставление идёт по БАЙТАМ. Иначе предикат «есть не-ASCII»
# сам зависел бы от локали — GNU grep отвергает кириллический диапазон в C.UTF-8,
# и проверка против класса совершила бы ошибку этого же класса (так уже было).
#
# Compositors: {"all_of": [...]}, {"any_of": [...]} — may nest one level inside a signal.
#
# Contract of ds_evaluate:
#   ds_evaluate <pattern_file> <tool_name> <tool_input_json> <prompt_text>
#   Exit 0 + signal name on stdout  → a signal matched
#   Exit 1 + no output              → no signal matched (or pattern has none)
#
# This library has NO state of its own. Throttling, logging, injection — all in
# blocker-tier-check.sh.

set -uo pipefail

# jq is a hard dep. Without it, return no-match so the system degrades gracefully.
_ds_jq_available() {
    command -v jq >/dev/null 2>&1
}

# Extract detection_signals JSON array from pattern file YAML frontmatter.
# Echoes JSON (either a non-empty array or `[]`).
ds_extract_signals() {
    local pattern_file="$1"
    [ -f "$pattern_file" ] || { printf '[]\n'; return 0; }
    _ds_jq_available || { printf '[]\n'; return 0; }
    local fm
    fm=$(awk '/^---$/{n++; if (n==2) exit; next} n==1{print}' "$pattern_file")
    local block
    block=$(printf '%s\n' "$fm" | awk '
        BEGIN { in_block = 0 }
        /^detection_signals:[[:space:]]*\|[[:space:]]*$/ { in_block = 1; next }
        in_block {
            if ($0 ~ /^[^[:space:]]/) { exit }
            print
        }
    ')
    if [ -z "$block" ]; then
        printf '[]\n'
        return 0
    fi
    local json
    json=$(printf '%s\n' "$block" | jq -c '.' 2>/dev/null)
    if [ -z "$json" ] || [ "$json" = "null" ]; then
        printf '[]\n'
    else
        printf '%s\n' "$json"
    fi
}

# Quick boolean: does pattern declare `blocker: true` in frontmatter?
ds_has_blocker_flag() {
    local pattern_file="$1"
    [ -f "$pattern_file" ] || return 1
    awk '
        /^---$/ { n++; if (n == 2) exit; next }
        n == 1 && /^blocker:[[:space:]]*true[[:space:]]*$/ { found = 1; exit }
        END { exit (found ? 0 : 1) }
    ' "$pattern_file"
}

# Evaluate one node (either a composition or a base matcher). 0 = match, 1 = no match.
# Arguments: <node_json> <tool_name> <tool_input_json> <prompt>
# ds_code_only <tool_input> → та же полезная нагрузка без содержимого комментариев.
#
# Повод (D56). Сигналы сопоставляют содержимое правки подстрокой, и блокер переносимости
# дважды за сессию загорелся на КОММЕНТАРИИ — на тексте, где `date -j` и `stat -f`
# перечислены как запрещённые. То есть страж сработал на пояснении к правилу, а не на его
# нарушении. Это `pattern-guard-scope-blindness` внутри самого блокера; для команд тот же
# класс уже закрыт `command-scope-lib.sh` (вырезает кавычки и heredoc), здесь — эквивалент
# для содержимого правки.
#
# Правило комментария оболочки: решётка в начале строки, возможно после отступа. Решётка
# ВНУТРИ кода (`grep -c "#" f`) комментария не открывает, и код после неё обязан уцелеть —
# иначе страж начнёт пропускать настоящие нарушения, что хуже ложных срабатываний.
#
# Нагрузка приходит одной строкой (`jq -c`), перевод строки в ней — два символа `\n`,
# поэтому границей служит он, а не настоящий конец строки.
ds_code_only() {
    # Границей строки служит последовательность `\n`, а НЕ «любая обратная косая».
    # Первая версия резала `#` до ближайшей косой — и под ASCII-экранированием кириллица
    # (`\u0413…`) обрывала вырезание на первом же символе комментария, оставляя запрещённую
    # команду видимой. Проверка поймала это только потому, что гоняет обе кодировки.
    printf '%s' "${1:-}" | awk '{
        n = split($0, a, /\\n/)
        out = ""
        for (i = 1; i <= n; i++) {
            s = a[i]
            sub(/(^|")[[:space:]]*#.*$/, "\"", s)   # решётка в начале строки или значения
            out = out s (i < n ? "\\n" : "")
        }
        print out
    }'
}

ds_evaluate_node() {
    local node="$1" tool_name="$2" tool_input="$3" prompt="$4"
    _ds_jq_available || return 1
    local key
    key=$(printf '%s' "$node" | jq -r 'keys_unsorted[0] // empty' 2>/dev/null)
    [ -z "$key" ] && return 1

    case "$key" in
        all_of|any_of)
            local sub_count
            sub_count=$(printf '%s' "$node" | jq -r ".${key} | length" 2>/dev/null)
            [ -z "$sub_count" ] && return 1
            [ "$sub_count" -eq 0 ] && return 1
            local i sub res filter
            for (( i = 0; i < sub_count; i++ )); do
                filter=".${key}[${i}]"
                sub=$(printf '%s' "$node" | jq -c "$filter" 2>/dev/null)
                [ -z "$sub" ] && { [ "$key" = "all_of" ] && return 1 || continue; }
                ds_evaluate_node "$sub" "$tool_name" "$tool_input" "$prompt"
                res=$?
                if [ "$key" = "all_of" ]; then
                    [ "$res" -ne 0 ] && return 1
                else
                    [ "$res" -eq 0 ] && return 0
                fi
            done
            [ "$key" = "all_of" ] && return 0 || return 1
            ;;
        tool_matches)
            local match
            match=$(printf '%s' "$node" | jq -r --arg t "$tool_name" '.tool_matches | index($t) != null' 2>/dev/null)
            [ "$match" = "true" ] && return 0
            return 1
            ;;
        file_path_regex)
            local regex file_path
            regex=$(printf '%s' "$node" | jq -r '.file_path_regex' 2>/dev/null)
            [ -z "$regex" ] && return 1
            file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null)
            [ -z "$file_path" ] && return 1
            printf '%s' "$file_path" | grep -qE -- "$regex" && return 0
            return 1
            ;;
        tool_input_regex)
            local rx
            rx=$(printf '%s' "$node" | jq -r '.tool_input_regex' 2>/dev/null)
            [ -z "$rx" ] && return 1
            # LC_ALL=C — сопоставление по байтам, см. пояснение в шапке.
            ds_code_only "$tool_input" | LC_ALL=C grep -qE -- "$rx" && return 0
            return 1
            ;;
        file_size_min_lines)
            local threshold file_path line_count
            threshold=$(printf '%s' "$node" | jq -r '.file_size_min_lines' 2>/dev/null)
            [ -z "$threshold" ] && return 1
            file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null)
            if [ -n "$file_path" ] && [ -f "$file_path" ]; then
                line_count=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ')
            else
                line_count=0
            fi
            [ "${line_count:-0}" -ge "$threshold" ] && return 0
            return 1
            ;;
        prompt_contains)
            local needle
            needle=$(printf '%s' "$node" | jq -r '.prompt_contains' 2>/dev/null)
            [ -z "$needle" ] && return 1
            printf '%s' "$prompt" | grep -qF -- "$needle" && return 0
            return 1
            ;;
        tool_input_contains)
            local needle
            needle=$(printf '%s' "$node" | jq -r '.tool_input_contains' 2>/dev/null)
            [ -z "$needle" ] && return 1
            ds_code_only "$tool_input" | grep -qF -- "$needle" && return 0
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Evaluate one named signal. Extracts the all_of/any_of branch and delegates.
# Arguments: <signal_json> <tool_name> <tool_input_json> <prompt>
ds_evaluate_signal() {
    local signal="$1" tool_name="$2" tool_input="$3" prompt="$4"
    _ds_jq_available || return 1
    local op
    op=$(printf '%s' "$signal" | jq -r 'if has("all_of") then "all_of" elif has("any_of") then "any_of" else empty end' 2>/dev/null)
    [ -z "$op" ] && return 1
    local composition
    composition=$(printf '%s' "$signal" | jq -c "{${op}: .${op}}" 2>/dev/null)
    [ -z "$composition" ] && return 1
    ds_evaluate_node "$composition" "$tool_name" "$tool_input" "$prompt"
}

# Main entry. Evaluates every signal in pattern; on first match echoes name and exits 0.
# Arguments: <pattern_file> <tool_name> <tool_input_json> <prompt>
ds_evaluate() {
    local pattern_file="$1" tool_name="$2" tool_input="$3" prompt="$4"
    local signals
    signals=$(ds_extract_signals "$pattern_file")
    [ "$signals" = "[]" ] && return 1
    local count
    count=$(printf '%s' "$signals" | jq -r '. | length' 2>/dev/null)
    [ -z "$count" ] || [ "$count" -eq 0 ] && return 1
    local i signal name
    for (( i = 0; i < count; i++ )); do
        signal=$(printf '%s' "$signals" | jq -c ".[$i]" 2>/dev/null)
        [ -z "$signal" ] && continue
        name=$(printf '%s' "$signal" | jq -r '.name // ""' 2>/dev/null)
        if ds_evaluate_signal "$signal" "$tool_name" "$tool_input" "$prompt"; then
            printf '%s\n' "$name"
            return 0
        fi
    done
    return 1
}
