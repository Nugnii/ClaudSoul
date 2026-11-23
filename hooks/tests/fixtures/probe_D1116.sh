#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D1116 — исход снимает отказ СВОЕГО повода, а не всех поводов того же вида в ходе. Красная (1), пока вторая
# находка того же хода (новый токен, другой файл) снимается исходом первой и получает память зачёта (скептик D1108,
# H2). Положительный контроль — первая находка снимается своим исходом. Рамка — 2.
# Ноги при взятии: тот же пункт, дописанный проявлением второй находки, после повторного исхода снимает и её (иначе
# запрет повтора `outcome.sh` запер бы агента); исход одного вида не снимает отказ другого вида того же хода.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/p"; gproj "$P" || exit 2
TR="$SB/tr.jsonl"; mk_tr "$TR" "Побочно вылезла дыра в разборе ключа в hooks/x.sh, чиню заодно."
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9901 "hooks/x.sh:4"
no s1 debt discovery D9901 "$P" || exit 2
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] && { echo "первая находка своим исходом не снялась — рамка" >&2; exit 2; }
jq -cn --arg t "Побочно вылезла ещё одна дыра: hooks/y.sh теряет последнюю строку при чтении, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
[ "$(dec "$(cw s1 "$P/hooks/y.sh" "$TR" "$P")")" = deny ] \
    || { echo "вторая находка того же хода снята исходом первой" >&2; exit 1; }
printf '%s\n' '  **Повод.** `hooks/y.sh:3` тоже ломается.' >> "$P/BACKLOG.md"
no s1 debt discovery D9901 "$P" || { echo "пункт, дописанный проявлением второй находки, исходом для неё отвергнут" >&2; exit 1; }
[ "$(dec "$(cw s1 "$P/hooks/y.sh" "$TR" "$P")")" = deny ] \
    && { echo "исход, принятый для второй находки, её отказ не снял" >&2; exit 1; }
# Брат на ступень выше: переработка x.sh и находка о y.sh в одном ходе; исход переработки не снимает отказ находки.
printf '{"ts":"2026-10-26T09:00:00Z","path":"%s","cycles":2}\n' "$P/hooks/x.sh" "$P/hooks/x.sh" > "$ST/rework-fired-s2.jsonl"
TR2="$SB/tr2.jsonl"; mk_tr "$TR2" "Побочно вылезла дыра: hooks/y.sh теряет последнюю строку, чиню заодно."
[ "$(dec "$(cw s2 "$P/hooks/x.sh" "$TR2" "$P")")" = deny ] || exit 2
grep -q "^live|.*|rework:" "$ST/five-whys-s2.seen" 2>/dev/null && grep -q "^live|.*|discovery:" "$ST/five-whys-s2.seen" 2>/dev/null || exit 2
item "$P/BACKLOG.md" D9902 "hooks/x.sh:5"
no s2 debt rework D9902 "$P" || exit 2
[ "$(dec "$(cw s2 "$P/hooks/x.sh" "$TR2" "$P")")" = deny ] \
    || { echo "исход вида «переработка» снял отказ находки того же хода" >&2; exit 1; }
no s2 debt discovery D9902 "$P" || exit 2
[ "$(dec "$(cw s2 "$P/hooks/x.sh" "$TR2" "$P")")" = deny ] && { echo "оба повода названы, а отказ не снят" >&2; exit 1; }
echo "исход снимает свой повод, а не все поводы вида в ходе и не поводы другого вида"
exit 0
