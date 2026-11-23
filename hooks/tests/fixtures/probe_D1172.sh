#!/usr/bin/env bash
# СУДИТ: hooks/timestamp-canary-check.sh
# probe_D1172 — инжект и канарейка судят одно понятие хода: подачу с инжектом 🕐. Инжект требует шапку на КАЖДОЙ подаче
# (реплика владельца, отчёт субагента, уведомление задачи), значит канарейка считает шапки и ищет их отсутствие в
# ответах после ПОСЛЕДНЕГО инжекта. Ноги: ряд «реплика → итог с шапкой» и шесть раз «отчёт → итог с шапкой» — тихо;
# шесть шапок на один инжект — тревога «шапок»; после отчёта итог без шапки — тревога «без таймштампа»; отчёт посреди
# хода и итог с его шапкой — тихо. Записи подачи — в форме живой расшифровки (замер D1172).
# Красная (1), пока хоть одна нога судит иначе; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/timestamp-canary-check.sh"
[ -f "$HOOK" ] && [ -f "$R/hooks/timestamp-inject.sh" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
owner()  { jq -nc --arg t "$1" '{type:"user", message:{role:"user", content:[{type:"text", text:$t}]}}'; }
peer()   { jq -nc '{type:"user", isMeta:true, origin:{kind:"peer"}, message:{role:"user", content:"Another Claude session sent a message: <agent-message from=\"a1\">отчёт</agent-message>"}}'; }
queued() { jq -nc '{type:"attachment", attachment:{type:"queued_command", commandMode:"prompt", origin:{kind:"peer"}, prompt:"<agent-message from=\"a2\">отчёт</agent-message>"}}'; }
inject() { jq -nc --arg c "🕐 $1 CET — этой шапкой начни ИТОГОВОЕ сообщение хода" '{type:"attachment", attachment:{type:"hook_additional_context", hookName:"UserPromptSubmit", content:[$c]}}'; }
say()    { jq -nc --arg t "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}'; }
run() { printf '{"session_id":"p1172-%s","transcript_path":"%s"}' "$2" "$1" \
    | CANARY_STATE_DIR="$T/state-$2" TIMESTAMP_INJECT_PATH="$R/hooks/timestamp-inject.sh" bash "$HOOK" 2>/dev/null; }
bad=0
# 1. Реплика и шесть отчётов, на каждом инжект и итог со своей шапкой — тихо.
F="$T/a.jsonl"; { owner "дальше"; inject "2026-10-28 18:00"; say "🕐 2026-10-28 18:00 CET
Итог."; for m in 01 02 03 04 05 06; do peer; inject "2026-10-28 18:$m"; say "🕐 2026-10-28 18:$m CET
Итог по отчёту."; done; } > "$F"
out=$(run "$F" a); [ -z "$out" ] || { echo "ряд отчётов с шапкой на каждом: тревога — ${out:0:120}"; bad=1; }
# 2. Шесть шапок на один инжект — тревога «шапок» (прежнее обещание).
F="$T/b.jsonl"; { owner "дальше"; inject "2026-10-28 18:00"; for m in 1 2 3 4 5 6; do say "🕐 2026-10-28 18:00 CET
Блок $m."; done; } > "$F"
out=$(run "$F" b); case "$out" in *шапок*) ;; *) echo "шесть шапок на один инжект: тревоги нет"; bad=1 ;; esac
# 3. После отчёта итог без шапки — тревога «без таймштампа» (брат: прежде бралась шапка из начала хода).
F="$T/c.jsonl"; { owner "дальше"; inject "2026-10-28 18:00"; say "🕐 2026-10-28 18:00 CET
Итог."; peer; inject "2026-10-28 18:10"; say "Итог по отчёту без шапки."; } > "$F"
out=$(run "$F" c); case "$out" in *"БЕЗ таймштампа"*) ;; *) echo "итог без шапки после отчёта: тревоги нет (${out:0:80})"; bad=1 ;; esac
# 4. Отчёт посреди хода (queued_command) с инжектом, итог с его шапкой — тихо.
F="$T/d.jsonl"; { owner "дальше"; inject "2026-10-28 18:00"; say "Смотрю."; queued; inject "2026-10-28 18:20"; say "🕐 2026-10-28 18:20 CET
Итог."; } > "$F"
out=$(run "$F" d); [ -z "$out" ] || { echo "отчёт посреди хода и итог с его шапкой: тревога — ${out:0:120}"; bad=1; }
exit "$bad"
