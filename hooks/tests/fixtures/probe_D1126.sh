#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D1126 — отказ второй находки хода, отказанной после снятия первой, виден в журнале исходов: последний исход пары
# (ход, вид) — deferred. Красная (1), пока единица журнала — пара (ход, вид), а единица снятия — повод (D1116): после
# recorded первой находки отказ второй отбрасывается, и замер считает ход сверенным (третий скептик, M2). Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/p"; gproj "$P" || exit 2
# Ход с отметкой времени — её читает сверщик на Stop (нога (б)). Путей в тексте находок нет: путь вида `hooks/…` сверщик
# принял бы за предмет из дерева ClaudSoul («не тот носитель»), и путь «носитель тронут» в рамке был бы мёртв; по той же
# причине рабочие файлы и адрес пункта — в `src/`, а не в `hooks/`.
mkdir -p "$P/src" && seq 1 20 > "$P/src/x.sh" && seq 1 20 > "$P/src/y.sh" || exit 2
TR="$SB/tr.jsonl"; T0=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
jq -cn --arg ts "$T0" '{type:"user",message:{role:"user",content:[{type:"text",text:"чини"}]},timestamp:$ts}' > "$TR"
jq -cn --arg ts "$T0" --arg t "Побочно вылезла дыра в разборе ключа, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]},timestamp:$ts}' >> "$TR"
[ "$(dec "$(cw s1 "$P/src/x.sh" "$TR" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9901 "src/x.sh:4"; no s1 debt discovery D9901 "$P" || exit 2
[ "$(dec "$(cw s1 "$P/src/x.sh" "$TR" "$P")")" = deny ] && exit 2
jq -cn --arg t "Побочно вылезла ещё одна дыра: последняя строка теряется при чтении, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
[ "$(dec "$(cw s1 "$P/src/y.sh" "$TR" "$P")")" = deny ] || exit 2
last=$(jq -r 'select(.signal == "discovery" and ((.key | tostring) | startswith("manual-") | not)) | .outcome' "$ST/outcome-s1.jsonl" 2>/dev/null | tail -1)
[ "$last" = deferred ] || { echo "отказ второй находки не лёг: последний исход пары — «${last}»" >&2; exit 1; }
# (б) Сверщик на Stop не закрывает этот отказ ни сверенной строкой ПЕРВОЙ находки, ни правкой бэклога, сделанной до отказа.
STATE_DIR="$ST" DPR_LOCAL_BACKLOG="$P/BACKLOG.md" bash "$R/hooks/declared-problem-recorded.sh" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"s1","hook_event_name":"Stop","transcript_path":"$TR","cwd":"$P"}
PAYLOAD
last=$(jq -r 'select(.signal == "discovery" and ((.key | tostring) | startswith("manual-") | not)) | .outcome' "$ST/outcome-s1.jsonl" 2>/dev/null | tail -1)
[ "$last" = deferred ] || { echo "(б) сверщик на Stop закрыл отказ второй находки чужим исходом: «${last}»" >&2; exit 1; }
echo "отказ второй находки виден"
exit 0
