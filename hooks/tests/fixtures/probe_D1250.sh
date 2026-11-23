#!/usr/bin/env bash
set -u
# СУДИТ: hooks/session-collector.sh hooks/lib/transcript_window.py
# probe_D1250 — фоновый свод на Stop судит ход, закончившийся на СВОЁМ Stop, даже когда в расшифровке за его итогом уже
#   лежит начало следующего хода. Настоящий свод в изолированном мире (HOME, корень, состояние — в mktemp); в ходе опознан
#   класс без реестра носителей, итог хода — поле Stop `last_assistant_message`:
#   (к) контроль — расшифровка кончается итогом: в журнале `class-registry-fired` есть запись «owed»;
#   (п) за итогом лежат реплика следующего хода и его текст без опознания — запись «owed» всё равно есть.
# Код: 0 — обе ноги; 1 — (п) без записи (судился чужой ход); 2 — нет предмета или контроль не собрался.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$R/hooks"
[ -f "$H/session-collector.sh" ] && [ -f "$R/scripts/signal-precision-corpus.py" ] || exit 2
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
LAM="Это тот же класс дефектов. Чиню на месте."
rec_u() { jq -nc --arg u "$1" --arg t "$2" '{type:"user",uuid:$u,message:{role:"user",content:$t}}'; }
rec_a() { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
run() {  # <расшифровка> <имя мира> → число записей «owed» в журнале свода
    local w="$W/$2"
    mkdir -p "$w/home" "$w/state" "$w/root/scripts"
    cp "$R/scripts/signal-precision-corpus.py" "$w/root/scripts/" && ln -s "$H" "$w/root/hooks"
    jq -nc --arg p "$1" --arg c "$w" --arg l "$LAM" \
        '{hook_event_name:"Stop",session_id:"s-d1250",transcript_path:$p,cwd:$c,stop_hook_active:false,last_assistant_message:$l}' \
        | (cd "$w" && env HOME="$w/home" STATE_DIR="$w/state" CLAUDSOUL_ROOT="$w/root" CLAUDSOUL_REPO="$w/root" \
            PYTHONDONTWRITEBYTECODE=1 CLAUDE_CODE_SESSION_ID=d1250 bash "$H/session-collector.sh") >/dev/null 2>&1
    local n; n=$(grep -c '"state":"owed"' "$w/state/class-registry-fired-s-d1250.jsonl" 2>/dev/null); echo "${n:-0}"
}
{ rec_u u1 "первая реплика"; rec_a "работаю"; rec_a "$LAM"; } > "$W/turn.jsonl"
{ cat "$W/turn.jsonl"; rec_u u2 "вторая реплика"; rec_a "Дальше."; } > "$W/next.jsonl"
k=$(run "$W/turn.jsonl" k)
[ "$k" -ge 1 ] || { echo "рамка: на расшифровке, кончающейся итогом, свод долга не записал" >&2; exit 2; }
p=$(run "$W/next.jsonl" p)
# (б) Окно хода у владельца разбора входа (им читает ход и второй фоновый хук, `declared-problem-recorded.sh`): после
#   `transcript_stop_bound` окно — закончившийся ход, без реплики следующего.
win=$( . "$H/hook-input-lib.sh" 2>/dev/null; transcript_stop_bound "$W/next.jsonl" "$LAM"; transcript_turn_window "$W/next.jsonl" )
# (в) Граница действует только на свой файл: другой файл с тем же содержимым, прочитанный тем же процессом, — целиком
#   (первая редакция границы — смещение без файла — урезала бы и его).
cp "$W/next.jsonl" "$W/other.jsonl"
oth=$( . "$H/hook-input-lib.sh" 2>/dev/null; transcript_stop_bound "$W/next.jsonl" "$LAM"; transcript_turn_window "$W/other.jsonl" )
# (г) Файл не догнал итог (скептик opus, H1): итог дописывается через секунду после вызова границы — окно хода его
#   содержит (граница ждёт итог; не дождавшись — не ставится).
{ rec_u u1 "первая реплика"; rec_a "работаю"; } > "$W/lag.jsonl"
( sleep 1; rec_a "$LAM" >> "$W/lag.jsonl" ) &
lag=$( . "$H/hook-input-lib.sh" 2>/dev/null; transcript_stop_bound "$W/lag.jsonl" "$LAM"; wait; transcript_turn_window "$W/lag.jsonl" )
wait
miss=""
grep -q 'тот же класс' <<< "$lag" || miss="$miss итог, дописанный после вызова границы, выпал из окна хода;"
grep -q 'вторая реплика' <<< "$oth" || miss="$miss граница своего файла урезала чужой;"
[ "$p" -ge 1 ] || miss="$miss свод судил начало следующего хода (owed $p при контроле $k);"
grep -q 'ИТОГ\|тот же класс' <<< "$win" && ! grep -q 'вторая реплика' <<< "$win" \
    || miss="$miss окно хода после границы не равно закончившемуся ходу;"
[ -z "$miss" ] && { echo "фоновые читатели судят закончившийся ход и при начале следующего в файле (owed: контроль $k, с хвостом $p)"; exit 0; }
echo "не держится:$miss"
exit 1
