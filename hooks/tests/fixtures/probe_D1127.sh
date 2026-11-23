#!/usr/bin/env bash
# СУДИТ: scripts/outcome.sh hooks/root-cause-lib.sh hooks/five-whys-gate.sh
# probe_D1127 — повод переработки файла с «;» в имени снимается правильным исходом. Красная (1), пока команда исхода режет
# токен повода по «;» (разделитель перечня токенов в контексте), пишет в `toks` обрезки, а отказ остаётся навсегда —
# тупик при верных действиях (третий скептик, M3). Положительный контроль — то же с обычным именем. Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
run() {   # <sid> <имя файла переработки> → решение стража после исхода
    P="$SB/p-$1"; gproj "$P" || return 2
    F="$P/hooks/$2"; seq 1 20 > "$F"
    jq -cn --arg p "$F" '{ts:"2026-10-26T09:00:00Z",path:$p,cycles:2}' > "$ST/rework-fired-$1.jsonl"
    jq -cn --arg p "$F" '{ts:"2026-10-26T09:01:00Z",path:$p,cycles:3}' >> "$ST/rework-fired-$1.jsonl"
    TR="$SB/tr-$1.jsonl"; mk_tr "$TR" "Правлю файл дальше."
    [ "$(dec "$(cw "$1" "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || return 2
    item "$P/BACKLOG.md" D9901 "hooks/x.sh:4"; no "$1" debt rework D9901 "$P"
    dec "$(cw "$1" "$P/hooks/x.sh" "$TR" "$P")"
}
[ "$(run s1 'ab.sh')" = allow ] || exit 2
[ "$(run s2 'a;b.sh')" = allow ] || { echo "повод переработки «a;b.sh» верным исходом не снят" >&2; exit 1; }
echo "«;» в пути повода не режет токен"
exit 0
