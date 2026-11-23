#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1033.sh — отказ стража разбора снимается СЛЕДОМ РАЗБОРА, а не числом чтений; текст отказа речи не требует.
#
# Повод (23 октября 2026, решение владельца «вернуть как в сентябре»): журналы исходов по полумесяцам — разборов с
# ≥3 «почему» 216 и 126 в сентябре, 50 и 5 в октябре; «снято чтениями» 0, 0 → 210, 287. Обрыв на D513 (4 октября):
# три любых чтения снимали отказ без следа разбора, и починка симптома проходила мимо стража (B535).
#
# Ноги: (1) запись при поводе отказана, текст отказа не требует произнести цепочку (довод D513 — фильтр API);
# (2) три чтения после повода отказа не снимают; (3) след разбора в тексте хода (`rc_chain_spoken`) снимает —
# положительный контроль: сентябрьский механизм жив.
# Код: 0 — все три держат; 1 — нога красная (названа); 2 — нечем мерить.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GATE="$REPO/hooks/five-whys-gate.sh"
[ -f "$GATE" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/hooks" "$T/state"
export STATE_DIR="$T/state"
RED=0
tr_new() { printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$1"
           jq -cn --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"; }
write() { jq -cn --arg s "$1" --arg d "$P" --arg f "$P/hooks/x.sh" --arg p "$2" \
            '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Write", cwd:$d, tool_input:{file_path:$f, content:"x"}}' \
          | bash "$GATE" 2>/dev/null; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null)" = "deny" ]; }
read_add() { jq -cn --arg f "$P/hooks/$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:$f}}]}}' >> "$1"; }

# (1) и (2): повод с правом на отказ, разбора нет.
TR="$T/a.jsonl"; tr_new "$TR" "Правлю строку."; touch "$STATE_DIR/error_streak_fired_a"
OUT=$(write a "$TR")
denied "$OUT" || { echo "КОНТРОЛЬ: запись при поводе не отказана — пробе нечего судить"; exit 2; }
grep -qE "произнесена|произнес[ти]|цепочк[ауи] «почему»|звен" <<< "$OUT" \
    && { echo "КРАСНАЯ: текст отказа требует РЕЧИ модели (довод D513)"; RED=1; }
read_add "$TR" a.sh; read_add "$TR" b.sh; read_add "$TR" c.sh
denied "$(write a "$TR")" || { echo "КРАСНАЯ: три чтения сняли отказ без следа разбора"; RED=1; }

# (3) след разбора в тексте хода снимает отказ.
TR="$T/b.jsonl"; touch "$STATE_DIR/error_streak_fired_b"
tr_new "$TR" "Почему упало — читался старый индекс (mcp-server/indexer.py:231). Почему старый — add шёл после. Почему не поймали — тест брал фикстуру."
denied "$(write b "$TR")" && { echo "КРАСНАЯ: след разбора в тексте хода отказ не снял"; RED=1; }
exit "$RED"
