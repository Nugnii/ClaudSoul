#!/usr/bin/env bash
# СУДИТ: hooks/user-correction-guard.sh
# probe_D1018.sh — страж поправок не останавливает подтверждением вызов агента (D1018).
#
# Коды: 0 — вызов агента (в payload есть agent_id) проходит без permissionDecision, а родитель на ту же
#       реплику его получает; 1 — агенту выставлен отказ уровня 4 (дефект D1018: агент ждёт человека, к
#       которому реплика не обращена); 2 — судить нечем: нет стража или jq, либо страж молчит и родителю.
# Повод — 21 октября 2026: волна из четырёх агентов-проверяющих простояла по 210 минут на первом же вызове.
# У вызова агента transcript_path родительский, страж прочитал реплику владельца главной сессии как
# поправку агенту и выставил ask; ключ дросселя с D463 включает участника, поэтому каждый новый агент
# получает свой ask. Ответить мог только человек, а он спал. Корень: уровень 4 стоит на признаке, чьё
# последствие зависит от участника, — родителю пауза, агенту запрос к отсутствующему человеку.
# Рамка взята у probe_D463.sh: та же форма расшифровки и вызова.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$HOOKS_DIR/user-correction-guard.sh"
[ -f "$HOOK" ] || { echo "probe_D1018: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D1018: нет jq" >&2; exit 2; }

T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
TR="$T/t.jsonl"
jq -cn --arg t "я же говорил, так делать не надо, переделай" \
   '{type:"user", origin:{kind:"human"}, message:{role:"user", content:[{type:"text", text:$t}]}}' > "$TR"

call() { # $1 — agent_id (пусто = родитель), $2 — свой каталог состояния, чтобы дроссели не мешали друг другу
    mkdir -p "$T/$2"
    jq -cn --arg tp "$TR" --arg a "${1:-}" \
      'if $a == "" then {session_id:"probe-d1018", transcript_path:$tp, tool_name:"Bash", tool_input:{command:"echo hi"}}
       else {session_id:"probe-d1018", transcript_path:$tp, agent_id:$a, tool_name:"Bash", tool_input:{command:"echo hi"}} end' \
    | STATE_DIR="$T/$2" bash "$HOOK" 2>/dev/null
}
asks() { grep -q '"permissionDecision"' <<< "${1:-}"; }

# Положительный контроль: родителю на свежем состоянии страж обязан заговорить.
asks "$(call "" parent)" || { echo "probe_D1018: контроль — страж молчит и родителю, судить нечем" >&2; exit 2; }
if asks "$(call "agent-1" agent)"; then
    echo "probe_D1018: дефект — агенту выставлен отказ уровня 4 по реплике, обращённой к родителю" >&2
    exit 1
fi
exit 0
