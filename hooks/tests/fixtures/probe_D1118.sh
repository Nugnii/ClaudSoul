#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh
# probe_D1118 — «за сессию гейт разбора срабатывал N раз» считает срабатывания (строки хода `turn:` журнала стража), а не
# все строки, где встречается род повода. Красная (1), пока в N входят строки `seen-at|`, `snap|`, `subj|`, `live|`,
# `target|` (D1108–D1109; скептик, L2: ход с одним срабатыванием дал 7). Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
DPR="$R/hooks/declared-problem-recorded.sh"; [ -f "$DPR" ] || exit 2
P="$SB/p"; gproj "$P" || exit 2
TR="$SB/tr.jsonl"; mk_tr "$TR" "Побочно вылезла дыра в hooks/x.sh и hooks/y.sh, чиню заодно."
cr s1 "$TR" "$P"
next_turn "$TR" "дальше" "Продолжаю по плану."
J="$ST/five-whys-s1.seen"
turns=$(awk -F'|' 'index($1, "turn:") == 1 { n++ } END { print n + 0 }' "$J" 2>/dev/null)   # поле 1 записи журнала, а не шаблон начала строки
[ "${turns:-0}" -ge 1 ] || exit 2
: > "$ST/stop-signals-s1.txt"
STATE_DIR="$ST" DPR_LOCAL_BACKLOG="$P/BACKLOG.md" bash "$DPR" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"s1","hook_event_name":"Stop","transcript_path":"$TR","cwd":"$P"}
PAYLOAD
n=$(grep -oE 'срабатывал [0-9]+ раз' "$ST/stop-signals-s1.txt" 2>/dev/null | grep -oE '[0-9]+' | head -1)
[ -n "$n" ] || exit 2
[ "$n" = "$turns" ] || { echo "сообщение назвало $n срабатываний при $turns строках хода" >&2; exit 1; }
echo "счёт срабатываний — по строкам хода"
exit 0
