#!/usr/bin/env bash
# СУДИТ: scripts/outcome.sh hooks/root-cause-lib.sh
# probe_D1139 — исход по находке хода не ложится на находку, у которой в этом ходе уже есть принятый исход. Красная (1),
# пока строка «показалось» о второй находке несёт и повод первой, уже снятой пунктом (в мире: `debt D1138`, через 14 с
# `disproved` с обоими поводами). Контроль — строка «показалось» несёт повод второй находки. Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/p"; gproj "$P" || exit 2
TR="$SB/tr.jsonl"; mk_tr "$TR" "Побочно вылезла дыра в разборе ключа в hooks/x.sh, чиню заодно."
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9901 "hooks/x.sh:4"
no s1 debt discovery D9901 "$P" || exit 2
jq -cn --arg t "Побочно вылезла ещё одна дыра: hooks/y.sh теряет последнюю строку при чтении, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
[ "$(dec "$(cw s1 "$P/hooks/y.sh" "$TR" "$P")")" = deny ] || exit 2
no s1 disproved discovery "вторая находка — не дефект: последняя строка пустая по формату" "$P" || exit 2
OJ="$ST/outcome-s1.jsonl"; [ -f "$OJ" ] || exit 2
first=$(jq -r 'select(.outcome == "debt" and .ref == "D9901") | .toks[]?' "$OJ" | head -1)
disp=$(jq -r 'select(.outcome == "disproved") | .toks[]?' "$OJ")
[ -n "$first" ] && grep -q . <<< "$disp" || exit 2
grep -qxF -- "$first" <<< "$disp" && { echo "«показалось» о второй находке легло и на первую, снятую пунктом" >&2; exit 1; }
grep -vqxF -- "$first" <<< "$disp" || exit 2
echo "исход ложится только на находку без принятого исхода"
exit 0
