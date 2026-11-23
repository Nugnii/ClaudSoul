#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/rework-detector.sh
# probe_D1289 — правки одного файла из одного ответа модели судятся как одна: ступень переработки, поднятая первой
# правкой ответа (запись детектора несёт `message.id` этого ответа), не отклоняет остальные правки того же ответа; в
# СЛЕДУЮЩЕМ ответе отказ, как прежде. Повод (9 ноября 2026, ProjectA, B566): пакет из пяти параллельных правок одного
# теста — прошла первая, четыре отклонены «Исхода нет у повода: rework:…:1», файл остался наполовину правленым, и
# прогон краснел от половины изменения (корень R6: продолжение пакета и новая попытка отвечали стражу одним значением).
# Красная (1), пока правку пакета отклоняет ступень, поднятая его же первой правкой; 2 — рамка не собралась (контроль:
# ступень другого ответа и запись без идентификатора ответа обязаны дать отказ).
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/a"; gproj "$P" || exit 2
F="$P/hooks/x.sh"
batch_tr() {   # <файл> <id ответа> — реплика и ответ модели из трёх правок одного файла (параллельные вызовы делят id)
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    for i in 1 2 3; do
        jq -cn --arg m "$2" --arg f "$F" --arg i "t$i" \
            '{type:"assistant",message:{id:$m,role:"assistant",content:[{type:"tool_use",id:$i,name:"Edit",input:{file_path:$f}}]}}' >> "$1"
    done
}
fired() {   # <sid> <id ответа или пусто> — ступень 1 переработки x.sh, поднятая правкой этого ответа
    if [ -n "$2" ]; then
        printf '{"ts":"2026-11-10T03:00:00Z","msg":"%s","path":"%s","cycles":2}\n' "$2" "$F" > "$ST/rework-fired-$1.jsonl"
    else
        printf '{"ts":"2026-11-10T03:00:00Z","path":"%s","cycles":2}\n' "$F" > "$ST/rework-fired-$1.jsonl"
    fi
}
batch_tr "$SB/tb.jsonl" msg_B
fired s2 msg_A
[ "$(dec "$(cw s2 "$F" "$SB/tb.jsonl" "$P")")" = deny ] || { echo "рамка: ступень другого ответа не дала отказа" >&2; exit 2; }
fired s3 ""
[ "$(dec "$(cw s3 "$F" "$SB/tb.jsonl" "$P")")" = deny ] || { echo "рамка: запись без идентификатора ответа не дала отказа" >&2; exit 2; }
batch_tr "$SB/ta.jsonl" msg_A
fired s1 msg_A
[ "$(dec "$(cw s1 "$F" "$SB/ta.jsonl" "$P")")" = deny ] && { echo "правку пакета отклонила ступень, поднятая первой правкой того же ответа"; exit 1; }
# Пропуск — паре «ответ, файл» (скептик opus по 63da421a, H1): правка ДРУГОГО файла того же ответа и запись оболочкой в
# том же ответе судятся как прежде — отказ; иначе ступень первого файла заслонялась ступенью второго и не требовалась никогда.
fired s4 msg_A
[ "$(dec "$(cw s4 "$P/hooks/y.sh" "$SB/ta.jsonl" "$P")")" = deny ] || { echo "правку другого файла того же ответа пропустила ступень первого файла"; exit 1; }
fired s5 msg_A
_bw=$(jq -cn --arg p "$SB/ta.jsonl" --arg d "$P" \
    '{session_id:"s5", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:"git commit -qam wip"}}' \
    | STATE_DIR="$ST" bash "$HOOK" 2>/dev/null)
[ "$(dec "$_bw")" = deny ] || { echo "запись оболочкой того же ответа прошла мимо ступени"; exit 1; }
# Детектор кладёт идентификатор ответа в запись ступени: правка → прогон → правка (ход probe_D1268, каталог внутри
# каталога сессии — файл проекта), последняя запись ответа в расшифровке несёт `message.id`.
DET="$R/hooks/rework-detector.sh"; [ -f "$DET" ] || exit 2
P2="$SB/tmp/proj"; mkdir -p "$P2" || exit 2; T2="$P2/t.sh"; printf 'x\n' > "$T2"
TR="$SB/tr.jsonl"; batch_tr "$TR" msg_C
ed() { jq -cn --arg p "$1" --arg d "$P2" --arg t "$TR" \
        '{session_id:"s9", tool_name:"Edit", tool_input:{file_path:$p}, cwd:$d, transcript_path:$t}' \
        | STATE_DIR="$ST" bash "$DET" >/dev/null 2>&1; }
hk() { jq -cn --arg d "$P2" --arg t "$TR" '{session_id:"s9", tool_name:"Bash", tool_input:{command:"bash test.sh"}, cwd:$d, transcript_path:$t}' \
        | STATE_DIR="$ST" bash "$DET" >/dev/null 2>&1; }
ed /repo/seed.sh; ed "$T2"; hk; ed "$T2"
[ -s "$ST/rework-fired-s9.jsonl" ] || { echo "рамка: ступень детектором не поднята — ход не сложился" >&2; exit 2; }
grep -qF '"msg":"msg_C","path":"'"$T2"'"' "$ST/rework-fired-s9.jsonl" || { echo "детектор не записал идентификатор ответа в ступень"; exit 1; }
exit 0
