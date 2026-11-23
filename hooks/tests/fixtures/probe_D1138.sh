#!/usr/bin/env bash
# СУДИТ: hooks/user-correction-guard.sh
# probe_D1138 — реплика из одного вызова слеш-команды поправкой не пишется: её текст — служебные метки
# (`<command-message>`, `<command-name>`), а не речь собеседника. Красная (1), пока такая реплика попадает в журнал
# поправок (в мире: `/retro` 26 октября, `/save` 17 октября — 2 строки из 222). Повод в пробе — совпадение слов меток со
# словами агента до реплики (предметный признак). Контроль — настоящая поправка словами собеседника пишется. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/user-correction-guard.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1138.XXXXXX") || exit 2
fired() {  # fired <имя> <текст агента до реплики> <реплика> → число строк журнала поправок
    local d="$T/$1"; mkdir -p "$d/state"
    { jq -cn '{type:"user", origin:{kind:"human"}, message:{role:"user", content:"сохрани"}}'
      jq -cn --arg t "$2" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'
      jq -cn --arg t "$3" '{type:"user", origin:{kind:"human"}, message:{role:"user", content:$t}}'; } > "$d/t.jsonl"
    jq -cn --arg p "$d/t.jsonl" '{session_id:"p1", transcript_path:$p, tool_name:"Bash", tool_input:{command:"ls"}, hook_event_name:"PreToolUse"}' \
        | STATE_DIR="$d/state" bash "$HOOK" >/dev/null 2>&1
    local _k; _k=$(grep -c '' "$d/state/correction-fired-p1.jsonl" 2>/dev/null); echo "${_k:-0}"
}
[ "$(fired real 'Посчитана доля переработок в журнале: 13 процентов' 'Доля переработок посчитана неверно')" -ge 1 ] || exit 2
[ "$(fired cmd 'Закрыл серию; ошибки с двух попыток — предлагаю /retro по command-name' \
    $'<command-message>retro</command-message>\n<command-name>/retro</command-name>')" -eq 0 ] || exit 1
# Второе проявление (скептик D1138, L-4): правка файла, уведомление задачи, вторая правка того же файла — реплика,
# сказанная до первой правки, поправкой не пишется (контекстный признак «правка, затем реплика»).
d="$T/ctx"; mkdir -p "$d/state"
{ jq -cn '{type:"user", origin:{kind:"human"}, message:{role:"user", content:"запусти консолидацию накопленного за три недели"}}'
  jq -cn '{type:"assistant", message:{content:[{type:"tool_use", name:"Edit", input:{file_path:"/work/notes.md"}}]}}'
  jq -cn '{type:"user", origin:{kind:"task-notification"}, message:{role:"user", content:"<task-notification>\n<task-id>b1</task-id>\n</task-notification>"}}'; } > "$d/t.jsonl"
jq -cn --arg p "$d/t.jsonl" '{session_id:"p2", transcript_path:$p, tool_name:"Edit", tool_input:{file_path:"/work/notes.md"}, hook_event_name:"PreToolUse"}' \
    | STATE_DIR="$d/state" bash "$HOOK" >/dev/null 2>&1
_k=$(grep -c '' "$d/state/correction-fired-p2.jsonl" 2>/dev/null); [ "${_k:-0}" -eq 0 ] || exit 1
exit 0
