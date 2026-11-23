#!/usr/bin/env bash
# СУДИТ: hooks/bulk-copy-guard.sh hooks/internal-doc-leak-guard.sh hooks/partial-read-guard.sh
# probe_D457.sh — состояние с предметом «действие вызывающего» ключуется актором, и это
# судится ПОВЕДЕНИЕМ, а не наличием слова в исходнике.
#
# Предмет. Файл, который гейтит ДОСТАВКУ («этому вызывающему уже показали»), обязан
# ключеваться актором: иначе первый сработавший гасит сообщение всем остальным, и владелец
# не видит того, что показали субагенту. Проба гоняет четырёх носителей ДВАЖДЫ — сперва с
# `agent_id`, потом без него, — и требует, чтобы ВЛАДЕЛЕЦ заговорил после субагента.
#
# Почему проба, а не grep по `resolve_actor_suffix`: греп зеленеет от НАПИСАННОГО СЛОВА.
# Он был бы зелён и на правке, легшей в мёртвую ветку, — а такая в этой работе случилась
# (backlog-touch-check, суффикс в ветке без библиотеки; тесты остались зелёными, поймал
# прогон). Слово в исходнике и поведение в мире — разные вещи.
#
# Коды: 0 — дефекта нет; 1 — воспроизведён (назван носитель); 2 — судить нечем (не сработал
#       положительный контроль: субагент молчит, то есть признак не совпал вовсе).
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "probe_D457: нет jq" >&2; exit 2; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FAILED=""

speaks() { [ -n "$(printf '%s' "${1:-}" | tr -d '[:space:]')" ]; }

# Носитель зовётся так: <имя> <функция-вызова>. Функция берёт agent_id первым аргументом
# (пусто — родитель) и печатает вывод хука.
check() { # $1 имя носителя, $2 имя функции вызова
    local name="$1" fn="$2" out_sub out_par
    out_sub=$("$fn" "probe-sub")
    if ! speaks "$out_sub"; then
        echo "probe_D457: контроль — $name молчит и субагенту, судить нечем" >&2
        exit 2
    fi
    out_par=$("$fn" "")
    if ! speaks "$out_par"; then
        FAILED="${FAILED}${FAILED:+, }$name"
    fi
}

# --- носитель 1: partial-read-guard (маркер «этот файл уже читали частично») ---
mkdir -p "$T/s1"; seq 1 200 > "$T/big.txt"
prg() { jq -cn --arg f "$T/big.txt" --arg a "${1:-}" \
    'if $a == "" then {session_id:"p1", tool_name:"Read", tool_input:{file_path:$f, limit:20}, tool_response:{}}
     else {session_id:"p1", agent_id:$a, tool_name:"Read", tool_input:{file_path:$f, limit:20}, tool_response:{}} end' \
  | STATE_DIR="$T/s1" bash "$HOOKS_DIR/partial-read-guard.sh" 2>/dev/null; }
check partial-read-guard prg

# --- носитель 2: user-correction-guard (ask на поправку собеседника) ---
mkdir -p "$T/s2"
jq -cn --arg t "я же говорил, так делать не надо, переделай" \
   '{type:"user", origin:{kind:"human"}, message:{role:"user", content:[{type:"text", text:$t}]}}' > "$T/tr.jsonl"
ucg() { jq -cn --arg tp "$T/tr.jsonl" --arg a "${1:-}" \
    'if $a == "" then {session_id:"p2", transcript_path:$tp, tool_name:"Bash", tool_input:{command:"echo hi"}}
     else {session_id:"p2", transcript_path:$tp, agent_id:$a, tool_name:"Bash", tool_input:{command:"echo hi"}} end' \
  | STATE_DIR="$T/s2" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null; }
# Носитель 2 снят с проверки D1018 (22 октября 2026): агенту страж поправок молчит по замыслу — реплика обращена к
# родителю, — и «показанное субагенту гасит владельцу» у него невозможно: субагенту не показывается ничего. Порядок
# «агент первым, затем владелец» держат probe_D463.sh и probe_D1018.sh. Функция `ucg` оставлена как рамка носителя.

# --- носитель 3: bulk-copy-guard (ask на массовое копирование) ---
mkdir -p "$T/s3" "$T/src"; : > "$T/src/a.txt"
bcg() { jq -cn --arg s "$T/src" --arg a "${1:-}" \
    'if $a == "" then {session_id:"p3", tool_name:"Bash", tool_input:{command:("cp -r " + $s + " /tmp/probe_d457_dst")}}
     else {session_id:"p3", agent_id:$a, tool_name:"Bash", tool_input:{command:("cp -r " + $s + " /tmp/probe_d457_dst")}} end' \
  | STATE_DIR="$T/s3" bash "$HOOKS_DIR/bulk-copy-guard.sh" 2>/dev/null; }
check bulk-copy-guard bcg

# --- носитель 4: internal-doc-leak-guard (ask на запись внутренней заметки наружу) ---
mkdir -p "$T/s4"
idl() { jq -cn --arg a "${1:-}" \
    'if $a == "" then {session_id:"p4", tool_name:"Write", tool_input:{file_path:"/tmp/Lawyer_Track/probe.md", content:"Для адвоката: внутренняя заметка"}}
     else {session_id:"p4", agent_id:$a, tool_name:"Write", tool_input:{file_path:"/tmp/Lawyer_Track/probe.md", content:"Для адвоката: внутренняя заметка"}} end' \
  | STATE_DIR="$T/s4" bash "$HOOKS_DIR/internal-doc-leak-guard.sh" 2>/dev/null; }
check internal-doc-leak-guard idl

if [ -n "$FAILED" ]; then
    echo "probe_D457: дефект — показанное субагенту гаснет у владельца: $FAILED" >&2
    exit 1
fi
exit 0
