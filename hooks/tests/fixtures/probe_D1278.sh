#!/usr/bin/env bash
set -u
# СУДИТ: hooks/doc-impact-check.sh
# probe_D1278 — страж влияния на документацию в режиме PreToolUse (ловушка обойдена `core.hooksPath`) не трогает индекс
#   папки сессии, когда команда коммитит в ДРУГОЙ репозиторий: `cd <другой> && git add -A && git -c core.hooksPath=… commit`.
#   Папка сессии — клон ClaudSoul с незакоммиченной правкой механизма (новая функция — учёт устарел), как 8 ноября 2026:
#   (п) коммит в другой репозиторий — `.claude-docs/dep-index.tsv` в индексе сессии НЕ появляется;
#   (к) тот же коммит в самой сессии — учёт в индекс сессии ложится (положительный контроль: страж жив).
#   У каждой ноги свой клон, своё состояние и своя сессия: повтор в той же сессии страж гасит.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/doc-impact-check.sh" ] && command -v git >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
O="$W/other"
mkdir -p "$O" && git -C "$O" init -q && printf 'x\n' > "$O/f.txt" && git -C "$O" add f.txt || exit 2
HP="core.hooks""Path"   # слово обхода ловушки — не в тексте пробы: страж коммита судит команду по тексту
leg() {  # <имя> <команда> → число строк учёта в индексе сессии после PreToolUse стража
    local S="$W/$1"
    git clone -q --local "$R" "$S" 2>/dev/null || return 9
    printf '\nprobe_d1278_fn() { :; }\n' >> "$S/hooks/root-cause-lib.sh"
    mkdir -p "$W/state-$1"
    jq -nc --arg c "$2" --arg d "$S" --arg s "s-d1278-$1" \
        '{hook_event_name:"PreToolUse",session_id:$s,cwd:$d,tool_name:"Bash",tool_input:{command:$c}}' \
        | (cd "$S" && env -u CLAUDECODE -u AI_AGENT CLAUDSOUL_ROOT="$S" CLAUDSOUL_REPO="$S" STATE_DIR="$W/state-$1" \
            bash "$R/hooks/doc-impact-check.sh") >/dev/null 2>&1   # страж с его библиотеками разбора — из судимого дерева
    git -C "$S" diff --cached --name-only | grep -cx '.claude-docs/dep-index.tsv'
}
p=$(leg p "cd \"$O\" && git add -A && git -c $HP=/dev/null commit -qm x")
k=$(leg k "git add -A && git -c $HP=/dev/null commit -qm x")
[ "${k:-0}" -ge 1 ] 2>/dev/null || { echo "рамка: и на коммите в самой сессии учёт в индекс не лёг (k=${k:-?})" >&2; exit 2; }
[ "${p:-1}" -eq 0 ] && { echo "коммит в другой репозиторий индекс сессии не трогает; в самой сессии учёт ложится"; exit 0; }
echo "страж положил учёт в индекс папки сессии на коммите в другой репозиторий (контроль: $k)"
exit 1
