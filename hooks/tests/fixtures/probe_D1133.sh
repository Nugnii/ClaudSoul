#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D1133 — стоячий вид, снятый сверенным исходом, не получает ложного отказа, когда в том же ходе отказ пришёл по
# находке другого вида. Красная (1), пока цикл отказа стража пишет `deferred` стоячему виду безусловно, а с D1126 отказ
# поверх снятия ложится — вид висит в сводке открытого (четвёртый скептик, M1). Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
. "$R/hooks/root-cause-lib.sh" 2>/dev/null || exit 2
. "$R/hooks/lib/open-findings-lib.sh" 2>/dev/null || exit 2
[ -n "${RC_KINDS_RE:-}" ] && [ -n "${RC_OUTCOMES_ACTED:-}" ] || exit 2
P="$SB/p"; gproj "$P" || exit 2
mkdir -p "$P/src" && seq 1 20 > "$P/src/x.sh" && seq 1 20 > "$P/src/y.sh" || exit 2
printf '%s\n' '{"ts":"2026-10-26T10:00:00Z","snippet":"всё сломалось","hash":"h1"}' > "$ST/breakage-fired-s1.jsonl"
TR="$SB/tr.jsonl"; T0=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
jq -cn --arg ts "$T0" '{type:"user",uuid:"u1",message:{role:"user",content:[{type:"text",text:"после твоей правки всё сломалось, не работает — чини"}]},timestamp:$ts}' > "$TR"
jq -cn --arg ts "$T0" --arg t "Побочно вылезла дыра в разборе ключа, чиню заодно." '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]},timestamp:$ts}' >> "$TR"
cwp() { jq -cn --arg f "$1" --arg p "$TR" --arg d "$P" '{session_id:"s1", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Write", cwd:$d, tool_input:{file_path:$f, content:"x"}}' | ( cd "$P" && STATE_DIR="$ST" bash "$HOOK" 2>/dev/null ); }
stop() { ( cd "$P" && printf '{"session_id":"s1","hook_event_name":"Stop","transcript_path":"%s","cwd":"%s"}' "$TR" "$P" | STATE_DIR="$ST" DPR_LOCAL_BACKLOG="$P/BACKLOG.md" bash "$R/hooks/declared-problem-recorded.sh" >/dev/null 2>&1 ); }
[ "$(dec "$(cwp "$P/src/x.sh")")" = deny ] || exit 2
grep -q '"signal":"breakage","outcome":"deferred"' "$ST/outcome-s1.jsonl" 2>/dev/null || exit 2   # стоячий вид в ходе есть
item "$P/BACKLOG.md" D9901 "src/x.sh:4"; no s1 debt discovery D9901 "$P" || exit 2; no s1 debt breakage D9901 "$P" || exit 2
cwp "$P/src/x.sh" >/dev/null; stop
jq -cn --arg t "Побочно вылезла ещё одна дыра: последняя строка теряется при чтении, чиню заодно." '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
[ "$(dec "$(cwp "$P/src/y.sh")")" = deny ] || exit 2
no s1 disproved discovery "не дефект: строка читается" "$P" || exit 2
cwp "$P/src/y.sh" >/dev/null; stop
lst=$(OF_KINDS="$RC_KINDS_RE" OF_OUTCOMES="$RC_OUTCOMES_ACTED" of_open_list "$ST" 2>/dev/null) || exit 2   # сводка не отработала — рамка
open=$(printf '%s\n' "$lst" | cut -f2,3 | grep -c '^breakage')
[ "${open:-0}" = 0 ] || { echo "снятый стоячий вид получил ложный отказ и висит открытым" >&2; exit 1; }
echo "стоячий вид после снятия ложного отказа не получает"
exit 0
