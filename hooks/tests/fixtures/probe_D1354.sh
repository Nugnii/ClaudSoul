#!/usr/bin/env bash
# СУДИТ: hooks/subagent-outcome.sh
# probe_D1354.sh — помощник, возобновлённый сообщением и сдавший отчёт, оборвавшимся не назван; настоящий обрыв
#   возобновлённого помощника назван.
#
# Повод (21 ноября 2026, D1354). Страж записал «субагент оборвался без ответа» про трёх возобновлённых помощников,
# сдавших отчёт вызовом `SubagentHandback`; готовые расшифровки тех же трёх он судит молча. Разбор 22 ноября: страж
# прочитал файл ДО того, как в него легли вызов сдачи и его результат, — последним стоял `Edit`, и ожидание D510,
# заведённое только на вызов сдачи, не включилось. Так же помечены 7 первых запусков с 6 ноября 2026.
# Гонка разыграна без таймингов, как в ноге T18 `hooks/tests/test_subagent_outcome.sh`: подменённый `sleep` дописывает
# хвост расшифровки, когда страж ждёт. Фоновый писатель с задержкой дал бы пробу, зеленеющую на прежнем коде, если
# страж под нагрузкой прочтёт файл позже писателя (`case-2026-10-27-probe-green-by-winning-a-race-with-background`).
# Форма расшифровки взята из мира (сессия ccfb1549, агент a7f81170): первый запуск со сдачей, реплика «The coordinator
# sent a message while you were working», служебные копии запроса `api-request-blob` с копией прежней сдачи, правка,
# затем вызов сдачи и результат с `toolEndsTurn`.
# Проверка результата: bash hooks/tests/fixtures/probe_D1354.sh → 0 — сдача после возобновления, дописанная после
#   события, тревоги не дала, а обрыв после возобновления назван; 1 — ложная тревога или пропущенный обрыв;
#   2 — не измерено (нет стража или jq; контроль готовой расшифровки не молчит).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$REPO/hooks/subagent-outcome.sh"
[ -f "$H" ] && command -v jq >/dev/null 2>&1 || { echo "нет стража или jq — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
SID="d1354probe-0000-4000-8000-000000000000"
PROJ="$W/proj"; mkdir -p "$PROJ/$SID/subagents" "$W/home"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_parent","name":"Agent","input":{}}]}}' > "$PROJ/$SID.jsonl"

a() { jq -nc --arg id "$1" --arg n "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$n,input:{}}]}}'; }
r() { jq -nc --arg id "$1" --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}'; }
delivered() { jq -nc --arg id "$1" '{type:"user",toolEndsTurn:true,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:"{\"success\":true,\"message\":\"Report delivered to your caller.\"}"}]}]}}'; }
blob() { jq -nc --arg id "$1" --arg n "$2" '{type:"api-request-blob",message:{role:"assistant",content:[{type:"thinking",thinking:"…"},{type:"tool_use",id:$id,name:$n,input:{}}]}}'; }

# Голова, общая обеим расшифровкам: первый запуск сдал отчёт, помощника возобновили сообщением, он правит файл.
head_of() {
    jq -nc '{type:"user",message:{role:"user",content:"Задача: поправь документ и сдай отчёт."}}'
    a toolu_b1 Bash; r toolu_b1 "ok"
    a toolu_h1 SubagentHandback; delivered toolu_h1
    jq -nc '{type:"user",message:{role:"user",content:"The coordinator sent a message while you were working:\nпоправь ещё раздел 2"}}'
    blob toolu_h1 SubagentHandback
    jq -nc '{type:"api-request-blob",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_h1",content:"Report delivered to your caller."}]}}'
    a toolu_e1 Edit; r toolu_e1 "The file docs/x.md has been updated successfully."
    blob toolu_e1 Edit
    jq -nc '{type:"api-request",timestamp:"2026-11-21T21:26:19.549Z"}'
    jq -nc '{type:"attachment",timestamp:"2026-11-21T21:26:25.091Z"}'
}

# judge <расшифровка> <хвост | -> [K] ; печатает очередь стража. Подменённый `sleep` считает свои вызовы и дописывает
#   хвост на K-м (по умолчанию 5-м): на первом сне починка, выходящая из ожидания при неизменном файле или ждущая один
#   раз, выглядела бы верной (находка M1 скептика 22 ноября 2026 — проба была зелёной на трёх неверных починках).
judge() {
    local ag="$PROJ/$SID/subagents/agent-$1.jsonl" st="$W/st-$1-${3:-5}" bin="$W/bin-$1-${3:-5}"
    mkdir -p "$st" "$bin"; cp "$W/$1.jsonl" "$ag"
    if [ "$2" = - ]; then
        printf '#!/bin/sh\nexit 0\n' > "$bin/sleep"
    else
        printf '#!/bin/sh\nn=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "%s/n"\n[ "$n" -eq %s ] && cat "%s" >> "%s"\nexit 0\n' \
            "$bin" "$bin" "${3:-5}" "$2" "$ag" > "$bin/sleep"
    fi
    chmod +x "$bin/sleep"
    jq -nc --arg s "$SID" --arg i "$1" --arg t "$ag" --arg p "$PROJ/$SID.jsonl" \
        '{session_id:$s,agent_id:$i,agent_transcript_path:$t,transcript_path:$p,cwd:"/tmp",hook_event_name:"SubagentStop",last_assistant_message:""}' \
      | HOME="$W/home" PATH="$bin:$PATH" STATE_DIR="$st" bash "$H" >/dev/null 2>&1
    cat "$st/pending-alerts.txt" 2>/dev/null || true
}
# verdict <ждём: тишина|тревога> <что подано> <очередь>
verdict() {
    if grep -q 'ОБОРВАЛСЯ' <<< "$3"; then got=тревога; else got=тишина; fi
    if [ "$got" = "$1" ]; then echo "$2: $got"; else echo "$2: $got, а ждали «$1»"; rc=1; fi
}

# Сдача после возобновления: на момент события в файле нет ни вызова сдачи, ни результата — их дописывает ожидание.
head_of > "$W/adone.jsonl"
{ a toolu_h2 SubagentHandback; delivered toolu_h2; } > "$W/tail.jsonl"
cat "$W/tail.jsonl" >> "$W/adone.jsonl"
head_of > "$W/arace.jsonl"
# Настоящий обрыв после возобновления: вызов прерван владельцем. Готовый — дописывать нечего; запоздалый — сам вызов и
# его результат ложатся после события (так легла последняя запись у 10 из 10 настоящих тревог), и рост файла ещё не
# «договорил»: судить надо заново (мутант «рост = успех» глушил бы 2 из 2 настоящих обрывов корпуса).
{ a toolu_b2 Bash; r toolu_b2 "The user doesn't want to proceed with this tool use. The tool use was rejected."; } > "$W/cuttail.jsonl"
{ head_of; cat "$W/cuttail.jsonl"; } > "$W/acut.jsonl"

# Контроль «рамка умеет молчать»: готовая расшифровка сдачи после возобновления тревоги не даёт ни на каком коде.
c=$(judge adone -)
[ -z "$c" ] || { echo "готовая расшифровка сдачи дала тревогу — фикстура не той формы; не измерено"; exit 2; }

rc=0
verdict тишина "сдача после возобновления, легшая после события (5-й сон)" "$(judge arace "$W/tail.jsonl" 5)"
verdict тишина "сдача после возобновления на пределе ожидания (20-й сон)" "$(judge arace "$W/tail.jsonl" 20)"
verdict тревога "сдача за пределом ожидания (21-й сон) — названный предел, ожидание не бесконечно" "$(judge arace "$W/tail.jsonl" 21)"
verdict тревога "обрыв после возобновления" "$(judge acut -)"
verdict тревога "обрыв после возобновления, легший после события (3-й сон)" "$(judge arace "$W/cuttail.jsonl" 3)"
exit "$rc"
