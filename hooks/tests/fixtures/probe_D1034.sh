#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# probe_D1034.sh — повод, чей отказ снят в том же ходе, кончается в журнале исходов исходом снятия
# (`chain-spoken` — разбором, `recorded` — названным исходом; до D1035 второй путь — `looked` осмотром), а не `deferred`.
#
# Повод (23 октября 2026, финальный скептик D1033): `rc_log_outcome` пропускает запись, если у пары «ход, сигнал» исход
# уже есть. Отказ пишет `deferred`, и снятие того же хода второй записи не оставляло: «отложено и брошено» и «отложено,
# снято, пропущено» давали одно значение (корень R6). Второй путь снятия той же парой: до D1035 — осмотр (`looked`),
# с D1035 — названный исход (`recorded`).
#
# Две сессии, по ноге на путь снятия. В каждой: (1) контроль — запись при поводе без исхода отказана и пишет `deferred`;
# (2) снятие — разбором в тексте хода (сессия s) либо названным исходом повода (сессия l: пункт фикстуры и настоящая
# команда `scripts/outcome.sh`) — пропускает запись;
# (3) ПОСЛЕДНИЙ исход пары «ход, сигнал» в журнале — исход снятия.
# Код: 0 — держит; 1 — нога красная (названа); 2 — нечем мерить.
# Рамка — outcome_frame_lib.sh (D1109): названный исход принимает настоящая команда `scripts/outcome.sh` (с D1104/D1106
# исход принимается только сверенным: свежий пункт с корнем и адресом цели отказа), журнал пишет настоящий страж.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
GATE="$HOOK"; STATE_DIR="$ST"; T="$SB"
P="$SB/proj"; gproj "$P" || exit 2
write() { cw "$1" "$P/hooks/x.sh" "$T/$1.jsonl" "$P"; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null)" = "deny" ]; }
say()  { jq -cn --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$T/$1.jsonl"; }
last() { jq -r --arg k "$2" --arg s "$3" 'select(.key == $k and .signal == $s) | .outcome' "$STATE_DIR/outcome-$1.jsonl" | tail -1; }

# refuse <sid> — повод стоит, запись отказана, `deferred` записан; KEY и SIG — пара отказа.
refuse() {
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$T/$1.jsonl"
    say "$1" "Правлю строку."
    touch "$STATE_DIR/error_streak_fired_$1"
    denied "$(write "$1")" || { echo "КОНТРОЛЬ ($1): запись при поводе не отказана — пробе нечего судить"; exit 2; }
    J="$STATE_DIR/outcome-$1.jsonl"
    jq -e 'select(.outcome == "deferred")' "$J" >/dev/null 2>&1 || { echo "КОНТРОЛЬ ($1): отказ не записал deferred"; exit 2; }
    SIG=$(jq -r 'select(.outcome == "deferred") | .signal' "$J" | head -1)
    KEY=$(jq -r 'select(.outcome == "deferred") | .key' "$J" | head -1)
}

# Сессия s: снятие разбором в тексте того же хода.
refuse s
say s "Почему упало — читался старый индекс (mcp-server/indexer.py:231). Почему старый — add шёл после. Почему не поймали — тест брал фикстуру."
denied "$(write s)" && { echo "КОНТРОЛЬ (s): разбор в тексте хода отказ не снял — пробе нечего судить"; exit 2; }
L=$(last s "$KEY" "$SIG")
[ "$L" = "chain-spoken" ] || { echo "КРАСНАЯ: повод «${SIG}», отказ которого снят разбором того же хода, кончается исходом «${L}», а не chain-spoken"; exit 1; }

# Сессия l: снятие названным исходом повода после отказа.
refuse l
item "$P/BACKLOG.md" D9934 "hooks/x.sh:5"
no l debt "$SIG" D9934 "$P" || { echo "КОНТРОЛЬ (l): команда исхода не приняла свежий пункт по цели отказа — рамка не собралась"; exit 2; }
denied "$(write l)" && { echo "КОНТРОЛЬ (l): названный исход отказ не снял — пробе нечего судить"; exit 2; }
L=$(last l "$KEY" "$SIG")
[ "$L" = "recorded" ] || { echo "КРАСНАЯ: повод «${SIG}», отказ которого снят названным исходом того же хода, кончается исходом «${L}», а не recorded"; exit 1; }
exit 0
