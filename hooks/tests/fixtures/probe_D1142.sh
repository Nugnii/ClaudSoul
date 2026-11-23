#!/usr/bin/env bash
# СУДИТ: hooks/user-correction-guard.sh
# probe_D1142 — реплика владельца, набранная посреди хода, судится сборщиком поправок: харнесс кладёт её записью
# `type: attachment` (`attachment.type: queued_command`, текст — `attachment.prompt`, автор — `attachment.origin.kind`).
# Красная (1), пока поправка в такой записи в журнал поправок не ложится. Контроль — тот же текст записью `user`
# ложится, отчёт субагента той же формы (`origin.kind: peer`) — нет. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/user-correction-guard.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1142.XXXXXX") || exit 2
TXT='опять не то, ты снова сделал не так — переделай'
fired() {  # fired <имя> <последняя запись расшифровки, JSON> → число строк журнала поправок
    local d="$T/$1"; mkdir -p "$d/state"
    { jq -cn '{type:"user", origin:{kind:"human"}, message:{role:"user", content:"посчитай долю переработок в журнале"}}'
      jq -cn '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"Посчитал: 13 процентов."}]}}'
      printf '%s\n' "$2"; } > "$d/t.jsonl"
    jq -cn --arg p "$d/t.jsonl" '{session_id:"p1", transcript_path:$p, tool_name:"Bash", tool_input:{command:"ls"}, hook_event_name:"PreToolUse"}' \
        | STATE_DIR="$d/state" bash "$HOOK" >/dev/null 2>&1
    local _k; _k=$(grep -c '' "$d/state/correction-fired-p1.jsonl" 2>/dev/null); echo "${_k:-0}"
}
queued() { jq -cn --arg t "$TXT" --arg k "$1" \
    '{type:"attachment", attachment:{type:"queued_command", prompt:$t, commandMode:"prompt", origin:{kind:$k}}}'; }
[ "$(fired user "$(jq -cn --arg t "$TXT" '{type:"user", origin:{kind:"human"}, message:{role:"user", content:$t}}')")" -ge 1 ] || exit 2
[ "$(fired peer "$(queued peer)")" -eq 0 ] || exit 2
[ "$(fired queued "$(queued human)")" -ge 1 ] || exit 1
echo "реплика посреди хода судится как реплика"
exit 0
