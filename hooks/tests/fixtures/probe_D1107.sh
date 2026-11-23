#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh
# probe_D1107 — сверщик на Stop пишет `recorded` только за исход, сверенный тем же правилом, что у стража (D1106),
# а правку бэклога без такого исхода — словом `touched` (решение владельца: развести значения). Красная (1), пока она
# даёт не `touched`. Положительный контроль: свежий пункт о ПРЕДМЕТЕ повода (переработанный файл), названный командой
# исхода, — `recorded`. Повод и журнал стража производит настоящий страж из входа детектора переработки (рамка
# outcome_frame_lib.sh): прежняя редакция писала токен руками в форме, которой страж не производит (D1110), и её
# положительный контроль отношение к поводу не судил вовсе. Рамка не собралась — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
DPR="$R/hooks/declared-problem-recorded.sh"
[ -f "$DPR" ] && command -v python3 >/dev/null 2>&1 || exit 2
SID=probe1107; NOW=$(date +%s)
iso() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
set_mtime() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }
turn() {   # <расшифровка> <реплика> <эпоха> — ход с отметкой времени (её читает сверщик на Stop)
    jq -cn --arg t "$2" --arg ts "$(iso "$3")" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]},timestamp:$ts}' >> "$1"
    jq -cn --arg ts "$(iso "$3")" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"правлю"}]},timestamp:$ts}' >> "$1"
}
key_of() { printf '%s\n' "$1" | cksum | awk '{print $1}'; }
run_dpr() {
    STATE_DIR="$ST" DPR_LOCAL_BACKLOG="$P/BACKLOG.md" bash "$DPR" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TR","cwd":"$P"}
PAYLOAD
}
out_of() { jq -r --arg k "$1" 'select(.key == $k and .signal == "rework") | .outcome' "$ST/outcome-${SID}.jsonl" 2>/dev/null | tail -1; }
P="$SB/p"; gproj "$P" || exit 2
TR="$SB/t.jsonl"; : > "$TR"
printf '{"ts":"2026-10-26T09:00:00Z","path":"%s","cycles":2}\n' "$P/hooks/x.sh" "$P/hooks/x.sh" > "$ST/rework-fired-${SID}.jsonl"
# Ход 1: страж увидел повод; бэклог тронут строкой без корня и адреса, исход не назван
turn "$TR" "разбери и почини" $((NOW - 3600))
cr "$SID" "$TR" "$P"
grep -q "^live|.*|rework:$P/hooks/x.sh:" "$ST/five-whys-${SID}.seen" 2>/dev/null || exit 2
printf '%s\n' '- ☐ **D9911** что-то' >> "$P/BACKLOG.md"; set_mtime "$P/BACKLOG.md" $((NOW - 60))
run_dpr
_o1=$(out_of "$(key_of "разбери и почини")")
[ "$_o1" = touched ] || { echo "правка бэклога без исхода записана как «${_o1:-ничего}», а не touched" >&2; exit 1; }
# Ход 2: свежий пункт о предмете повода (переработанный hooks/x.sh), исход назван командой
turn "$TR" "ещё раз" $((NOW - 30))
cr "$SID" "$TR" "$P"
item "$P/BACKLOG.md" D9912 "hooks/x.sh:4"
no "$SID" debt rework "D9912" "$P" || { echo "сверенный исход не записан командой — рамка не собралась" >&2; exit 2; }
run_dpr
[ "$(out_of "$(key_of "ещё раз")")" = recorded ] || { echo "сверенный исход названного хода не дал recorded" >&2; exit 1; }
echo "правка без исхода — touched, сверенный исход — recorded"
exit 0
